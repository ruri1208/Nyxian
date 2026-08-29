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
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

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
