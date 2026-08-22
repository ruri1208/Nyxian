/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab
 Copyright (C) 2026 ruri1208

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

#import <LindChain/ProcEnvironment/PEUserspaceManager.h>
#import <LindChain/ProcEnvironment/PEExtension.h>
#import <LindChain/ProcEnvironment/PEProcessManager.h>
#import <LindChain/ProcEnvironment/PELaunchServiceManager.h>
#import <LindChain/ProcEnvironment/PEBootstrapRegistry.h>
#import <LindChain/Services/containerd/PEContainer.h>
#import <LindChain/ProcEnvironment/Utils/klog.h>
#import <LindChain/IDEFoundation/NXBootstrap.h>
#import <Nyxian-Swift.h>

@implementation PEUserspaceManager {
    os_unfair_lock _lock;
    atomic_flag _bootOnceFlag;
    atomic_bool _bootSuccessful;
    atomic_bool _launchServiceManagerStable;
}

@dynamic isBooted;
@dynamic isLaunchServiceManagerStable;

+ (void)load
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        @autoreleasepool {
            [[PEUserspaceManager shared] boot];
        }
    });
}

+ (instancetype)shared
{
    static PEUserspaceManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PEUserspaceManager alloc] init];
    });
    return shared;
}

- (BOOL)isBooted
{
    return atomic_load_explicit(&_bootSuccessful, memory_order_acquire);
}

- (BOOL)isLaunchServiceManagerStable
{
    return atomic_load_explicit(&_launchServiceManagerStable, memory_order_acquire);
}

- (instancetype)init
{
    static atomic_flag once = ATOMIC_FLAG_INIT;
    if(atomic_flag_test_and_set(&once))
    {
        environment_panic("This class may only be initilized once");
    }
    
    self = [super init];
    if(self)
    {
        _lock = OS_UNFAIR_LOCK_INIT;
        atomic_flag_clear(&_bootOnceFlag);
        atomic_store_explicit(&_bootSuccessful, false, memory_order_release);
        atomic_store_explicit(&_launchServiceManagerStable, false, memory_order_release);
        _mode = kPEUserspaceModeDefault;
    }
    return self;
}

- (void)boot
{
    const char *domain = "PEUserspaceManager:boot";
    
    /* boot shall only happen once */
    if(atomic_flag_test_and_set(&_bootOnceFlag))
    {
        environment_panic("boot called twice");
    }
    
    os_unfair_lock_lock(&_lock);
    
    /* extension must be available */
    if(PEGetLiveProcessBundle() == NULL ||
       !PEExtensionHasGetTaskAllowed())
    {
        klog_log(domain, "Cannot spin up anything, extension is malformed");
        os_unfair_lock_unlock(&_lock);
        return;
    }
    
    /* now we can spin up that baby (micro kernel) =3 */
    ksurface_kinit();
    
    /* now the actual userspace */
    Class UserspaceBootChain[] = {
        [PEProcessManager class],
        [PEBootstrapRegistry class],
        [PELaunchServiceManager class],
    };
    
    for(size_t index = 0; index < sizeof(UserspaceBootChain) / sizeof(Class); index++)
    {
        Class class = UserspaceBootChain[index];
        if([class shared] != nil)
        {
            klog_log(domain, "%@ [ok]", class);
        }
        else
        {
            environment_panic("%@ [failed]", class);
        }
    }
    klog_log(domain, "%@ [ok]", [self class]);
    
    /* spinning up the launch services */
    [[PELaunchServiceManager shared] reloadAllEntries];
    
    /* mark current boot as successful */
    atomic_store_explicit(&_launchServiceManagerStable, true, memory_order_release);
    atomic_store_explicit(&_bootSuccessful, true, memory_order_release);
    
    os_unfair_lock_unlock(&_lock);
}

- (BOOL)rebootUserspaceWithType_nolock:(PEUserspaceRebootType)type
{
    if(!atomic_load_explicit(&_bootSuccessful, memory_order_acquire))
    {
        return NO;
    }
    
    const char *domain = "PEUserspaceManager:reboot";
    
    /* TODO: prevent spawns from happening, deny any new spawns too */
    klog_log(domain, "aquiring proctil lock");
    if(proctil(kProctilActionLock) != KERN_SUCCESS)
    {
        klog_log(domain, "userspace reboot failed, lock couldn't be claimed");
        return NO;
    }
    
    klog_log(domain, "invalidating all launch service entries in registry");
    [[PELaunchServiceManager shared] invalidateAllEntries];    /* causes reignition to fail in launch services, so killing will not automatically restart them */
    
    klog_log(domain, "killing all running processes");
    [[PEProcessManager shared] killAllRunningProcesses];
    
    klog_log(domain, "releasing proctil lock");
    proctil(kProctilActionUnlock);
    
    klog_log(domain, "reloading daemons");
    switch(type)
    {
        case kPEUserspaceRebootTypeDefault:
            _mode = kPEUserspaceModeDefault;
            break;
        case kPEUserspaceRebootTypeMinimal:
            _mode = kPEUserspaceModeMinimal;
            break;
        default:
            _mode = kPEUserspaceModeEmpty;
            break;
    }
    [self reloadDaemons_nolock];
    
    klog_log(domain, "userspace rebooted successfully");
    return YES;
}

- (BOOL)rebootUserspaceWithType:(PEUserspaceRebootType)type
{
    os_unfair_lock_lock(&_lock);
    BOOL success = [self rebootUserspaceWithType_nolock:type];
    os_unfair_lock_unlock(&_lock);
    return success;
}

- (BOOL)rebootUserspace
{
    os_unfair_lock_lock(&_lock);
    BOOL success = [self rebootUserspaceWithType_nolock:kPEUserspaceRebootTypeDefault];
    os_unfair_lock_unlock(&_lock);
    return success;
}

- (BOOL)restore
{
    if(!atomic_load_explicit(&_bootSuccessful, memory_order_acquire))
    {
        return NO;
    }
    
    const char *domain = "PEUserspaceManager:restore";
    
    os_unfair_lock_lock(&_lock);
    BOOL inRetry = NO;
    goto first;
    
recoverable_fail:
    if(inRetry)
    {
        goto retry_fail;
    }
    /* here we can still return back without consequences */
    [self rebootUserspaceWithType_nolock:kPEUserspaceRebootTypeDefault];
    os_unfair_lock_unlock(&_lock);
    return NO;
    
retry_fail: /* a retry shall not happen, happens tho if something goes wrong */
    inRetry = YES;
    klog_log(domain, "failed to restore, reattempt restore");
    
first:
    {
        /* needs to be in minimal userspace boot mode to safely begin restoring the container through containerd */
        klog_log(domain, "rebooting userspace into empty mode");
        [self rebootUserspaceWithType_nolock:kPEUserspaceRebootTypeEmpty];
        
        /* getting contents of each */
        NSURL *root = [[NXBootstrap shared] rootfsURL];
        NSArray<NSString*> *rootDirectories = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[root path] error:nil];
        klog_log(domain, "directories to tear down \ninside of %@: %@", [[NXBootstrap shared] rootfsURL], rootDirectories);
        
        /* deleting everything */
        klog_log(domain, "restoring file system");
        for(NSString *pathComponent in rootDirectories)
        {
            NSURL *itemURL = [root URLByAppendingPathComponent:pathComponent];
            if(![[NSFileManager defaultManager] removeItemAtURL:itemURL error:nil])
            {
                klog_log(domain, "tearing down %@ failed", itemURL);
                goto retry_fail;
            }
        }
        
        /* now we have to restore the default hostname */
        klog_log(domain, "restoring hostname");
        ksurface_sethostname(@"localhost");
        
        klog_log(domain, "restoring code signature key pair");
        uint8_t *new_priv = NULL, *new_pub = NULL;
        size_t new_priv_len = 0, new_pub_len = 0;
        
        if(!get_kernel_ec_key(&new_priv, &new_priv_len, &new_pub, &new_pub_len))
        {
            goto retry_fail;
        }
        
        int ret = store_kernel_key(new_priv, new_priv_len, new_pub, new_pub_len);
        free(new_priv);
        free(new_pub);
        if(ret != 0)
        {
            goto retry_fail;
        }
        
        /* regather them */
        ksurface_kinit_get_keys();
        
        /* clearing app list TODO: make it a actual "client portal" instead */
        klog_log(domain, "restored successfully");
        [[ApplicationManagementViewController shared] removeAllApplications];
        
        /* we're done, now rebooting back into default mode */
        klog_log(domain, "bringing userspace back into normal mode");
        [self rebootUserspaceWithType_nolock:kPEUserspaceRebootTypeDefault];
        
        /* TODO: make the entire reboot timing perfect */
    }
    os_unfair_lock_unlock(&_lock);
    return YES;
}

- (BOOL)reloadDaemons_nolock
{
    if(!atomic_load_explicit(&_bootSuccessful, memory_order_acquire))
    {
        return NO;
    }
    
    atomic_store_explicit(&_launchServiceManagerStable, false, memory_order_release);
    [[PELaunchServiceManager shared] invalidateAllEntries];
    if(_mode == kPEUserspaceModeDefault)
    {
        [[PELaunchServiceManager shared] reloadAllEntries];
    }
    else if(_mode == kPEUserspaceModeMinimal)
    {
        [[PELaunchServiceManager shared] loadEntryWithFileName:@"org.emexlabs.containerd.plist"];
    }
    else
    {
        return NO;
    }
    atomic_store_explicit(&_launchServiceManagerStable, true, memory_order_release);
    
    return YES;
}

- (BOOL)reloadDaemons
{
    os_unfair_lock_lock(&_lock);
    BOOL success = [self reloadDaemons_nolock];
    os_unfair_lock_unlock(&_lock);
    return success;
}

- (BOOL)clearApplicationCaches
{
    if(!atomic_load_explicit(&_bootSuccessful, memory_order_acquire))
    {
        return NO;
    }
    
    const char *domain = "PEUserspaceManager:clearApplicationCaches";
    
    os_unfair_lock_lock(&_lock);
    klog_log(domain, "rebooting to default (without apps)");
    [self rebootUserspaceWithType_nolock:kPEUserspaceRebootTypeMinimal];
    
    /* waiting till containerd is back */
    sleep(1);   /* FIXME: waiting shall not be necessary */
    
    /* getting containers */
    NSURL *containerRoot = [[PEContainer shared] getContainerRoot];
    if(containerRoot == NULL)
    {
        klog_log(domain, "failed to get stable connection with containerd");
        os_unfair_lock_unlock(&_lock);
        return NO;
    }
    
    NSError *error;
    NSArray<NSString*> *containers = [[PEContainer shared] contentsOfDirectoryAtPath:[[containerRoot URLByAppendingPathComponent:@"/Documents/Data/Application"] path] error:&error];
    if(containers == NULL)
    {
        klog_log(domain, "failed to get all applications containers: \"%@\"", error);
        os_unfair_lock_unlock(&_lock);
        return NO;
    }
    
    /* now we gotta clear all caches */
    for(NSString *containerPath in containers)
    {
        NSString *cachesPath = [[containerRoot path] stringByAppendingPathComponent:[@"/Documents/Data/Application" stringByAppendingPathComponent:[containerPath stringByAppendingPathComponent:@"/Library/Caches"]]];
        [[PEContainer shared] removeItemAtURL:[NSURL fileURLWithPath:cachesPath] error:nil];
    }
    
    klog_log(domain, "rebooting back to normal (without apps)");
    [self rebootUserspaceWithType_nolock:kPEUserspaceRebootTypeDefault];
    
    /* userspace in usable state anyways */
    os_unfair_lock_unlock(&_lock);
    return YES;
}

@end
