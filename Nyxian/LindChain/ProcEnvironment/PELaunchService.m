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

#import <LindChain/ProcEnvironment/PELaunchService.h>
#import <LindChain/ProcEnvironment/PEProcessManager.h>
#import <os/lock.h>

@implementation PELaunchService {
    os_unfair_lock _lock;
    PEProcess *_process;
    NSXPCListenerEndpoint *_endpoint;
    NSDictionary *_dictionary;
    
    /* properties for async access */
    NSString *_executablePath;
    NSString *_serviceIdentifier;
    BOOL _autoRestart;
}

+ (instancetype)launchServiceWithPlistPath:(NSString*)plistPath
{
    return [[self alloc] initWithPlistPath:plistPath];
}

- (instancetype)initWithPlistPath:(NSString*)plistPath
{
    self = [super init];
    if(self)
    {
        _lock = OS_UNFAIR_LOCK_INIT;
        _dictionary = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        if(_dictionary == NULL)
        {
            return nil;
        }
        
        /* TODO: add sanitization */
        _executablePath = _dictionary[@"PEExecutablePath"];
        _serviceIdentifier = _dictionary[@"PEServiceIdentifier"];
        _autoRestart = [((NSNumber*)[_dictionary valueForKey:@"PEShouldAutorestart"]) boolValue];
        
        if(_executablePath == NULL || _serviceIdentifier == NULL)
        {
            return nil;
        }
        
        [self ignition];
    }
    return self;
}

- (void)ignition
{
    NSDictionary *dictionary = _dictionary;
    
#if DEBUG
    extern int kfd;
    NSMutableDictionary *mutableDictionary = [_dictionary mutableCopy];
    PEFileTable *fileTable = [PEFileTable emptyTable];
    [fileTable appendFileDescriptor:kfd withMappingToLoc:STDOUT_FILENO];
    [fileTable appendFileDescriptor:kfd withMappingToLoc:STDERR_FILENO];
    [mutableDictionary setObject:fileTable forKey:@"PEFileTable"];
    dictionary = [mutableDictionary copy];
#endif /* DEBUG */
    
    /* getting lock */
    os_unfair_lock_lock(&_lock);
    pid_t pid = [[PEProcessManager shared] spawnProcessWithItems:dictionary withKernelSurfaceProcess:kernel_proc_];
    if(pid < 0)
    {
        return;
    }
    
    _process = [[PEProcessManager shared] processForProcessIdentifier:pid];
    if(_process == nil)
    {
        return;
    }
    
    /* now assign handlers */
    [_process addObserver:self];
    
    os_unfair_lock_unlock(&_lock);
}

- (BOOL)isServiceWithServiceIdentifier:(NSString*)serviceIdentifier
{
    return [_serviceIdentifier isEqualToString:serviceIdentifier];
}

- (PEProcess*)getProcess
{
    PEProcess *process = nil;
    os_unfair_lock_lock(&_lock);
    process = _process;
    os_unfair_lock_unlock(&_lock);
    return process;
}

- (NSString*)getExecutablePath
{
    return _executablePath;
}

- (NSString*)getServiceIdentifier
{
    return _serviceIdentifier;
}

- (BOOL)shouldAutorestart
{
    return _autoRestart;
}

- (void)process:(PEProcess *)process didExitWithWait4Code:(int)code
{
    if(self.shouldAutorestart)
    {
        [self ignition];
    }
}

- (void)dealloc
{
    [_process removeObserver:self];
    [_process sendSignal:SIGKILL];
    _process = nil;
}

@end
