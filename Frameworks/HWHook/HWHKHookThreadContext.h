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

#ifndef HWHKHOOKTHREADCONTEXT_H
#define HWHKHOOKTHREADCONTEXT_H

#import <Foundation/Foundation.h>
#import "HWHookThreadContext.h"
#import "HWHKCFType.h"
#import "HWHKHook.h"

@interface HWHKHookThreadContext : HWHKCFType

+ (instancetype)current;
+ (instancetype)context;

- (BOOL)enter;
- (BOOL)exit;

- (BOOL)addHook:(HWHKHook*)hook;

@end

#endif /* HWHKHOOKTHREADCONTEXT_H */
