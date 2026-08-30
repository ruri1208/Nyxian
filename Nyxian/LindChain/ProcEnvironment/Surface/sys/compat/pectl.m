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

#include <LindChain/ProcEnvironment/Surface/sys/compat/pectl.h>
#import <LindChain/ProcEnvironment/PEProcessManager.h>
#import <LindChain/ProcEnvironment/PEBootstrapRegistry.h>
#import <LindChain/ProcEnvironment/PELaunchServiceManager.h>
#import <LindChain/ProcEnvironment/PEUserspaceManager.h>
#import <Foundation/Foundation.h>
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/WindowServer/Session/NXWindowSessionApplication.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCUtils.h>
#include <LindChain/ProcEnvironment/Utils/vnode.h>
#include <LindChain/ProcEnvironment/Utils/klog.h>
#include <LindChain/ProcEnvironment/Surface/kext.h>
#import <ksurface_config.h>
#import <ksurface_abi.h>
#include <dlfcn.h>

DEFINE_SYSCALL_HANDLER(pectl_launchservice)
{
    PECTLLaunchService action = (PECTLLaunchService)args[1];
    switch(action)
    {
        case kPECTLLaunchServiceGetEndpoint:
        {
            userspace_pointer_t userspace_str = (userspace_pointer_t)args[2];
            char *service_name = mach_syscall_copy_str_in(sys_task_, userspace_str, MAXHOSTNAMELEN);
            if(service_name == NULL)
            {
                sys_return_failure_with_errno(ENOMEM);
            }
            
            NSString *service_nsname = [NSString stringWithCString:service_name encoding:NSUTF8StringEncoding];
            free(service_name);
            if(service_nsname == nil)
            {
                sys_return_failure_with_errno(ENOMEM);
            }
            
            if(!entitlement_got_entitlement(proc_getentitlements(sys_proc_snapshot_), kPEEntitlementFlagLaunchServicesGetEndpoint))
            {
                kvo_rdlock(sys_proc_);
                CFArrayRef allowList = CFDictionaryGetValue(sys_proc_->nyx.identity->entitlements, kNXT2EntitlementLaunchServicesGetEndpointAllowList);
                if(allowList != nil)
                {
                    CFIndex allowListCount = CFArrayGetCount(allowList);
                    for(CFIndex index = 0; index < allowListCount; index++)
                    {
                        NSString *allowedServiceIdentifier = (__bridge NSString*)CFArrayGetValueAtIndex(allowList, index);
                        if([service_nsname isEqualToString:allowedServiceIdentifier])
                        {
                            kvo_unlock(sys_proc_);
                            goto allow_get_fastpath;
                        }
                    }
                }
                kvo_unlock(sys_proc_);
                sys_return_failure_with_errno(EPERM);
            }
            
        allow_get_fastpath:
            {
                mach_port_t port = [[PEBootstrapRegistry shared] getMachPortNameWithServiceIdentifier:service_nsname];
                if(port == MACH_PORT_NULL)
                {
                    sys_return_failure_with_errno(EACCES);
                }
                
                kern_return_t kr = mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_SEND, 1);
                if(kr != KERN_SUCCESS)
                {
                    sys_return_failure_with_errno(EACCES);
                }
                
                kr = mach_syscall_payload_create(NULL, sizeof(mach_port_t), (vm_address_t*)out_ports);
                if(kr != KERN_SUCCESS)
                {
                    mach_port_deallocate(mach_task_self(), port);
                    sys_return_failure_with_errno(ENOMEM);
                }
                
                (*out_ports)[0] = port;
                *out_ports_cnt = 1;
                
                sys_return;
            }
        }
        case kPECTLLaunchServiceSetEndpoint:
        {
            sys_need_in_ports(1, MACH_MSG_TYPE_MOVE_SEND);
            
            userspace_pointer_t userspace_str = (userspace_pointer_t)args[2];
            char *service_name = mach_syscall_copy_str_in(sys_task_, userspace_str, MAXHOSTNAMELEN);
            if(service_name == NULL)
            {
                sys_return_failure_with_errno(ENOMEM);
            }
            
            NSString *service_nsname = [NSString stringWithCString:service_name encoding:NSUTF8StringEncoding];
            free(service_name);
            if(service_nsname == nil)
            {
                sys_return_failure_with_errno(ENOMEM);
            }
            
            if(!entitlement_got_entitlement(proc_getentitlements(sys_proc_snapshot_), kPEEntitlementFlagLaunchServicesSetEndpoint))
            {
                kvo_rdlock(sys_proc_);
                CFArrayRef allowList = CFDictionaryGetValue(sys_proc_->nyx.identity->entitlements, kNXT2EntitlementLaunchServicesSetEndpointAllowList);
                if(allowList != nil)
                {
                    CFIndex allowListCount = CFArrayGetCount(allowList);
                    for(CFIndex index = 0; index < allowListCount; index++)
                    {
                        NSString *allowedServiceIdentifier = (__bridge NSString*)CFArrayGetValueAtIndex(allowList, index);
                        if([service_nsname isEqualToString:allowedServiceIdentifier])
                        {
                            kvo_unlock(sys_proc_);
                            goto allow_set_fastpath;
                        }
                    }
                }
                kvo_unlock(sys_proc_);
                sys_return_failure_with_errno(EPERM);
            }
            
        allow_set_fastpath:
            {
                /*
                 * getting existing launch service, because we
                 * have ti make sure that its not a attacker
                 * attempting to overwrite a launchservice
                 * endpoint to control it, as Nyxian it self
                 * requires such launch service to be able to
                 * read data from the other container, which
                 * is the reason for this extra layer of trust.
                 */
                PELaunchService *service = [[PELaunchServiceManager shared] serviceForIdentifier:service_nsname];
                if(service != nil)
                {
                    PEProcess *process = service.process;
                    
                    /*
                     * in-case there is no process it is
                     * reserved for the service and cannot
                     * be overriden by a attacker.
                     */
                    if(process == nil)
                    {
                        /* slot is reserved */
                        sys_return_failure_with_errno(EACCES);
                    }
                    
                    /*
                     * making sure that the right process
                     * registers the endpoint for the
                     * service domain.
                     */
                    if(process.pid != proc_getpid(sys_proc_snapshot_))
                    {
                        /* slot is reserved */
                        sys_return_failure_with_errno(EACCES);
                    }
                }
                
                [[PEBootstrapRegistry shared] setMachPortName:sys_in_ports[0] forServiceIdentifier:service_nsname];
                sys_in_ports[0] = MACH_PORT_NULL;   /* prevent mach port reference leak */
                
                sys_return;
            }
        }
        default:
            sys_return_failure_with_errno(ENOSYS);
    }
}

/* sub categories */
DEFINE_SYSCALL_HANDLER(pectl_codesigning)
{
    PECTLCodeSigning action = (PECTLCodeSigning)args[1];
    switch(action)
    {
        case kPECTLCodeSigningGetPublicKey:
        {
            userspace_pointer_t key_user_ptr = (userspace_pointer_t)args[2];
            userspace_pointer_t key_len_ptr = (userspace_pointer_t)args[3];
            
            size_t key_len = 0;
            if(!mach_syscall_copy_in(sys_task_, sizeof(size_t), &key_len, key_len_ptr))
            {
                sys_return_failure_with_errno(EFAULT);
            }
            
            if(key_len < ksurface->pub_key_len)
            {
                sys_return_failure_with_errno(E2BIG);
            }
            
            if(!mach_syscall_copy_out(sys_task_, ksurface->pub_key_len, ksurface->pub_key, key_user_ptr) ||
               !mach_syscall_copy_out(sys_task_, sizeof(size_t), &key_len, key_len_ptr))
            {
                sys_return_failure_with_errno(EFAULT);
            }
            
            sys_return;
        }
        case kPECTLCodeSigningGetPrivateKey:
            /* too much of a security concern */
            sys_return_failure_with_errno(ENOSYS);
        case kPECTLCodeSigningSignPath:
            /* deprecated with SYS_sign */
            sys_return_failure_with_errno(ENOSYS);
        case kPECTLCodeSigningGetCDHash:
        {
            kvo_rdlock(sys_proc_);
            if(sys_proc_->nyx.identity->trustLevel != kPETrustLevelSignature)   /* signature type needs cdhash verification */
            {
                kvo_unlock(sys_proc_);
                sys_return_failure_with_errno(ENOENT);
            }
            
            userspace_pointer_t ch_user_ptr = (userspace_pointer_t)args[2];
            if(!mach_syscall_copy_out(sys_task_, sizeof(sys_proc_->nyx.identity->cdhash), sys_proc_->nyx.identity->cdhash, ch_user_ptr))
            {
                kvo_unlock(sys_proc_);
                sys_return_failure_with_errno(EFAULT);
            }
            
            kvo_unlock(sys_proc_);
            sys_return;
        }
        case kPECTLCodeSigningAllEntitlements:
            return kPEEntitlementFlagAll;
        case kPECTLCodeSigningGetEntitlements:
        {
            return proc_getentitlements(sys_proc_snapshot_);
        }
        case kPECTLCodeSigningSetEntitlements:
        {
            kvo_wrlock(sys_proc_);
            
            /* MARK: THIS IS USER SUPPLIED */
            PEEntitlementFlags userPassed = (PEEntitlementFlags)args[2];
            
            /* getting the added mask out of entitlements */
            PEEntitlementFlags added = (~proc_getentitlements(sys_proc_)) & userPassed;
            
            /* deny adding entitlements not present in max entitlements */
            if(!entitlement_got_entitlement(proc_getmaxentitlements(sys_proc_), added))
            {
                kvo_unlock(sys_proc_);
                sys_return_failure_with_errno(EPERM);
            }
            
            proc_setentitlements(sys_proc_, userPassed);
            
            kvo_unlock(sys_proc_);
            sys_return;
        }
        case kPECTLCodeSigningDropAllEntitlements:
        {
            kvo_wrlock(sys_proc_);
            proc_setmaxentitlements(sys_proc_, kPEEntitlementFlagNone);
            proc_setentitlements(sys_proc_, kPEEntitlementFlagNone);
            kvo_unlock(sys_proc_);
            sys_return;
        }
        case kPECTLCodeSigningLoadKernelExtension:
        {
            if(!entitlement_got_entitlement(proc_getentitlements(sys_proc_snapshot_), kPEEntitlementFlagLoadKEXT))
            {
                sys_return_failure_with_errno(EPERM);
            }
            
            userspace_pointer_t userspace_str = (userspace_pointer_t)args[2];
            char *extensionPath = mach_syscall_copy_str_in(sys_task_, userspace_str, MAXHOSTNAMELEN);
            if(extensionPath == NULL)
            {
                sys_return_failure_with_errno(ENOMEM);
            }
            
            /* spinning the extension up~ */
            uint64_t key;
            kern_return_t kr = ksurface_kext_load_at_path(extensionPath, &key);
            switch(kr)
            {
                case KERN_SUCCESS: return (int64_t)key;
                case KERN_NAME_EXISTS: sys_return_failure_with_errno(EEXIST);
                case KERN_NO_SPACE: sys_return_failure_with_errno(ENOMEM);
                default: sys_return_failure_with_errno(ENOEXEC);
            }
        }
        case kPECTLCodeSigningUnloadKernelExtension:
        {
            if(!entitlement_got_entitlement(proc_getentitlements(sys_proc_snapshot_), kPEEntitlementFlagLoadKEXT))
            {
                sys_return_failure_with_errno(EPERM);
            }
            
            uint64_t key = (uint64_t)args[2];
            kern_return_t kr = ksurface_kext_unload_with_key(key);
            switch(kr)
            {
                case KERN_SUCCESS: return (int64_t)key;
                case KERN_NAME_EXISTS: sys_return_failure_with_errno(EEXIST);
                case KERN_NO_SPACE: sys_return_failure_with_errno(ENOMEM);
                default: sys_return_failure_with_errno(EACCES);
            }
        }
        default:
            sys_return_failure_with_errno(ENOSYS);
    }
}

DEFINE_SYSCALL_HANDLER(pectl_userinterface)
{
    PECTLUserInterface action = (PECTLUserInterface)args[1];
    switch(action)
    {
        case kPECTLUserInterfaceInit:
        {
            recv_buffer_t *recv = *recv_buffer;
            *recv_buffer = NULL;    /* claiming ownership */
            pid_t pid = proc_getpid(sys_proc_snapshot_);
            dispatch_async(dispatch_get_main_queue(), ^{
                NXWindowServer *sharedWindowServer = [NXWindowServer shared];
                if(sharedWindowServer == nil)
                {
                    /* window server is not running yet */
                    send_reply(&(recv->header), -1, NULL, 0, true, EAGAIN);
                    return;
                }
                
                PEProcess *process = [[PEProcessManager shared] processForProcessIdentifier:pid];
                if(process == nil || process.bundleIdentifier == nil)
                {
                    /* process must exist in Process Manager */
                    send_reply(&(recv->header), -1, NULL, 0, true, EACCES);
                    return;
                }
                
                id_t wid = [sharedWindowServer windowIdentifierForBundleIdentifier:process.bundleIdentifier];
                if(wid < 0)
                {
                    /* bundle is already presented as a window */
                    send_reply(&(recv->header), -1, NULL, 0, true, EACCES);
                    return;
                }
                
                NXWindowSessionApplication *session = [[NXWindowSessionApplication alloc] initWithProcess:process];
                [sharedWindowServer openWindowWithSession:session withCompletion:^(BOOL finished){
                    send_reply(&(recv->header), finished ? 0 : -1, NULL, 0, true, 0);
                }];
            });
            sys_return;
        }
        case kPECTLUserInterfaceOpenBundleIdentifier:
        {
            kvo_rdlock(sys_proc_);
            if(CFDictionaryGetValue(sys_proc_->nyx.identity->entitlements, kNXT2EntitlementManagementProcEnvironment) != kCFBooleanTrue)
            {
                kvo_unlock(sys_proc_);
                sys_return_failure_with_errno(EPERM);
            }
            kvo_unlock(sys_proc_);
            
            userspace_pointer_t bundleid_str = (userspace_pointer_t)args[2];
            char *bundleid = mach_syscall_copy_str_in(sys_task_, bundleid_str, MAXHOSTNAMELEN);
            if(bundleid == NULL)
            {
                sys_return_failure_with_errno(ENOMEM);
            }
            
            NSString *bundleIdentifier = [NSString stringWithCString:bundleid encoding:NSUTF8StringEncoding];
            free(bundleid);
            if(bundleIdentifier == NULL)
            {
                sys_return_failure_with_errno(ENOMEM);
            }
            
            recv_buffer_t *recv = *recv_buffer;
            *recv_buffer = NULL;    /* claiming ownership */
            dispatch_async(dispatch_get_main_queue(), ^{
                pid_t pid = [[PEProcessManager shared] spawnProcessWithBundleIdentifier:bundleIdentifier withItems:@{} withKernelSurfaceProcess:kernel_proc_ doRestartIfRunning:NO];
                if(pid < 0)
                {
                    send_reply(&(recv->header), -1, NULL, 0, true, EAGAIN);
                }
                
                send_reply(&(recv->header), 0, NULL, 0, true, 0);
            });
            sys_return;
        }
        default:
            sys_return_failure_with_errno(ENOSYS);
    }
}

DEFINE_SYSCALL_HANDLER(pectl_userspace)
{
    PECTLUserspace action = (PECTLUserspace)args[1];
    switch(action)
    {
        case kPECTLUserspaceReboot:
            if(!entitlement_got_entitlement(proc_getmaxentitlements(sys_proc_snapshot_), kPEEntitlementFlagPlatform))
            {
                sys_return_failure_with_errno(EPERM);
            }
            [[PEUserspaceManager shared] rebootUserspaceWithType:kPEUserspaceRebootTypeDefault];
            sys_return;
        case kPECTLUserspaceGetMode:
            return [[PEUserspaceManager shared] mode];
        default:
            sys_return_failure_with_errno(ENOSYS);
    }
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(pectl_misceleanous)
{
    PECTLMisceleanous action = (PECTLMisceleanous)args[1];
    switch(action)
    {
        case kPECTLMisceleanousGetBuildType:
            #if DEBUG
            return kPEBuildTypeDebug;
            #else
            return kPEBuildTypeRelease;
            #endif /* DEBUG */
        default:
            sys_return_failure_with_errno(ENOSYS);
    }
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(pectl)
{
    @autoreleasepool {
        PECTLCategory category = (PECTLCategory)args[0];
        switch(category)
        {
            case kPECTLCategoryLaunchService:
                return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(pectl_launchservice);
            case kPECTLCategoryCodeSigning:
                return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(pectl_codesigning);
            case kPECTLCategoryUserInterface:
                return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(pectl_userinterface);
            case kPECTLCategoryUserspace:
                return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(pectl_userspace);
            case kPECTLCategoryMisceleanous:
                return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(pectl_misceleanous);
            default:
                sys_return_failure_with_errno(ENOSYS);
        }
    }
}
