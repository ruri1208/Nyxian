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

#include <LindChain/ProcEnvironment/Surface/sys/proc/kill.h>
#include <LindChain/ProcEnvironment/Surface/proc/proc.h>
#include <LindChain/ProcEnvironment/Surface/proc/permit.h>

DEFINE_SYSCALL_HANDLER(kill)
{    
    /* getting args, nu checks needed the syscall server does them */
    pid_t u_pid = (pid_t)args[0];
    int u_signal = (int)args[1];
    
    /* checking signal bounds */
    if(u_signal <= 0 || u_signal >= NSIG)
    {
        sys_return_failure_with_errno(EINVAL);
    }
    
    /*
     * checking if the caller process that makes the call is the same process,
     * also checks if the caller process has the entitlement to kill
     * and checks if the process has primitive over the other process.
     */
    if(!proc_snapshot_primitive_over_pid_allowed(sys_proc_snapshot_, u_pid, kPEEntitlementFlagProcessKill, kPEEntitlementFlagNone))
    {
        sys_return_failure_with_errno(errno);
    }
    
    ksurface_proc_t *target;
    kern_return_t kr = proc_for_pid(u_pid, &target);
    if(kr != KERN_SUCCESS)
    {
        sys_return_failure_with_errno(ESRCH);
    }
    
    /* making sure it is not ksurface it self */
    kvo_rdlock(target);
    if(target->bsd.kp_proc.p_flag & P_SYSTEM)
    {
        kvo_unlock(target);
        kvo_release(target);
        sys_return_failure_with_errno(EPERM);
    }
    kvo_unlock(target);
    
    kr = proc_kill(target, u_signal);
    kvo_release(target);
    if(kr != KERN_SUCCESS)
    {
        /* shall never happen */
        sys_return_failure_with_errno(EINVAL);
    }
    
    sys_return;
}
