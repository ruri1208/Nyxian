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

#import <LindChain/ProcEnvironment/Surface/sys/compat/sign.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCUtils.h>
#import <LindChain/ProcEnvironment/Utils/vnode.h>
#import <LindChain/Private/mach/fileport.h>

DEFINE_SYSCALL_HANDLER(sign)
{
    sys_need_in_ports(1, MACH_MSG_TYPE_MOVE_SEND);
    
    /*
     * checking entitlements weither the process is entitled enough to
     * sign unsigned binaries for opening or executing them, this is
     * done by checking if it is entitled to spawn processes, this
     * entitlement is meant to be a arbitary spawn entitlement against
     * equevalents like PEEntitlementProcessSpawnSignedOnly which is
     * used to only allow the spawn of binaries which are already signed.
     * all this is done to ensure the user does consent do these things!
     */
    if(!entitlement_got_entitlement(proc_getentitlements(sys_proc_), kPEEntitlementFlagProcessSpawn))
    {
        sys_return_failure_with_errno(EPERM);
    }
    
    /* extract file descriptor out of mach port capability */
    fileport_t fp = sys_in_ports[0];
    int fd = fileport_makefd(fp);
    if(fd < 0)
    {
        sys_return_failure_with_errno(EBADF);
    }
    
    int flags = fcntl(fd, F_GETFL);
    if(flags == -1)
    {
        close(fd);
        sys_return_failure_with_errno(EBADF);
    }
    
    if((flags & O_ACCMODE) != O_RDWR)
    {
        close(fd);
        sys_return_failure_with_errno(EBADF);
    }
    
    char path[MAXPATHLEN];
    int ret = fcntl(fd, F_GETPATH, path);
    close(fd);
    if(ret != 0)
    {
        sys_return_failure_with_errno(EBADF);
    }
    
    NSString *nsPath = [NSString stringWithCString:path encoding:NSUTF8StringEncoding];
    if(nsPath == nil)
    {
        sys_return_failure_with_errno(ENOMEM);
    }
    
    /* signing that shit */
    if(![LCUtils signMachOAtURL:[NSURL fileURLWithPath:nsPath]])
    {
        sys_return_failure_with_errno(ENOEXEC);
    }
    vnode_refresh_with_path([nsPath UTF8String]);
    
    sys_return;
}
