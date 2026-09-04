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

#import <LindChain/IDEFoundation/NXBootstrap.h>
#import <LindChain/ProcEnvironment/Surface/shimcache/ptrcache.h>
#import <LindChain/ProcEnvironment/Surface/fs/mount.h>
#import <LindChain/ProcEnvironment/Utils/klog.h>
#import <LindChain/ProcEnvironment/litehook/litehook.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#include <string.h>
#include <mach/mach.h>
#include <mach/task_info.h>
#include <mach-o/dyld_images.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#import <Foundation/Foundation.h>

typedef struct {
    uint64_t signature;
    void *found;
} dyld_search_entry_t;

static struct dyld_all_image_infos *_alt_dyld_get_all_image_infos(void)
{
    static struct dyld_all_image_infos *result;
    if(result != NULL)
    {
        return result;
    }
    
    struct task_dyld_info dyldInfo = {0};
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);
    if(kr != KERN_SUCCESS ||
       dyldInfo.all_image_info_addr == 0)
    {
        return NULL;
    }
    
    result = (struct dyld_all_image_infos *)(uintptr_t)dyldInfo.all_image_info_addr;
    
    return result;
}


static void searchDyldFunctions(const char *base,
                                dyld_search_entry_t *entries,
                                size_t count)
{
    if(base == NULL || entries == NULL || count == 0)
    {
        return;
    }
    
    size_t remaining = count;
    
    for(size_t i = 0; i < count; i++)
    {
        entries[i].found = NULL;
    }
    
    for(size_t off = 0; off + sizeof(uint64_t) <= 0x80000; off += 4)
    {
        uint64_t value;
        memcpy(&value, base + off, sizeof(value));
        for(size_t i = 0; i < count; i++)
        {
            if(entries[i].found != NULL)
            {
                continue;
            }
            if(entries[i].signature != value)
            {
                continue;
            }
            entries[i].found =
            (void *)(base + off);
            if(--remaining == 0)
            {
                return;
            }
        }
    }
}


static kern_return_t findDyldFunctionPointers(uint64_t out[kDyldPtrCount])
{
    if(out == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    memset(out, 0, sizeof(uint64_t) * kDyldPtrCount);
    struct dyld_all_image_infos *infos = _alt_dyld_get_all_image_infos();
    if(infos == NULL)
    {
        klog_log("ptrcache:emit", "couldn't obtain dyld_all_image_infos");
        return KERN_FAILURE;
    }
    
    const char *dyldBase = (const char *)infos->dyldImageLoadAddress;
    if(dyldBase == NULL)
    {
        klog_log("ptrcache:emit", "dyldImageLoadAddress is NULL");
        return KERN_FAILURE;
    }
    
    dyld_search_entry_t entries[kDyldPtrCount] = {
        /* first shit */
        [kDyldPtrOpen] = {
            .signature = 0xD4001001D28000B0ULL,
            .found = NULL,
        },
        [kDyldPtrFcntl] = {
            .signature = 0xD4001001D2800B90ULL,
            .found = NULL,
        },
        [kDyldPtrFstat64] = {
            .signature = 0xD4001001D2802A70ULL,
            .found = NULL,
        },
        [kDyldPtrStat64] = {
            .signature = 0xD4001001D2802A50ULL,
            .found = NULL,
        },
        [kDyldPtrOpenat] = {
            .signature = 0xD4001001D28039F0ULL,
            .found = NULL,
        },
        
        /* 2nd shit */
        [kDyldLockUnlockFunc] = {
            .signature = 0x0,
            .found = NULL,
        },
    };
    searchDyldFunctions(dyldBase, entries, kDyldPtrOpenat + 1);
    
    /* now the shit that takes 20~30ms if not cached properly */
    const char *libdyldPath = "/usr/lib/system/libdyld.dylib";
    mach_header_u *libdyldHeader = LCGetLoadedImageHeader(0, libdyldPath);
    assert(libdyldHeader != NULL);
    void **lockUnlockPtr = NULL;
    void **vtableLibSystemHelpers = litehook_find_dsc_symbol(libdyldPath, "__ZTVN5dyld416LibSystemHelpersE");
    void *lockFunc = litehook_find_dsc_symbol(libdyldPath, "__ZNK5dyld416LibSystemHelpers42os_unfair_recursive_lock_lock_with_optionsEP26os_unfair_recursive_lock_s24os_unfair_lock_options_t");
#if DEBUG
    void *unlockFunc = litehook_find_dsc_symbol(libdyldPath, "__ZNK5dyld416LibSystemHelpers31os_unfair_recursive_lock_unlockEP26os_unfair_recursive_lock_s");
#endif /* DEBUG */
    while(!lockUnlockPtr)
    {
        if(vtableLibSystemHelpers[0] == lockFunc)
        {
            lockUnlockPtr = vtableLibSystemHelpers;
            NSCAssert(vtableLibSystemHelpers[1] == unlockFunc, @"dyld has changed: lock and unlock functions are not next to each other");
            break;
        }
        vtableLibSystemHelpers++;
    }
    
    entries[kDyldLockUnlockFunc].found = lockUnlockPtr;
    
    static const char *names[kDyldPtrCount] = {
        "open",
        "fcntl",
        "fstat64",
        "stat64",
        "openat",
        "lockUnlockFunc",
    };
    
    for(size_t i = 0; i < kDyldPtrCount; i++)
    {
        if(entries[i].found == NULL)
        {
            klog_log("ptrcache:emit", "couldn't find %s", names[i]);
            return KERN_FAILURE;
        }
        
        out[i] = (uint64_t)(uintptr_t)entries[i].found;
        klog_log("ptrcache:emit", "%s = 0x%llx", names[i], (unsigned long long)out[i]);
    }
    
    return KERN_SUCCESS;
}

kern_return_t ksurface_ptrcache_emit(void)
{
    uint64_t pointers[kDyldPtrCount];
    kern_return_t kr = findDyldFunctionPointers(pointers);
    if(kr != KERN_SUCCESS)
    {
        return kr;
    }
    
    NSData *data = [NSData dataWithBytes:pointers length:sizeof(pointers)];
    if(data == nil)
    {
        return KERN_RESOURCE_SHORTAGE;
    }
    
    NSURL *url = [NXBootstrap.shared.rootURL URLByAppendingPathComponent:@"mntfs/bootfs/ptrcache"];
    NSError *error = nil;
    if(![data writeToURL:url options:NSDataWritingAtomic error:&error])
    {
        klog_log("ptrcache:emit", "couldn't write dyld.ptrs: %@", error);
        return KERN_FAILURE;
    }
    klog_log("ptrcache:emit", "wrote %lu-byte pointer blob to %@", (unsigned long)data.length, url.path);
    
    return KERN_SUCCESS;
}
