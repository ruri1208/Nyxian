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

#import <LiveShim/LiveShimSyscall.h>
#import <LiveShim/shim.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

static OSStatus ksurface_SecItemAdd(CFDictionaryRef query, CFTypeRef *result);
static OSStatus ksurface_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result);
static OSStatus ksurface_SecItemUpdate(CFDictionaryRef query, CFTypeRef *result);
static OSStatus ksurface_SecItemDelete(CFDictionaryRef query);

INTERPOSE(ksurface_SecItemAdd, SecItemAdd);
INTERPOSE(ksurface_SecItemCopyMatching, SecItemCopyMatching);
INTERPOSE(ksurface_SecItemUpdate, SecItemUpdate);
INTERPOSE(ksurface_SecItemDelete, SecItemDelete);

NSMutableDictionary *SecItemPrepare(CFDictionaryRef query)
{
    NSMutableDictionary *queryCopy = ((__bridge NSDictionary *)query).mutableCopy;
    NSString *accessGroup = queryCopy[(__bridge id)kSecAttrAccessGroup];
    NSString *account = queryCopy[(__bridge id)kSecAttrAccount];
    
    if(!accessGroup)
    {
        accessGroup = [[NSBundle mainBundle] bundleIdentifier];
    }
    if(account)
    {
        [queryCopy removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        [queryCopy removeObjectForKey:(__bridge id)kSecAttrAccount];
        queryCopy[(__bridge id)kSecAttrAccount] = [NSString stringWithFormat:@"%@@%@", accessGroup, account];
    }
    else
    {
        [queryCopy removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
    }
    
    return queryCopy;
}

/* will later be ksurface syscalls (safe finally) */
static OSStatus ksurface_SecItemAdd(CFDictionaryRef query,
                                    CFTypeRef *result)
{
    OSStatus (*darwin_SecItemAdd)(CFDictionaryRef query, CFTypeRef *result) = _interpose_SecItemAdd.replacee;
    return darwin_SecItemAdd((__bridge CFDictionaryRef)SecItemPrepare(query), result);
}

static OSStatus ksurface_SecItemCopyMatching(CFDictionaryRef query,
                                             CFTypeRef *result)
{
    OSStatus (*darwin_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result) = _interpose_SecItemCopyMatching.replacee;
    return darwin_SecItemCopyMatching((__bridge CFDictionaryRef)SecItemPrepare(query), result);
}

static OSStatus ksurface_SecItemUpdate(CFDictionaryRef query,
                                       CFTypeRef *result)
{
    OSStatus (*darwin_SecItemUpdate)(CFDictionaryRef query, CFTypeRef *result) = _interpose_SecItemUpdate.replacee;
    return darwin_SecItemUpdate((__bridge CFDictionaryRef)SecItemPrepare(query), result);
}

static OSStatus ksurface_SecItemDelete(CFDictionaryRef query)
{
    OSStatus (*darwin_SecItemDelete)(CFDictionaryRef query) = _interpose_SecItemDelete.replacee;
    return darwin_SecItemDelete((__bridge CFDictionaryRef)SecItemPrepare(query));
}
