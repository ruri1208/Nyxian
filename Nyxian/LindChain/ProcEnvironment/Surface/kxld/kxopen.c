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

#include <LindChain/ProcEnvironment/Utils/klog.h>
#include <LindChain/ProcEnvironment/Surface/kxld/kxopen.h>
#include <LindChain/ProcEnvironment/Surface/kxld/validation.h>
#include <LindChain/ProcEnvironment/Surface/kxld/mapper.h>
#include <LindChain/ProcEnvironment/Surface/kxld/fixup.h>
#include <LindChain/ProcEnvironment/Surface/kxld/reseal.h>
#include <LindChain/ProcEnvironment/Surface/kxld/image.h>
#include <LindChain/ProcEnvironment/Surface/kxld/kmod.h>
#include <LindChain/ProcEnvironment/Surface/kxld/export.h>
#include <LindChain/ProcEnvironment/Surface/kxld/init.h>
#include <LindChain/ProcEnvironment/Surface/kxld/objc.h>
#include <LindChain/ProcEnvironment/Surface/kxld/resolve.h>
#include <LindChain/ProcEnvironment/Surface/trust/signing.h>
#include <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#include <LindChain/ProcEnvironment/Shims/panic.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/param.h>
#include <mach-o/loader.h>
#include <mach-o/ldsyms.h>
#include <os/lock.h>
#include <pthread.h>

static os_unfair_lock g_kxld_lock = OS_UNFAIR_LOCK_INIT;

void *ksurface_kext_thread(void *ii)
{
    kxld_image_info_t *image_info = (kxld_image_info_t*)ii;
    
    /* invoking kextension start */
    klog_log("kxld:thread", "[%p] spinning up kext", image_info);
    image_info->mod->start();
    if(!(image_info->mod->flags & KMOD_FLAG_PERSISTENT))
    {
        /*kext_table_wrlock();
        kext_object_t *found = radix_remove(&(ksurface->kext_info.kexts), kext_object->key);
        kext_table_unlock();*/
        
        /*if(found == NULL)
        {
            /* kext was already removed */
            /*return NULL;
        }
        klog_log("ksurface:kext:thread", "[%p] removing kext", kext_object->image_info);
        
        kext_object->mod->stop();
        if(kext_object->mod->deinit)
        {
            kern_return_t kr = kext_object->mod->deinit();
            if(kr != KERN_SUCCESS)
            {
                environment_panic("kext with key %llu failed to deinitialize: %s", kext_object->key, mach_error_string(kr));
            }
        }
        kxclose(kext_object->image_info);
        free(kext_object);*/
    }
    
    return NULL;
}

static void kxdestroy_image(kxld_image_info_t *image_info)
{
    if(image_info->base != NULL)
    {
        munmap(image_info->base, image_info->len);
    }
    free(image_info->deps);
    free(image_info);
}

kxld_image_info_t *kxopen(const char *path,
                          int mode)
{
    int fd = open(path, O_RDWR);
    if(fd < 0)
    {
        return NULL;
    }
    
    kxld_image_info_t *image_info = kxopen_with_fd(fd, mode);
    close(fd);
    return image_info;
}

kxld_image_info_t *kxopen_with_fd(int fd,
                                  int mode)
{
    os_unfair_lock_lock(&g_kxld_lock);
    if(fd < 0)
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        errno = EINVAL;
        return NULL;
    }
    
    /* map machO */
    LCMachO *machO = LCMapMachOFromFDRO(fd);
    if(machO == NULL)
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        return NULL;
    }
    
    /* validating header of kext */
    if(machO->header->filetype != MH_KEXT_BUNDLE ||
       machO->header->cputype != CPU_TYPE_ARM64)
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        errno = ENOEXEC;
        LCUnmapMachO(machO);
        return NULL;
    }
    
    /* checking if the kernel says(double meaning x3) this is signed */
    if(!KXValidateCodeSignature(machO))
    {
        /* sets errno */
        os_unfair_lock_unlock(&g_kxld_lock);
        LCUnmapMachO(machO);
        return NULL;
    }
    
    kxld_image_info_t *image_info = calloc(1, sizeof(kxld_image_info_t));
    if(image_info == NULL)
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        errno = ENOMEM;
        LCUnmapMachO(machO);
        return NULL;
    }
    
    if(fcntl(machO->fd, F_GETPATH, image_info->path) != 0)
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        errno = ENOMEM;
        LCUnmapMachO(machO);
        free(image_info);
        return NULL;
    }
    
    bool success = KXMapMachOExecutable(machO, image_info);
    LCUnmapMachO(machO);
    if(!success)
    {
        /* sets errno */
        os_unfair_lock_unlock(&g_kxld_lock);
        kxdestroy_image(image_info);
        return NULL;
    }
    
    /* now let the fixup */
    if(!KXApplyFixups(image_info))
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        kxdestroy_image(image_info);
        return NULL;
    }
    
    /* now we gotta get kmod */
    if(!KXLocateKmod(image_info))
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        kxdestroy_image(image_info);
        return NULL;
    }
    
    /* resolve dependencies versions */
    for(uint32_t i = 0; i < image_info->ndeps; i++)
    {
        kxld_image_info_t *depImageInfo;
        kern_return_t kr = KXGetRegisteredKextForIdentifier(image_info->deps[i].identifier, &depImageInfo);
        if(kr != KERN_SUCCESS)
        {
            os_unfair_lock_unlock(&g_kxld_lock);
            kxdestroy_image(image_info);
            errno = EACCES;
            return NULL;
        }
        
        if(depImageInfo->mod->version < image_info->deps[i].min_version ||
           depImageInfo->mod->version > image_info->deps[i].max_version)
        {
            os_unfair_lock_unlock(&g_kxld_lock);
            kxdestroy_image(image_info);
            errno = EACCES;
            return NULL;
        }
        
        /* so the kext knows on what version this dependency is */
        image_info->mod->dependencies[i].min_version = depImageInfo->mod->version;
        image_info->mod->dependencies[i].max_version = depImageInfo->mod->version;
    }
    
    /* still very unmappable */
    if(KXRegisterKext(image_info) != KERN_SUCCESS)
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        kxdestroy_image(image_info);
        errno = EEXIST;
        return NULL;
    }
    
    /* now the spicy port with the symbol exports */
    if(!KXRegisterKextExports(image_info))
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        kxdestroy_image(image_info);
        return NULL;
    }
    
    if(!KXRegisterObjCImage(image_info))
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        kxdestroy_image(image_info);
        return NULL;
    }
    
    /* now resealing */
    if(!KXResealDataConst(image_info))
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        kxdestroy_image(image_info);
        return NULL;
    }
    
    if(!KXRunInitializers(image_info))
    {
        os_unfair_lock_unlock(&g_kxld_lock);
        kxdestroy_image(image_info);
        return NULL;
    }
    
    /* now lets initialize the kext it self */
    if(image_info->mod->init)
    {
        kern_return_t kr = image_info->mod->init();
        if(kr != KERN_SUCCESS)
        {
            klog_log("kxld", "kext @ %s, had a failure initializing: %s", image_info->path, mach_error_string(kr));
            os_unfair_lock_unlock(&g_kxld_lock);
            kxdestroy_image(image_info);
            errno = EBADEXEC;
            return NULL;
        }
    }
    
    if(image_info->mod->start)
    {
        pthread_t thread;
        if(pthread_create(&thread, NULL, ksurface_kext_thread, (void*)image_info) != 0)
        {
            if(image_info->mod->deinit)
            {
                kern_return_t kr = image_info->mod->deinit();
                if(kr != KERN_SUCCESS)
                {
                    environment_panic("kext @ %s failed to deinitialize: %s", image_info->path, mach_error_string(kr));
                }
            }
            klog_log("kxld", "failed start thread for kext object");
            os_unfair_lock_unlock(&g_kxld_lock);
            kxdestroy_image(image_info);
            return NULL;
        }
        pthread_detach(thread);
    }
    
    /* done =3 */
    klog_log("kxld", "successfully initialized kext of %s @ %p", image_info->path, image_info);
    os_unfair_lock_unlock(&g_kxld_lock);
    return image_info;
}

void kxclose(kxld_image_info_t *image_info)
{
    os_unfair_lock_lock(&g_kxld_lock);
    klog_log("kxld", "unloading kext of @ %p", image_info);
    
    /* finding kext object */
    if(!(image_info->mod->flags & KMOD_FLAG_PERSISTENT))
    {
        /* now we can remove it again */
        klog_log("ksurface:kext:unload", "stopping kext");
        kern_return_t kr;
        if(image_info->mod->stop)
        {
            kr = image_info->mod->stop();
            if(kr != KERN_SUCCESS)
            {
                environment_panic("kext with key @ %p failed to stop: %s", image_info, mach_error_string(kr));
            }
        }
        if(image_info->mod->deinit)
        {
            kr = image_info->mod->deinit();
            if(kr != KERN_SUCCESS)
            {
                environment_panic("kext @ %p failed to deinitialize: %s", image_info, mach_error_string(kr));
            }
        }
        kxdestroy_image(image_info);
        return;
    }
    else
    {
        klog_log("kxld", "kext @ %p is marked as not unloadable", image_info);
        os_unfair_lock_unlock(&g_kxld_lock);
        return;
    }
    
    
    klog_log("ksurface:kext:unload", "successfully unloaded kext @ %p", image_info);
    os_unfair_lock_unlock(&g_kxld_lock);
    return;
}
