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

#include <LindChain/ProcEnvironment/Surface/sys/compat/procpath.h>
#include <LindChain/ProcEnvironment/Surface/proc/proc.h>
#include <LindChain/ProcEnvironment/Surface/proc/list.h>

DEFINE_SYSCALL_HANDLER(procpath)
{
    /* prepare arguments */
    pid_t u_pid = (pid_t)args[0];
    userspace_pointer_t u_buffer_ptr = (userspace_pointer_t)args[1];
    userspace_pointer_t u_size_ptr = (userspace_pointer_t)args[2];
    
    /* getting target process */
    ksurface_proc_t *target;
    kern_return_t ret = proc_for_pid(u_pid, &target);
    if(ret != KERN_SUCCESS)
    {
        sys_return_failure_with_errno(EINVAL);
    }
    
    /* checking if caller can see target process */
    proc_visibility_t vis = proc_get_proc_visibility(sys_proc_snapshot_);
    if(!proc_can_see_proc(sys_proc_snapshot_, target, vis))
    {
        kvo_release(target);
        sys_return_failure_with_errno(ESRCH);
    }
    
    /* getting size of the userspace buffer */
    size_t u_size = 0;
    if(!syscall_copy_in(sys_task_, sizeof(size_t), &u_size, u_size_ptr))
    {
        sys_return_failure_with_errno(EFAULT);
    }
    
    /* getting buffer of target (we shouldn't hold it for long) */
    char path[PATH_MAX];
    _Static_assert(sizeof(target->nyx.identity->path) <= sizeof(path), "process path exceeds temporary buffer");
    kvo_rdlock(target);
    strlcpy(path, target->nyx.identity->path, sizeof(path));
    kvo_unlock(target);
    kvo_release(target);
    
    /* does the process path buffer fit into the userspace buffer */
    size_t size = strnlen(path, sizeof(path) - 1) + 1;
    if(u_size < size)
    {
        if(!syscall_copy_out(sys_task_, sizeof(size_t), &size, u_size_ptr))
        {
            sys_return_failure_with_errno(EFAULT);
        }
        sys_return_failure_with_errno(ERANGE);
    }
    
    /* final copy out */
    if(!syscall_copy_out(sys_task_, size, path, u_buffer_ptr))
    {
        sys_return_failure_with_errno(EFAULT);
    }
    sys_return;
}
