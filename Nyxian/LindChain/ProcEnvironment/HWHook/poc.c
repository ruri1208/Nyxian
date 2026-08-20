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

#include <LindChain/ProcEnvironment/HWHook/HWHookThreadContext.h>

int test_open(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if(flags & O_CREAT)
    {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    
    HWHookThreadContextExit(HWHookThreadContextGetCurrent());
    return open(path, flags, mode);
}

__attribute__((constructor))
void test_hwhook(void)
{
    HWHookRef hook = HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, open, test_open);
    if(hook == NULL)
    {
        exit(1);
    }
    
    HWHookThreadContextRef context = HWHookThreadContextCreate(kCFAllocatorDefault);
    if(context == NULL)
    {
        CFRelease(hook);
        exit(1);
    }
    
    if(!HWHookThreadContextAppendHook(context, hook) ||
       !HWHookThreadContextEnter(context))
    {
        CFRelease(hook);
        CFRelease(context);
        exit(1);
    }
    
    int ret = open("test.txt", O_CREAT | O_RDWR, 0777);
    printf("hook returned: %d\n", ret);
}
