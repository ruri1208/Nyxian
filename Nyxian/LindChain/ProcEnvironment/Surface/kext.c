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
#include <LindChain/ProcEnvironment/Utils/dlfcn.h>
#include <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#include <LindChain/ProcEnvironment/Surface/trust/signing.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <pthread.h>
#include <assert.h>
#include <os/lock.h>

static bool macho_name_eq(const char *field,
                          size_t field_size,
                          const char *want)
{
    size_t have = strnlen(field, field_size);
    size_t want_len = strlen(want);
    return have == want_len && memcmp(field, want, want_len) == 0;
}

static bool range_ok(uint64_t off,
                     uint64_t len,
                     uint64_t total)
{
    return len <= total && off <= total - len;
}

static const uint8_t *ksurface_locate_modinfo(const uint8_t *base,
                                              size_t size,
                                              uint64_t *out_len)
{
    if(size < sizeof(struct mach_header_64))
    {
        return NULL;
    }
    
    const struct mach_header_64 *mh = (const struct mach_header_64 *)base;
    if(mh->magic != MH_MAGIC_64)
    {
        return NULL;
    }
    if(mh->filetype != MH_DYLIB && mh->filetype != MH_BUNDLE)
    {
        return NULL;
    }
    if(!range_ok(sizeof(*mh), mh->sizeofcmds, size))
    {
        return NULL;
    }
    
    const uint8_t *cursor = base + sizeof(*mh);
    const uint8_t *lc_end = cursor + mh->sizeofcmds;
    for(uint32_t i = 0; i < mh->ncmds; i++)
    {
        if((uint64_t)(lc_end - cursor) < sizeof(struct load_command))
        {
            return NULL;
        }
        
        const struct load_command *lc = (const struct load_command *)cursor;
        if(lc->cmdsize < sizeof(struct load_command) ||
           (lc->cmdsize & 0x7) ||
           lc->cmdsize > (uint64_t)(lc_end - cursor))
        {
            return NULL;
        }
        
        if(lc->cmd == LC_SEGMENT_64)
        {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
            if(lc->cmdsize < sizeof(*seg))
            {
                return NULL;
            }
            
            if(macho_name_eq(seg->segname, sizeof(seg->segname), SEG_DATA) ||
               macho_name_eq(seg->segname, sizeof(seg->segname), "__DATA_CONST"))
            {
                uint64_t need = sizeof(*seg) + (uint64_t)seg->nsects * sizeof(struct section_64);
                if(lc->cmdsize < need)
                {
                    return NULL;
                }
                
                const struct section_64 *sec = (const struct section_64 *)(cursor + sizeof(*seg));
                
                for(uint32_t j = 0; j < seg->nsects; j++)
                {
                    if(!macho_name_eq(sec[j].sectname, sizeof(sec[j].sectname), "__ksurfacemod"))
                    {
                        continue;
                    }
                    
                    uint32_t type = sec[j].flags & SECTION_TYPE;
                    if(type == S_ZEROFILL || type == S_THREAD_LOCAL_ZEROFILL)
                    {
                        return NULL;
                    }
                    
                    if(!range_ok(sec[j].offset, sec[j].size, size))
                    {
                        return NULL;
                    }
                    
                    *out_len = sec[j].size;
                    return base + sec[j].offset;
                }
            }
        }
        cursor += lc->cmdsize;
    }
    return NULL;
}

kern_return_t ksurface_kext_copy_kmod(const char *path,
                                      kinfo_mod_t *out_info,
                                      kmod_dependency_t **out_deps,
                                      uint32_t *out_dep_count)
{
    kern_return_t kr = KERN_NOT_FOUND;
    kinfo_mod_t info = {};
    kmod_dependency_t *deps = NULL;
    const uint8_t *blob = NULL;
    uint64_t sec_len = 0;
    uint32_t ndeps = 0;
    void *map = MAP_FAILED;
    size_t size = 0;
    struct stat st;
    int fd;
    
    if(path == NULL || out_info == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }
    if(out_deps)
    {
        *out_deps = NULL;
    }
    if(out_dep_count)
    {
        *out_dep_count = 0;
    }
    
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if(fd < 0)
    {
        return KERN_FAILURE;
    }
    
    if(fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size <= 0)
    {
        close(fd);
        return KERN_FAILURE;
    }
    size = (size_t)st.st_size;
    
    map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if(map == MAP_FAILED)
    {
        return KERN_FAILURE;
    }
    
    blob = ksurface_locate_modinfo(map, size, &sec_len);
    if(blob == NULL)
    {
        goto out;
    }
    
    if(sec_len < sizeof(kinfo_mod_t))
    {
        kr = KERN_INVALID_ARGUMENT;
        goto out;
    }
    memcpy(&info, blob, sizeof(info));
    
    if(info.magic != KSURFACE_KMOD_MAGIC ||
       info.abi_version != KSURFACE_KMOD_ABI_VERSION ||
       strnlen(info.identifier, KMOD_MAX_NAME) == KMOD_MAX_NAME)
    {
        kr = KERN_INVALID_ARGUMENT;
        goto out;
    }
    
    info.init = NULL;
    info.start = NULL;
    info.stop  = NULL;
    
    ndeps = info.dependency_count;
    if(ndeps > KMOD_MAX_DEPENDENCIES ||
       sec_len < sizeof(kinfo_mod_t) + (uint64_t)ndeps * sizeof(kmod_dependency_t))
    {
        kr = KERN_INVALID_ARGUMENT;
        goto out;
    }
    
    if(ndeps > 0 && out_deps != NULL)
    {
        deps = calloc(ndeps, sizeof(*deps));
        if(deps == NULL)
        {
            kr = KERN_RESOURCE_SHORTAGE;
            goto out;
        }
        
        memcpy(deps, blob + sizeof(kinfo_mod_t), ndeps * sizeof(*deps));
        
        for(uint32_t i = 0; i < ndeps; i++)
        {
            if(strnlen(deps[i].identifier, KMOD_MAX_NAME) == KMOD_MAX_NAME)
            {
                free(deps);
                kr = KERN_INVALID_ARGUMENT;
                goto out;
            }
        }
        *out_deps = deps;
    }
    
    if(out_dep_count)
    {
        *out_dep_count = ndeps;
    }
    memcpy(out_info, &info, sizeof(info));
    kr = KERN_SUCCESS;
    
out:
    munmap(map, size);
    return kr;
}

void ksurface_kext_free_deps(kmod_dependency_t *deps)
{
    free(deps);
}

typedef struct {
    uint64_t key;
    void *handle;
    const kinfo_mod_t *mod;
} kext_object_t;

void *ksurface_kext_thread(void *obj)
{
    kext_object_t *kext_object = (kext_object_t*)obj;
    
    /* invoking kextension start */
    klog_log("ksurface:kext:thread", "[%p] spinning up kext", kext_object->handle);
    kext_object->mod->start();
    if(!(kext_object->mod->flags & KMOD_FLAG_PERSISTENT))
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
        
        kext_object->mod->stop();
        if(kext_object->mod->deinit)
        {
            kern_return_t kr = kext_object->mod->deinit();
            if(kr != KERN_SUCCESS)
            {
                environment_panic("kext with key %llu failed to deinitialize: %s", kext_object->key, mach_error_string(kr));
            }
        }
        dlclose(kext_object->handle);
        free(kext_object);
    }
    
    return NULL;
}

kern_return_t ksurface_kext_load_at_path(const char *path,
                                         uint64_t *key)
{
    assert(path != NULL && key != NULL);
    
    uint64_t randomKey;
    arc4random_buf(&randomKey, sizeof(randomKey));
    
    kext_table_wrlock();
    klog_log("ksurface:kext:load", "path: %s", path);
    
    /* first checking the validity of the kext */
    LCMachO *machO = LCMapMachO(path, true);
    if(machO == NULL)
    {
        klog_log("ksurface:kext:load", "failed to map MachO of kext");
        kext_table_unlock();
        return KERN_FAILURE;
    }
    
    if(!LCCheckCodeSignature(machO))
    {
        klog_log("ksurface:kext:load", "MachO of kext is unsigned apple wise, cannot continue");
        kext_table_unlock();
        LCUnmapMachO(machO);
        return KERN_DENIED;
    }
    
    ksurface_nxt2_t nxt2 = {};
    kern_return_t kr = trust_nxt2_read_fd(machO->fd, &nxt2);
    if(kr != KERN_SUCCESS ||
       !nxt2.isValid ||
       !nxt2.isCdHashValid ||
       !nxt2.isSigned)
    {
        klog_log("ksurface:kext:load", "MachO of kext is incorrectly signed, cannot continue");
        kext_table_unlock();
        LCUnmapMachO(machO);
        if(nxt2.entitlements != NULL)
        {
            CFRelease(nxt2.entitlements);
        }
        return KERN_DENIED;
    }
    
    Boolean hasEntitlement = CFDictionaryGetValue(nxt2.entitlements, kNXT2EntitlementKsurfaceKEXTLoading) != kCFBooleanTrue;
    CFRelease(nxt2.entitlements);
    if(hasEntitlement)
    {
        klog_log("ksurface:kext:load", "MachO of kext is incorrectly signed, cannot continue");
        kext_table_unlock();
        LCUnmapMachO(machO);
        return KERN_DENIED;
    }
    
    /* finding out if this is already loaded */
    void *loadedHandle = dlopen_from_fd(machO->fd, RTLD_NOLOAD | RTLD_EXACT_PATH);
    if(loadedHandle != NULL)
    {
        klog_log("ksurface:kext:load", "kext %s is already loaded", path);
        dlclose(loadedHandle);  /* dropping the refcount back */
        kext_table_unlock();
        LCUnmapMachO(machO);
        return KERN_NAME_EXISTS;
    }
    
    /* loading kernel extension into address space */
    loadedHandle = dlopen_from_fd(machO->fd, RTLD_LAZY | RTLD_EXACT_PATH);
    LCUnmapMachO(machO);
    if(loadedHandle == NULL)
    {
        klog_log("ksurface:kext:load", "failed to load handle: %s", dlerror());
        kext_table_unlock();
        return KERN_INVALID_ARGUMENT;
    }
    else
    {
        klog_log("ksurface:kext:load", "got handle for kext @ %p", loadedHandle);
    }
    
    /* checking if extension has what is necessary */
    const kinfo_mod_t *liveMod = dlsym(loadedHandle, "ksurface_kext_info");
    if(liveMod == NULL)
    {
        klog_log("ksurface:kext:load", "start or exit symbols are missing in kext, cannot continue loading");
        dlclose(loadedHandle);
        kext_table_unlock();
        return KERN_INVALID_OBJECT;
    }
    
    /* initializing kext object */
    if(liveMod->init)
    {
        kr = liveMod->init();
        if(kr != KERN_SUCCESS)
        {
            klog_log("ksurface:kext:load", "kext @ %s, had a failure initializing: %s", path, mach_error_string(kr));
            dlclose(loadedHandle);
            kext_table_unlock();
            return kr;
        }
    }
    
    /* safety checks are complete so now the object ^^ */
    kext_object_t *object = calloc(1, sizeof(kext_object_t));
    if(object == NULL)
    {
        if(liveMod->deinit)
        {
            kr = liveMod->deinit();
            if(kr != KERN_SUCCESS)
            {
                environment_panic("kext @ %s failed to deinitialize: %s", path, mach_error_string(kr));
            }
        }
        klog_log("ksurface:kext:load", "failed to allocate kext object");
        dlclose(loadedHandle);
        kext_table_unlock();
        return KERN_NO_SPACE;
    }
    
    object->key = randomKey;
    object->handle = loadedHandle;
    object->mod = liveMod;
    
    /* inserting kext object */
    if(radix_insert(&(ksurface->kext_info.kexts), randomKey, object) != 0)
    {
        if(liveMod->deinit)
        {
            kr = liveMod->deinit();
            if(kr != KERN_SUCCESS)
            {
                environment_panic("kext @ %s failed to deinitialize: %s", path, mach_error_string(kr));
            }
        }
        klog_log("ksurface:kext:load", "failed to insert kext object into radix tree");
        free(object);
        dlclose(loadedHandle);
        kext_table_unlock();
        return KERN_FAILURE;
    }
    
    /* now we can safely load it */
    if(liveMod->start)
    {
        pthread_t thread;
        if(pthread_create(&thread, NULL, ksurface_kext_thread, (void*)object) != 0)
        {
            if(liveMod->deinit)
            {
                kr = liveMod->deinit();
                if(kr != KERN_SUCCESS)
                {
                    environment_panic("kext @ %s failed to deinitialize: %s", path, mach_error_string(kr));
                }
            }
            radix_remove(&(ksurface->kext_info.kexts), *key);
            klog_log("ksurface:kext:load", "failed start thread for kext object");
            free(object);
            dlclose(loadedHandle);
            kext_table_unlock();
            return KERN_FAILURE;
        }
        pthread_detach(thread);
    }
    kext_table_unlock();
    
    /* done =3 */
    klog_log("ksurface:kext:load", "successfully initialized kext of %s @ %p", path, loadedHandle);
    *key = randomKey;
    return KERN_SUCCESS;
}

kern_return_t ksurface_kext_unload_with_key(uint64_t key)
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
    
    if(!(found->mod->flags & KMOD_FLAG_PERSISTENT))
    {
        /* now we can remove it again */
        klog_log("ksurface:kext:unload", "stopping kext");
        kern_return_t kr;
        if(found->mod->stop)
        {
            kr = found->mod->stop();
            if(kr != KERN_SUCCESS)
            {
                environment_panic("kext with key %llu failed to stop: %s", found->key, mach_error_string(kr));
            }
        }
        if(found->mod->deinit)
        {
            kr = found->mod->deinit();
            if(kr != KERN_SUCCESS)
            {
                environment_panic("kext with key %llu failed to deinitialize: %s", found->key, mach_error_string(kr));
            }
        }
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
