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

#include <LindChain/ProcEnvironment/Surface/sys/proc/proc_info.h>

DEFINE_SYSCALL_HANDLER(proc_info)
{
    /* parse arguments */
    int32_t u_callnum = (int32_t)args[0];
    pid_t u_pid = (pid_t)args[1];
    uint32_t u_flavour = (uint32_t)args[2];
    uint64_t u_arg = (uint64_t)args[3];
    userspace_pointer_t u_buffer = (userspace_pointer_t)args[4];
    int32_t buffersize = (int32_t)args[5];
    
    sys_return;
}
