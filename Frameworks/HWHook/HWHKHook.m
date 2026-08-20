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
#import "HWHKHook.h"

@implementation HWHKHook

@dynamic disableContextHooksInFrame;
@dynamic symbolPtr;
@dynamic replacementPtr;

+ (void)load
{
    _CFRuntimeBridgeClasses(HWHookGetTypeID(), "HWHKHook");
}

+ (instancetype)hookWithPointerToSymbol:(void *)symbol
                  withReplacementSymbol:(void *)replacement
{
    return (__bridge_transfer HWHKHook*)HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, symbol, replacement);
}

- (void*)symbolPtr
{
    return HWHookGetSymbolPtr((__bridge HWHookRef)self);
}

- (void*)replacementPtr
{
    return HWHookGetReplacementPtr((__bridge HWHookRef)self);
}

- (BOOL)disableContextHooksInFrame
{
    return HWHookGetDisableContextHooksInFrame((__bridge HWHookRef)self);
}

- (void)setDisableContextHooksInFrame:(BOOL)disableContextHooksInFrame
{
    HWHookSetDisableContextHooksInFrame((__bridge HWHookRef)self, disableContextHooksInFrame);
}

@end
