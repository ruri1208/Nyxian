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

#include <LindChain/ProcEnvironment/Surface/sys/cred/getsid.h>
#include <LindChain/ProcEnvironment/Surface/proc/lookup.h>
#include <LindChain/ProcEnvironment/Surface/proc/list.h>
#include <LindChain/ProcEnvironment/Surface/proc/permit.h>

DEFINE_SYSCALL_HANDLER(getsid)
{
    pid_t pid = (pid_t)args[0];
    
    /* getting process */
    ksurface_proc_t *target = NULL;
    kern_return_t kr = proc_for_pid(pid, &target);
    if(kr != KERN_SUCCESS || target == NULL)
    {
        sys_return_failure_with_errno(ESRCH);
    }
    
    /* visibility check  */
    proc_visibility_t vis = proc_get_proc_visibility(sys_proc_snapshot_);
    if(!proc_can_see_proc(sys_proc_snapshot_, target, vis))
    {
        kvo_release(target);
        sys_return_failure_with_errno(ESRCH);
    }
    
    /* getting sid */
    kvo_rdlock(target);
    pid_t sid = target->nyx.sid;
    kvo_unlock(target);
    kvo_release(target);
    
    return sid;
}
