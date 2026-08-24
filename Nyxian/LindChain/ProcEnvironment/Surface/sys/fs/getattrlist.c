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
#include <sys/attr.h>

#define KSURFACE_ATTRBUF_MAX  (1u << 20)

/* FIXME: now we need SYS_getattrlistbulk and the necessary patches in SYS_getattrlist */
DEFINE_SYSCALL_HANDLER(getattrlist)
{
    userspace_pointer_t user_path = (userspace_pointer_t)args[0];
    userspace_pointer_t user_attrlist = (userspace_pointer_t)args[1];
    userspace_pointer_t user_attrbuf = (userspace_pointer_t)args[2];
    size_t attrbufsz = (size_t)args[3];
    unsigned int options = (unsigned int)args[4];
    
    char *path = mach_syscall_copy_str_in(sys_task_, user_path, MAXPATHLEN);
    if(path == NULL)
    {
        printf("%p\n", path);
        fsync(STDOUT_FILENO);
        sys_return_failure_with_errno(EFAULT);
    }
    
    char host[MAXPATHLEN];
    sys_set_errno(vfs_host_path(path, host, sizeof host));
    free(path);
    if(sys_get_errno() != 0)
    {
        sys_return_failure();
    }
    
    struct attrlist al;
    if(!mach_syscall_copy_in(sys_task_, sizeof(al), &al, user_attrlist))
    {
        sys_return_failure_with_errno(EFAULT);
    }
    
    if(attrbufsz == 0 || attrbufsz > KSURFACE_ATTRBUF_MAX)
    {
        sys_return_failure_with_errno(EINVAL);
    }
    
    void *buf = malloc(attrbufsz);
    if(buf == NULL)
    {
        sys_return_failure_with_errno(ENOMEM);
    }
    
    if(getattrlist(host, &al, buf, attrbufsz, options) != 0)
    {
        int e = errno ? errno : EIO;
        free(buf);
        sys_return_failure_with_errno(e);
    }
    
    u_int32_t written = *(u_int32_t *)buf;
    if(written > attrbufsz)
    {
        written = (u_int32_t)attrbufsz;
    }
    
    bool success = mach_syscall_copy_out(sys_task_, written, buf, user_attrbuf);
    free(buf);
    if(!success)
    {
        sys_return_failure_with_errno(EFAULT);
    }
    
    sys_return;
}
