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

#ifndef HWHOOK_H
#define HWHOOK_H

#include <CoreFoundation/CoreFoundation.h>

typedef struct __HWHook *HWHookRef;

CF_EXPORT CFTypeID HWHookGetTypeID(void);

CF_EXPORT HWHookRef HWHookCreateWithPointerToSymbol(CFAllocatorRef allocator, void *symbol, void *replacement);

CF_EXPORT void *HWHookGetSymbolPtr(HWHookRef hook);
CF_EXPORT void *HWHookGetReplacementPtr(HWHookRef hook);

/*
 * makes you able to call original symbols without manually
 * fiddling around, the hooking server will disable automatically
 * all hooks in the context and add a new stack frame which calls a
 * symbol that reenables all hooks in the context.
 */
CF_EXPORT Boolean HWHookGetDisableContextHooksInFrame(HWHookRef hook);
CF_EXPORT void HWHookSetDisableContextHooksInFrame(HWHookRef hook, Boolean disableContextHooksInFrame);

#endif /* HWHOOK_H */
