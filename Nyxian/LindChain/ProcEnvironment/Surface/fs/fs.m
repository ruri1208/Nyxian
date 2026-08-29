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

#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <LindChain/ProcEnvironment/Utils/klog.h>
#include <LindChain/ProcEnvironment/Surface/fs/fs.h>
#include <LindChain/ProcEnvironment/Surface/fs/mount.h>
#include <LindChain/ProcEnvironment/Surface/fs/preserver.h>
#include <LindChain/ProcEnvironment/Surface/trust/signing.h>
#include <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#include <LindChain/ProcEnvironment/Surface/kext.h>
#include <LindChain/ProcEnvironment/Shims/panic.h>
#include <LindChain/ProcEnvironment/Utils/klog.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

NSString *kextFSRoot = nil;

kern_return_t ksurface_fs_init(void)
{
    const char *home = getenv("HOME");
    if(!home)
    {
        klog_log("ksurface:fs", "HOME unset");
        return KERN_FAILURE;
    }
    
    klog_log("ksurface:fs", "initializing mntfs");
    klog_log("ksurface:fs", "preparing userspace mounts");
    
    kextFSRoot = [NSString stringWithFormat:@"%s/Documents/mntfs/kextfs", home];
    
    /* main mounts */
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs", home] UTF8String], NULL);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/rootfs", home] UTF8String], NULL);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/devfs", home] UTF8String], NULL);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/bootfs", home] UTF8String], NULL);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/kextfs", home] UTF8String], NULL);
    
    /* bind mounts */
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs", home] UTF8String], [[NSString stringWithFormat:@"%s/Documents/rootfs", home] UTF8String]);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/bootfs/bootloader", home] UTF8String], NSBundle.mainBundle.bundlePath.UTF8String);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/bootfs/kext", home] UTF8String], [[NSString stringWithFormat:@"%s/Documents/mntfs/kextfs", home] UTF8String]);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/dev", home] UTF8String], [[NSString stringWithFormat:@"%s/Documents/mntfs/devfs", home] UTF8String]);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/boot", home] UTF8String], [[NSString stringWithFormat:@"%s/Documents/mntfs/bootfs", home] UTF8String]);
    
    /* root mounts */
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/tmp", home] UTF8String], NULL);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/var", home] UTF8String], NULL);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/var/mobile", home] UTF8String], NULL);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/var/root", home] UTF8String], NULL);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/usr/bin", home] UTF8String], NULL);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/usr/sbin", home] UTF8String], NULL);
    
    /* root bind mounts */
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/bin", home] UTF8String], [[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/usr/bin", home] UTF8String]);
    ksurface_fs_mount([[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/sbin", home] UTF8String], [[NSString stringWithFormat:@"%s/Documents/mntfs/rootfs/usr/sbin", home] UTF8String]);
    
    klog_log("ksurface:fs", "starting mount preserver");
    kern_return_t kr = ksurface_fs_preserver_kickstart();
    if(kr != KERN_SUCCESS)
    {
        klog_log("ksurface:fs", "failed to start mount preserver");
        return KERN_FAILURE;
    }
    
    return kr == KERN_SUCCESS ? KERN_SUCCESS : KERN_FAILURE;
}

kern_return_t ksurface_fs_install_kext_at_path(const char *path)
{
    if(path == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    NSString *nsPath = [NSString stringWithCString:path encoding:NSUTF8StringEncoding];
    if(nsPath == nil)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    /* gather bundle and executable */
    NSBundle *bundle = [NSBundle bundleWithPath:nsPath];
    if(bundle == nil)
    {
        return KERN_DENIED;
    }
    
    NSString *executable = bundle.executablePath;
    if(executable == nil)
    {
        return KERN_DENIED;
    }
    
    /* validate apple signature */
    LCMachO *machO = LCMapMachO(executable.UTF8String, true);
    if(machO == NULL)
    {
        return KERN_DENIED;
    }
    
    bool isAppleSigned = LCCheckCodeSignature(machO);
    LCUnmapMachO(machO);
    if(!isAppleSigned)
    {
        return KERN_DENIED;
    }
    
    /* validate kext's nxt2 blob */
    ksurface_nxt2_t result = {};
    kern_return_t kr = trust_nxt2_read(executable.UTF8String, &result);
    if(kr != KERN_SUCCESS ||
       !result.isValid ||
       !result.isSigned ||
       !result.isCdHashValid)
    {
        if(result.entitlements != nil)
        {
            CFRelease(result.entitlements);
        }
        return KERN_DENIED;
    }
    
    /* check entitlements */
    bool hasEntitlement = CFDictionaryGetValue(result.entitlements, kNXT2EntitlementKsurfaceKEXTLoading) == kCFBooleanTrue;
    CFRelease(result.entitlements);
    if(!hasEntitlement)
    {
        return KERN_DENIED;
    }
    
    /* ready to go, we trust that thing */
    NSString *kextPath = [kextFSRoot stringByAppendingFormat:@"/%@.kext", bundle.bundleIdentifier];
    [[NSFileManager defaultManager] removeItemAtPath:kextPath error:nil];
    if(![[NSFileManager defaultManager] copyItemAtPath:nsPath toPath:kextPath error:nil])
    {
        return KERN_FAILURE;
    }
    
    return KERN_SUCCESS;
}

kern_return_t ksurface_fs_load_kext_with_bundleid(const char *bundleid,
                                                  uint64_t *key)
{
    if(bundleid == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    NSString *nsBundleIdentifier = [NSString stringWithCString:bundleid encoding:NSUTF8StringEncoding];
    if(nsBundleIdentifier == nil)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    NSString *kextPath = [kextFSRoot stringByAppendingFormat:@"/%@.kext", nsBundleIdentifier];
    if(kextPath == NULL)
    {
        return KERN_FAILURE;
    }
    
    return ksurface_fs_load_kext_with_path(kextPath.UTF8String, key);
}

kern_return_t ksurface_fs_load_kext_with_path(const char *path,
                                              uint64_t *key)
{
    NSString *kextPath = [NSString stringWithCString:path encoding:NSUTF8StringEncoding];
    if(kextPath == NULL)
    {
        return KERN_FAILURE;
    }
    
    NSBundle *kextBundle = [NSBundle bundleWithPath:kextPath];
    if(kextPath == nil)
    {
        return KERN_NOT_FOUND;
    }
    
    /* integrity check */
    NSString *executable = kextBundle.executablePath;
    if(executable == nil)
    {
        return KERN_DENIED;
    }
    
    /* validate apple signature */
    LCMachO *machO = LCMapMachO(executable.UTF8String, true);
    if(machO == NULL)
    {
        return KERN_DENIED;
    }
    
    bool isAppleSigned = LCCheckCodeSignature(machO);
    LCUnmapMachO(machO);
    if(!isAppleSigned)
    {
        return KERN_DENIED;
    }
    
    /* validate kext's nxt2 blob */
    ksurface_nxt2_t result = {};
    kern_return_t kr = trust_nxt2_read(executable.UTF8String, &result);
    if(kr != KERN_SUCCESS ||
       !result.isValid ||
       !result.isSigned ||
       !result.isCdHashValid)
    {
        if(result.entitlements != nil)
        {
            CFRelease(result.entitlements);
        }
        return KERN_DENIED;
    }
    
    /* check entitlements */
    bool hasEntitlement = CFDictionaryGetValue(result.entitlements, kNXT2EntitlementKsurfaceKEXTLoading) == kCFBooleanTrue;
    CFRelease(result.entitlements);
    if(!hasEntitlement)
    {
        return KERN_DENIED;
    }
    
    return kext_load_at_path(executable.UTF8String, key);
}

kern_return_t ksurface_fs_load_all_kext(void)
{
    NSArray<NSString*> *kexts = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kextFSRoot error:nil];
    if(kexts == nil)
    {
        return KERN_FAILURE;
    }
    
    klog_log("ksurface:fs:loadallkext", "kext load chain:");
    for(NSString *kext in kexts)
    {
        klog_log("ksurface:fs:loadallkext", "%@", kext);
    }
    
    klog_log("ksurface:fs:loadallkext", "loading all installed kext's");
    for(NSString *kext in kexts)
    {
        NSString *fullKextPath = [NSString stringWithFormat:@"%@/%@", kextFSRoot, kext];
        if(fullKextPath == nil)
        {
            environment_panic("failed to allocate full path for %@", kext);
        }
        
        uint64_t key;
        kern_return_t kr = ksurface_fs_load_kext_with_path(fullKextPath.UTF8String, &key);
        if(kr != KERN_SUCCESS)
        {
            environment_panic("failed to load kext %@", kr);
        }
    }
    klog_log("ksurface:fs:loadallkext", "all kext's shall be loaded");
    
    return KERN_SUCCESS;
}
