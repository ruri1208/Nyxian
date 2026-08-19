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
#import <LindChain/ProcEnvironment/PEProcessManager.h>
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/ProcEnvironment/Utils/klog.h>
#import <LindChain/Services/applicationmgmtd/LDEApplicationWorkspace.h>
#import <LindChain/Services/containerd/PEContainer.h>
#import <LindChain/ProcEnvironment/PEExtension.h>
#import <LindChain/ProcEnvironment/PELaunchServiceManager.h>
#import <LindChain/ProcEnvironment/PEMachPort.h>
#import <LindChain/ProcEnvironment/Server/Server.h>
#import <LindChain/ProcEnvironment/Surface/proc/proctil.h>
#import <MobileDevelopmentKit/MDKThreadPool.h>

@implementation PEProcess {
    NSHashTable<id<PEProcessObserver>> *_observers;
    os_unfair_lock _lock;
}

@dynamic pid;

- (instancetype)initWithItems:(NSDictionary*)items
     withKernelSurfaceProcess:(ksurface_proc_t*)proc
{
    if(proctil(kProctilActionCount) != KERN_SUCCESS)
    {
        return nil;
    }
    
    self = [super init];
    if(self)
    {
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
        
        LDEApplicationObject *applicationObject = nil;
        
        if(PELaunchServiceManager.shared.isBooted)
        {
            applicationObject = [[LDEApplicationWorkspace shared] applicationObjectForExecutablePath:self.executablePath];
        }
        
        self.bundleIdentifier = applicationObject ? applicationObject.bundleIdentifier : nil;
        self.displayName = applicationObject ? applicationObject.localizedName : [self.executablePath lastPathComponent];
        
        /* spawning process */
        self.process = PESpawnFBProcess(items);
        if(self.process == nil)
        {
            proctil(kProctilActionUnlock);
            return nil;
        }
        
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
        kern_return_t kr = proc_fork_plus_exec(proc ?: kernel_proc_, &child, self.pid, [self.executablePath UTF8String]);
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
    }
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
    
    if(signal == SIGSTOP)
    {
        _isSuspended = YES;
    }
    else if(signal == SIGCONT)
    {
        _isSuspended = NO;
    }
    
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
    
    if(self.proc != NULL)
    {
        /* yep writing official wait4 code~~ */
        proc_state_change(self.proc, arg1.exitContext.underlyingContext.legacyCode);
        kern_return_t error = proc_zombify(self.proc);
        if(error != KERN_SUCCESS)
        {
            klog_log("LDEProcess", "failed to remove pid %d", self.pid);
        }
    }
    
    /* notify observers */
    [self enumerateObservers:^(id<PEProcessObserver> observer) {
        [observer process:self didExitWithWait4Code:arg1.exitContext.underlyingContext.legacyCode];
    }];
    
    [[PEProcessManager shared] unregisterProcessWithProcessIdentifier:self.pid];
}

- (void)processWillExit:(FBProcess *)arg1
{
    /* stub for when ever */
}

- (void)process:(FBProcess *)arg1 stateDidChangeFromState:(FBProcessState *)arg2 toState:(FBProcessState *)arg3
{
    /* stub for when ever */
}

- (id)forwardingTargetForSelector:(SEL)sel
{
    /* redirecting for pid */
    if([self.process respondsToSelector:sel])
    {
        return self.process;
    }
    return [super forwardingTargetForSelector:sel];
}

- (void)enumerateObservers:(void (^)(id<PEProcessObserver> observer))block
{
    os_unfair_lock_lock(&_lock);
    NSArray<id<PEProcessObserver>> *snapshot = _observers.allObjects;
    os_unfair_lock_unlock(&_lock);

    for (id<PEProcessObserver> observer in snapshot) {
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
}

@end
