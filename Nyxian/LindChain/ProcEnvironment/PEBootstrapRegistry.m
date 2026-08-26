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

#import <LindChain/ProcEnvironment/PEBootstrapRegistry.h>
#import <LindChain/ProcEnvironment/Server/Server.h>
#import <os/lock.h>

@implementation PEBootstrapRegistry {
    os_unfair_lock _lock;
}

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        _registry = [[NSMutableDictionary alloc] init];
        if(_registry == nil)
        {
            return nil;
        }
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

+ (instancetype)shared
{
    static PEBootstrapRegistry *registrySingleton = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registrySingleton = [[PEBootstrapRegistry alloc] init];
    });
    return registrySingleton;
}

- (NSXPCListenerEndpoint*)getEndpointWithServiceIdentifier:(NSString*)serviceIdentifier
{
    mach_port_name_t port = [self getMachPortNameWithServiceIdentifier:serviceIdentifier];
    if(port == MACH_PORT_NULL)
    {
        return nil;
    }
    
    NSXPCListenerEndpoint *endpoint = [[NSXPCListenerEndpoint alloc] init];
    endpoint._endpoint = xpc_endpoint_create_mach_port_4sim(port);
    if(endpoint == nil || endpoint._endpoint == nil)
    {
        return nil;
    }
    
    return endpoint;
}

- (mach_port_name_t)getMachPortNameWithServiceIdentifier:(NSString*)serviceIdentifier
{
    os_unfair_lock_lock(&_lock);
    NSNumber *number = _registry[serviceIdentifier];
    os_unfair_lock_unlock(&_lock);
    return [number unsignedIntValue];
}

- (void)setMachPortName:(mach_port_name_t)port
   forServiceIdentifier:(NSString*)serviceIdentifier
{
    os_unfair_lock_lock(&_lock);
    _registry[serviceIdentifier] = [NSNumber numberWithUnsignedLong:port];
    os_unfair_lock_unlock(&_lock);
}

@end
