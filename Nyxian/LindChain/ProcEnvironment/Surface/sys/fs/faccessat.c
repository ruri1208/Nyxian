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

#include <LindChain/ProcEnvironment/Surface/sys/fs/faccessat.h>
#include <LindChain/ProcEnvironment/Surface/vfs/vfs.h>

DEFINE_SYSCALL_HANDLER(faccessat)
{
    int user_dirFd = (int)args[0];
    userspace_pointer_t user_path = (userspace_pointer_t)args[1];
    int mode = (int)args[2];
    /*
    int flags = (int)args[3];
     */
    
    /* means we take in raw path or nah */
    if(user_dirFd != AT_FDCWD)
    {
        sys_return_failure_with_errno(ENOSYS);
        //sys_need_in_ports(1, MACH_MSG_TYPE_MOVE_SEND);
    }
    
    char *path = mach_syscall_copy_str_in(sys_task_, user_path, MAXPATHLEN);
    if(path == NULL)
    {
        sys_return_failure_with_errno(EFAULT);
    }
    
    const char *sub = vfs_match_mount(path);
    if(sub == NULL)
    {
        free(path);
        sys_return_failure_with_errno(ENOSYS);
    }
    
    char rel[MAXPATHLEN];
    bool ok = vfs_resolve_rel(sub, rel, sizeof rel);
    free(path);
    if(!ok)
    {
        sys_return_failure_with_errno(ENOENT);
    }
    
    switch(mode)
    {
        case F_OK:
        case R_OK:
            return 0;
        default:
            return -1;
    }
}
