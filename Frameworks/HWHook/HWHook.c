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

#include "CFRuntime.h"
#include "HWHook.h"

static CFTypeID gHWHookTypeID = _kCFRuntimeNotATypeID;

struct __HWHook {
    CFRuntimeBase _base;
    void *symbol;
    void *replacement;
};

static const CFRuntimeClass gHWHook = {
    0,                              /* version */
    "HWHook",                       /* class name */
    NULL,                           /* init */
    NULL,                           /* copy */
    NULL,                           /* finalize */
    NULL,                           /* equal */
    NULL,                           /* hash */
    NULL,                           /* copyFormattingDesc */
    NULL,                           /* copyDebugDesc */
    NULL,
    NULL,
    0
};

CFTypeID HWHookGetTypeID(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gHWHookTypeID = _CFRuntimeRegisterClass(&gHWHook);
    });
    return gHWHookTypeID;
}

HWHookRef HWHookCreateWithPointerToSymbol(CFAllocatorRef allocator,
                                          void *symbol,
                                          void *replacement)
{
    HWHookRef hook = (HWHookRef)_CFRuntimeCreateInstance(allocator, HWHookGetTypeID(), sizeof(struct __HWHook) - sizeof(CFRuntimeBase), NULL);
    if(hook == NULL)
    {
        return NULL;
    }
    
    hook->symbol = symbol;
    hook->replacement = replacement;
    
    return hook;
}

void *HWHookGetSymbolPtr(HWHookRef hook)
{
    if(hook == NULL)
    {
        return NULL;
    }
    return hook->symbol;
}

void *HWHookGetReplacementPtr(HWHookRef hook)
{
    if(hook == NULL)
    {
        return NULL;
    }
    return hook->replacement;
}

