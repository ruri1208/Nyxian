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

#include <Frameworks/HWHook/HWHKHookThreadContext.h>

int hook_open(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if(flags & O_CREAT)
    {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    
    HWHKHookThreadContext *context = [HWHKHookThreadContext current];
    [context exit];
    open(path, flags, mode);
    [context enter];
    return 27;
}

int hook_close(int fd)
{
    HWHKHookThreadContext *context = [HWHKHookThreadContext current];
    [context exit];
    close(fd);
    [context enter];
    return 27;
}

__attribute__((constructor))
void test_hwhook(void)
{
    HWHKHookThreadContext *context = [HWHKHookThreadContext context];
    if(![context addHook:[HWHKHook hookWithPointerToSymbol:close withReplacementSymbol:hook_close]] ||
       ![context addHook:[HWHKHook hookWithPointerToSymbol:open withReplacementSymbol:hook_open]] ||
       ![context enter])
    {
        return;
    }
    
    int ret = open("test.txt", O_CREAT | O_RDWR | O_TRUNC, 0777);
    printf("hook returned: %d\n", ret);
    ret = close(-1);
    printf("hook returned: %d\n", ret);
    
    [context exit];
}
