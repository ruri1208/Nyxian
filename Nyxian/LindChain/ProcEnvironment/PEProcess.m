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

#import <LindChain/ProcEnvironment/PEProcess.h>
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/ProcEnvironment/Utils/klog.h>
#import <LindChain/Services/applicationmgmtd/LDEApplicationWorkspace.h>
#import <LindChain/Services/containerd/PEContainer.h>
#import <LindChain/ProcEnvironment/PEExtension.h>
#import <LindChain/ProcEnvironment/PEUserspaceManager.h>
#import <LindChain/ProcEnvironment/PEMachPort.h>
#import <LindChain/ProcEnvironment/Server/Server.h>
#import <LindChain/ProcEnvironment/Surface/proc/proctil.h>
#import <MobileDevelopmentKit/MDKThreadPool.h>
#import <LindChain/IDEFoundation/NXBootstrap.h>

@implementation PEProcess {
    NSHashTable<id<PEProcessObserver>> *_observers;
    os_unfair_lock _lock;
}

- (instancetype)initWithItems:(NSDictionary*)items
     withKernelSurfaceProcess:(ksurface_proc_t*)proc
{
    if(proctil(kProctilActionCount) != KERN_SUCCESS)
    {
        return nil;
    }
    
    self = [super init];
    if(self == nil)
    {
        proctil(kProctilActionUncount);
        return nil;
    }
    
    _observers = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality capacity:0];
    _lock = OS_UNFAIR_LOCK_INIT;
    
    if(proctil(kProctilActionLock) != KERN_SUCCESS)
    {
        return nil;
    }
    
    self.executablePath = items[@"PEExecutablePath"];
    if(![[PEContainer shared] isReadableFileAtPath:self.executablePath])
    {
        proctil(kProctilActionUnlock);
        return nil;
    }
    
    /* assigning potential bundle information */
    LDEApplicationObject *applicationObject = nil;
    if(PEUserspaceManager.shared.isLaunchServiceManagerStable)
    {
        applicationObject = [[LDEApplicationWorkspace shared] applicationObjectForExecutablePath:self.executablePath];
        if(applicationObject && applicationObject.bundlePath && applicationObject.containerPath)
        {
            bool wasLocallySigned;
            PEEntitlement entitlement = entitlement_get_path([applicationObject.executablePath UTF8String], &wasLocallySigned);
            if(!wasLocallySigned)
            {
                goto continue_assigning;
            }
            
            /* this will override the existing permissions */
            NSMutableArray<NSData*> *filePermissions = [[NSMutableArray alloc] init];
            
            if(entitlement_got_entitlement(entitlement, kPEEntitlementFileRootRW))
            {
                [filePermissions addObject:[NXBootstrap issueSandboxFileExtensionForURL:[[NXBootstrap shared] rootfsURL] readWrite:YES]];
                goto overwrite_file_permissions;
            }
            
            /*if(entitlement_got_entitlement(entitlement, kPEEntitlementFileBundleRW))
             {*/
            [filePermissions addObject:[NXBootstrap issueSandboxFileExtensionForURL:[NSURL fileURLWithPath:applicationObject.bundlePath] readWrite:YES]];
            /*}
             else
             {
             [filePermissions addObject:[NXBootstrap issueSandboxFileExtension:[NSURL fileURLWithPath:applicationObject.executablePath] readOnly:NO]];
             [filePermissions addObject:[NXBootstrap issueSandboxFileExtension:[NSURL fileURLWithPath:applicationObject.bundlePath] readOnly:YES]];
             }*/
            
            if(entitlement_got_entitlement(entitlement, kPEEntitlementFileContainerRW))
            {
                [filePermissions addObject:[NXBootstrap issueSandboxFileExtensionForURL:[NSURL fileURLWithPath:applicationObject.containerPath] readWrite:YES]];
            }
            else
            {
                [filePermissions addObjectsFromArray:@[
                    [NXBootstrap issueSandboxFileExtensionForURL:[NSURL fileURLWithPath:applicationObject.containerPath] readWrite:NO],
                    [NXBootstrap issueSandboxFileExtensionForURL:[[NSURL fileURLWithPath:applicationObject.containerPath] URLByAppendingPathComponent:@"Documents"] readWrite:YES],
                    [NXBootstrap issueSandboxFileExtensionForURL:[[NSURL fileURLWithPath:applicationObject.containerPath] URLByAppendingPathComponent:@"Library"] readWrite:YES],
                    [NXBootstrap issueSandboxFileExtensionForURL:[[NSURL fileURLWithPath:applicationObject.containerPath] URLByAppendingPathComponent:@"Tmp"] readWrite:YES],
                ]];
            }
            
        overwrite_file_permissions:
            {
                NSMutableDictionary *mutableItems = [items mutableCopy];
                [mutableItems setObject:filePermissions forKey:@"PEFilePermissions"];
                items = mutableItems;
            }
        }
    }
continue_assigning:
    self.bundleIdentifier = applicationObject ? applicationObject.bundleIdentifier : nil;
    self.displayName = applicationObject ? applicationObject.localizedName : [self.executablePath lastPathComponent];
    
    /* spawning process */
    self.process = PESpawnFBProcess(items);
    if(self.process == nil)
    {
        proctil(kProctilActionUnlock);
        return nil;
    }
    _pid = self.process.pid;
    
    [self.process addObserver:self];
    if(!self.process.running)
    {
        /*
         * prevents a race condition, when we add a observer
         * and it already died then we shall handle the exit.
         */
        FBProcessManager *manager = [PrivClass(FBProcessManager) sharedInstance];
        [manager _removeProcess:self.process];
        proctil(kProctilActionUnlock);
        return nil;
    }
    
    ksurface_proc_t *child = NULL;
    kern_return_t kr = proc_spawn(proc ?: kernel_proc_, &child, self.pid, [self.executablePath UTF8String]);
    if(kr != KERN_SUCCESS)
    {
        [self terminate];
        proctil(kProctilActionUnlock);
        return nil;
    }
    else
    {
        self.proc = child;
    }
    
    proctil(kProctilActionUnlock);
    return self;
}

- (void)sendSignal:(int)signal
{
    /*
     * those signals are not supported at all
     * (for now atleast).
     */
    if(signal == SIGTTIN ||
       signal == SIGTTOU)
    {
        return;
    }
    
    /*
     * for some reason apple doesnt support SIGTSTP on iOS
     * (maybe we just use it wrong lol)
     */
    if(signal == SIGTSTP)
    {
        signal = SIGSTOP;
    }
    
    /*
     * TODO: this is okay, but we need to use a boolean flag
     *
     * if(signal == SIGSTOP)
     * {
     *     _isSuspended = YES;
     * }
     * else if(signal == SIGCONT)
     * {
     *     _isSuspended = NO;
     * }
     */
    
    [self.process.nsExtension _kill:signal];
    
    if(signal == SIGSTOP)
    {
        kvo_wrlock(_proc);
        _proc->bsd.kp_proc.p_stat = SSTOP;
        
        goto report_signal;
    }
    else if(signal == SIGCONT)
    {
        kvo_wrlock(_proc);
        _proc->bsd.kp_proc.p_stat = SRUN;
        
    report_signal:
        kvo_unlock(_proc);
        proc_state_change(_proc, W_STOPCODE(signal));
    }
}

- (void)terminate
{
    [self sendSignal:SIGTERM];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(self) strongSelf = weakSelf;
        if(strongSelf != NULL)
        {
            /* process still alive? */
            [strongSelf sendSignal:SIGKILL];
        }
    });
}

- (void)suspend
{
    [self sendSignal:SIGSTOP];
}

- (void)resume
{
    [self sendSignal:SIGCONT];
}
        
- (void)processDidExit:(FBProcess *)arg1
{
    if(_proc != NULL)
    {
        /* yep writing official wait4 code~~ */
        proc_state_change(_proc, arg1.exitContext.underlyingContext.legacyCode);
        kern_return_t error = proc_zombify(_proc);
        if(error != KERN_SUCCESS)
        {
            klog_log("PEProcess:processDidExit", "failed to remove pid %d", _pid);
        }
    }
    
    /* notify observers */
    [self enumerateObservers:^(id<PEProcessObserver> observer) {
        [observer process:self didExitWithWait4Code:arg1.exitContext.underlyingContext.legacyCode];
    }];
}

- (void)processWillExit:(FBProcess *)arg1
{
    /* stub for when ever */
}

- (void)process:(FBProcess *)arg1 stateDidChangeFromState:(FBProcessState *)arg2 toState:(FBProcessState *)arg3
{
    /* stub for when ever */
}

- (void)enumerateObservers:(void (^)(id<PEProcessObserver> observer))block
{
    os_unfair_lock_lock(&_lock);
    NSArray<id<PEProcessObserver>> *snapshot = _observers.allObjects;
    os_unfair_lock_unlock(&_lock);
    for(id<PEProcessObserver> observer in snapshot)
    {
        block(observer);
    }
}

- (void)addObserver:(id<PEProcessObserver>)observer
{
    NSParameterAssert(observer);
    os_unfair_lock_lock(&_lock);
    [_observers addObject:observer];
    os_unfair_lock_unlock(&_lock);
}

- (void)removeObserver:(id<PEProcessObserver>)observer
{
    os_unfair_lock_lock(&_lock);
    [_observers removeObject:observer];
    os_unfair_lock_unlock(&_lock);
}

- (void)dealloc
{
    if(_proc != NULL)
    {
        kvo_release(_proc);
    }
    proctil(kProctilActionUncount);
#if DEBUG
    NSLog(@"deallocated %@", self);
#endif /* DEBUG */
}

@end
