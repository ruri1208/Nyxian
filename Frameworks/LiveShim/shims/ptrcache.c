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

#include <LiveShim/ptrcache.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <limits.h>
#include <fcntl.h>
#include <errno.h>
#include <os/lock.h>

uint64_t ptrcache[kDyldPtrCount];

static bool g_have_ptrcache = false;
static os_unfair_lock g_lock = OS_UNFAIR_LOCK_INIT;

bool load_ptrcache(void)
{
    os_unfair_lock_lock(&g_lock);
    if(g_have_ptrcache)
    {
        os_unfair_lock_unlock(&g_lock);
        return true;
    }
    
    char *rootPath = getenv("NXROOT");
    if(!rootPath)
    {
        os_unfair_lock_unlock(&g_lock);
        return false;
    }
    
    char path[PATH_MAX];
    snprintf(path, PATH_MAX, "%s/boot/ptrcache", rootPath);
    int fd = open(path, O_RDONLY);
    if(fd < 0)
    {
        os_unfair_lock_unlock(&g_lock);
        return false;
    }
    
    size_t done = 0;
    while(done < sizeof(ptrcache))
    {
        ssize_t n = read(fd, (char *)ptrcache + done, sizeof(ptrcache) - done);
        if(n > 0)
        {
            done += (size_t)n;
            continue;
        }
        if(n < 0 && errno == EINTR)
        {
            continue;
        }
        close(fd);
        os_unfair_lock_unlock(&g_lock);
        return false;
    }
    
    g_have_ptrcache = true;
    os_unfair_lock_unlock(&g_lock);
    close(fd);
    return true;
}
