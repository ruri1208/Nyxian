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

#ifndef HWHOOKTHREADCONTEXT_H
#define HWHOOKTHREADCONTEXT_H

#include <CoreFoundation/CoreFoundation.h>
#include <LindChain/ProcEnvironment/HWHook/HWHook.h>

typedef struct __HWHookThreadContext *HWHookThreadContextRef;

CF_EXPORT CFTypeID HWHookThreadContextGetTypeID(void);

/* so you can exit the context easily */
CF_EXPORT HWHookThreadContextRef HWHookThreadContextGetCurrent(void);

/* one context per thread! */
CF_EXPORT HWHookThreadContextRef HWHookThreadContextCreate(CFAllocatorRef allocator);

/* enters on a per thread basis */
CF_EXPORT Boolean HWHookThreadContextEnter(HWHookThreadContextRef context);
CF_EXPORT Boolean HWHookThreadContextExit(HWHookThreadContextRef context);

/*
 * you have to exit the context to call the original
 * other than that this hooks symbols until the context
 * ran out.
 */
CF_EXPORT Boolean HWHookThreadContextAppendHook(HWHookThreadContextRef context, HWHookRef hook);

#endif /* HWHOOKTHREADCONTEXT_H */
