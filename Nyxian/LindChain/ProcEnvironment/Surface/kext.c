/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#include <LindChain/ProcEnvironment/Surface/surface.h>
#include <LindChain/ProcEnvironment/Surface/kext.h>
#include <LindChain/ProcEnvironment/Utils/klog.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <pthread.h>
#include <assert.h>
#include <os/lock.h>

/*
 * can be blocking, it runs on its own thread and
 * is allowed to run for ever unless XNU denies it.
 *
 * when the thread exits and isUnloadable is set
 * to true it will attempt to unload through DYLD.
 *
 * this is not a toy API once a malicious kext is
 * loaded there is unfourtunetly nothing I can do
 * to safe your data, use this API at your own risk.
 * May the gods of kernel engineering be with you
 * my friend.
 */
typedef void (*kextension_start_handler_t)(ksurface_mapping_t *km);
typedef void (*kextension_exit_handler_t)(void);    /* It must block till everything is torn down */
typedef bool (*kextension_is_unloadable_handler_t)(void);

/*
 * looks at the back at you... don't think I don't
 * see what you're wanting to do.
 *
 * If you don't match ABI expectations of how kext's
 * work on ksurface then your kext is automatically a
 * malicious kext.
 */

typedef struct {
    uint64_t key;
    void *handle;
    bool isUnloadable;
    kextension_start_handler_t start;
    kextension_exit_handler_t exit;
} kext_object_t;

void *kext_thread(void *obj)
{
    kext_object_t *kext_object = (kext_object_t*)obj;
    
    /* invoking kextension start */
    klog_log("ksurface:kext:thread", "[%p] spinning up kext", kext_object->handle);
    kext_object->start(ksurface);
    if(kext_object->isUnloadable)
    {
        kext_table_wrlock();
        kext_object_t *found = radix_remove(&(ksurface->kext_info.kexts), kext_object->key);
        kext_table_unlock();
        
        if(found == NULL)
        {
            /* kext was already removed */
            return NULL;
        }
        klog_log("ksurface:kext:thread", "[%p] removing kext", kext_object->handle);
        
        kext_object->exit();
        dlclose(kext_object->handle);
        free(kext_object);
    }
    else
    {
        klog_log("ksurface:kext:thread", "[%p] kext doesnt't want to be unloaded", kext_object->handle);
    }
    
    return NULL;
}

kern_return_t kext_load_at_path(const char *path,
                                uint64_t *key)
{
    assert(path != NULL && key != NULL);
    
    uint64_t randomKey;
    arc4random_buf(&randomKey, sizeof(randomKey));
    
    kext_table_wrlock();
    klog_log("ksurface:kext:load", "path: %s", path);
    
    /* finding out if this is already loaded */
    void *loadedHandle = dlopen(path, RTLD_NOLOAD);
    if(loadedHandle != NULL)
    {
        klog_log("ksurface:kext:load", "kext %s is already loaded", path);
        dlclose(loadedHandle);  /* dropping the refcount back */
        kext_table_unlock();
        return KERN_NAME_EXISTS;
    }
    
    klog_log("ksurface:kext:load", "survived", path);
    
    /* loading kernel extension into address space */
    loadedHandle = dlopen(path, RTLD_LAZY);
    if(loadedHandle == NULL)
    {
        printf("%s\n", dlerror());
        klog_log("ksurface:kext:load", "failed to load handle: %s", dlerror());
        kext_table_unlock();
        return KERN_INVALID_ARGUMENT;
    }
    else
    {
        klog_log("ksurface:kext:load", "got handle for kext @ %p", loadedHandle);
    }
    
    /* checking if extension has what is necessary */
    kextension_start_handler_t start = dlsym(loadedHandle, "kextension_start");
    kextension_exit_handler_t exit = dlsym(loadedHandle, "kextension_exit");
    kextension_is_unloadable_handler_t unloadable = dlsym(loadedHandle, "kextension_is_unloadable");
    if(start == NULL ||
       exit == NULL ||
       unloadable == NULL)
    {
        klog_log("ksurface:kext:load", "start or exit symbols are missing in kext, cannot continue loading");
        dlclose(loadedHandle);
        kext_table_unlock();
        return KERN_INVALID_OBJECT;
    }
    
    /* safety checks are complete so now the object ^^ */
    kext_object_t *object = calloc(1, sizeof(kext_object_t));
    if(object == NULL)
    {
        klog_log("ksurface:kext:load", "failed to allocate kext object");
        dlclose(loadedHandle);
        kext_table_unlock();
        return KERN_NO_SPACE;
    }
    
    object->key = randomKey;
    object->handle = loadedHandle;
    object->start = start;
    object->exit = exit;
    object->isUnloadable = unloadable();
    
    /* inserting kext object */
    if(radix_insert(&(ksurface->kext_info.kexts), randomKey, object) != 0)
    {
        klog_log("ksurface:kext:load", "failed to insert kext object into radix tree");
        free(object);
        dlclose(loadedHandle);
        kext_table_unlock();
        return KERN_FAILURE;
    }
    
    /* now we can safely load it */
    pthread_t thread;
    if(pthread_create(&thread, NULL, kext_thread, (void*)object) != 0)
    {
        klog_log("ksurface:kext:load", "failed start thread for kext object");
        free(object);
        dlclose(loadedHandle);
        kext_table_unlock();
        return KERN_FAILURE;
    }
    pthread_detach(thread);
    kext_table_unlock();
    
    /* done =3 */
    klog_log("ksurface:kext:load", "successfully initialized kext of %s @ %p", path, loadedHandle);
    *key = randomKey;
    return KERN_SUCCESS;
}

kern_return_t kext_unload_with_key(uint64_t key)
{
    klog_log("ksurface:kext:unload", "unloading kext object key %llu", key);
    
    /* finding kext object */
    kext_table_wrlock();
    kext_object_t *found = radix_remove(&(ksurface->kext_info.kexts), key);
    kext_table_unlock();
    
    if(found == NULL)
    {
        klog_log("ksurface:kext:unload", "didn't found kext with key %llu", key);
        return KERN_NOT_FOUND;
    }
    else
    {
        klog_log("ksurface:kext:unload", "found kext object with handle @ %p", found->handle);
    }
    
    if(found->isUnloadable)
    {
        /* now we can remove it again */
        klog_log("ksurface:kext:unload", "stopping kext");
        found->exit();
        dlclose(found->handle);
        free(found);
        return KERN_SUCCESS;
    }
    else
    {
        klog_log("ksurface:kext:unload", "kext is marked as not unloadable");
        return KERN_DENIED;
    }
    
    
    klog_log("ksurface:kext:unload", "successfully unloaded kext obect handle @ %p", found->handle);
    return KERN_NOT_FOUND;
}
