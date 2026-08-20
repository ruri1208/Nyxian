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

#import "CFRuntime.h"
#import "HWHKHookThreadContext.h"

@implementation HWHKHookThreadContext

+ (void)load
{
    _CFRuntimeBridgeClasses(HWHookThreadContextGetTypeID(), "HWHKHookThreadContext");
}

+ (instancetype)current
{
    return (__bridge HWHKHookThreadContext*)HWHookThreadContextGetCurrent();
}

+ (instancetype)context
{
    return (__bridge_transfer HWHKHookThreadContext*)HWHookThreadContextCreate(kCFAllocatorDefault);
}

- (BOOL)enter
{
    return HWHookThreadContextEnter((__bridge HWHookThreadContextRef)self);
}

- (BOOL)exit
{
    return HWHookThreadContextExit((__bridge HWHookThreadContextRef)self);
}

- (BOOL)enableHooks
{
    return HWHookThreadContextEnableHooks((__bridge HWHookThreadContextRef)self);
}

- (BOOL)disableHooks
{
    return HWHookThreadContextDisableHooks((__bridge HWHookThreadContextRef)self);
}

- (BOOL)addHook:(HWHKHook *)hook
{
    return HWHookThreadContextAppendHook((__bridge HWHookThreadContextRef)self, (__bridge HWHookRef)hook);
}

@end
