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

#include <LiveShim/shim.h>
#include <LiveShim/fileport.h>
#include <Broadpatch/Broadpatch.h>
#include <util.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <errno.h>

LIBKERN_PATCH(int, openpty, (int *amaster,
                             int *aslave,
                             char *name,
                             struct termios *termp,
                             struct winsize *winp),
{
    if(amaster == NULL || aslave == NULL)
    {
        errno = EINVAL;
        return -1;
    }
    
    mach_port_t master_port = MACH_PORT_NULL;
    mach_port_t slave_port  = MACH_PORT_NULL;
    
    int ret = (int)liveshim_syscall(SYS_openpty, &master_port, &slave_port);
    if(ret != 0)
    {
        return -1;
    }
    
    int master = fileport_makefd(master_port);
    int slave = fileport_makefd(slave_port);
    
    mach_port_deallocate(mach_task_self(), master_port);
    mach_port_deallocate(mach_task_self(), slave_port);
    
    if(master < 0 || slave < 0)
    {
        if(master >= 0)
        {
            close(master);
        }
        if(slave >= 0)
        {
            close(slave);
        }
        errno = EBADF;
        return -1;
    }
    
    if(termp != NULL)
    {
        if(tcsetattr(slave, TCSANOW, termp) != 0)
        {
            close(master);
            close(slave);
            return -1;
        }
    }
    
    if(winp != NULL)
    {
        if(ioctl(slave, TIOCSWINSZ, winp) != 0)
        {
            close(master);
            close(slave);
            return -1;
        }
    }
    
    if(name != NULL)
    {
        name[0] = '\0';
    }
    
    *amaster = master;
    *aslave = slave;
    
    return 0;
});

__attribute__((constructor))
static void InstallPTYPatches(void)
{
    LIBKERN_INSTALL_PATCH(openpty);
}
