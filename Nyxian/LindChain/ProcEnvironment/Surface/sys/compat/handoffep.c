/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab
 Copyright (C) 2026 zipgod24
 Copyright (C) 2026 semvis123

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

#include <LindChain/ProcEnvironment/Surface/sys/compat/handoffep.h>
#include <LindChain/ProcEnvironment/Surface/proc/def.h>
#include <LindChain/ProcEnvironment/Utils/klog.h>
#include <LindChain/ProcEnvironment/Utils/ktfp.h>

DEFINE_SYSCALL_HANDLER(handoffep)
{
    sys_need_in_ports(1, MACH_MSG_TYPE_MOVE_RECEIVE);
    
    kvo_wrlock(sys_proc_);
    if(sys_proc_->task != MACH_PORT_NULL)
    {
        /* task port's can only be initialized once per process lifecycle. */
        kvo_unlock(sys_proc_);
        sys_return_failure_with_errno(EPERM);
    }
    
    /* consuming the exception port so it won't be released by the send_reply symbol. */
    mach_port_t exceptionPort = sys_in_ports[0];
    sys_in_ports[0] = MACH_PORT_NULL;
    
    /*
     * reply to the guest process so that it can trigger the
     * pseudo exception using __builtin_trap.
     */
    send_reply((mach_msg_header_t*)*recv_buffer, 0, *out_ports, *out_ports_cnt, true, 0);
    *recv_buffer = NULL;    /* consuming the mach message header the syscall server uses so it won't attempt to reply. */
    
    task_t returnedTask;
    if(ktfp(exceptionPort, &returnedTask) != KERN_SUCCESS)
    {
        kvo_unlock(sys_proc_);
        sys_return;
    }
    
    /* validating the identity of the process behind the task port. */
    pid_t pid;
    kern_return_t kr = pid_for_task(returnedTask, &pid);
    if(kr != KERN_SUCCESS || pid != proc_getpid(sys_proc_snapshot_))
    {
        mach_port_deallocate(mach_task_self(), returnedTask);
        kvo_unlock(sys_proc_);
        sys_return;
    }
    
    sys_proc_->task = returnedTask;
    
    kvo_unlock(sys_proc_);
    kvo_event_trigger(sys_proc_, kProcEventTypeWaitTask, 0);
    sys_return;
}
