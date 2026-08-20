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

#include <LindChain/ProcEnvironment/Surface/proc/proctil.h>
#include <LindChain/ProcEnvironment/Surface/surface.h>
#include <LindChain/ProcEnvironment/Shims/panic.h>
#include <stdatomic.h>
#include <os/lock.h>

static atomic_int counter = 0;
static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;

kern_return_t proctil(ProctilAction action)
{
    switch(action)
    {
        case kProctilActionCount:
            if(atomic_fetch_add(&counter, 1) >= PROC_MAX)
            {
                atomic_fetch_sub(&counter, 1);
                return KERN_POLICY_LIMIT;
            }
            return KERN_SUCCESS;
        case kProctilActionUncount:
            if(atomic_fetch_sub(&counter, 1) == 0)
            {
                environment_panic("process count did underflow");
            }
            return KERN_SUCCESS;
        case kProctilActionLock:
            os_unfair_lock_lock(&lock);
            return KERN_SUCCESS;
        case kProctilActionUnlock:
            os_unfair_lock_unlock(&lock);
            return KERN_SUCCESS;
        case kProctilActionTrylock:
            return os_unfair_lock_trylock(&lock) ? KERN_SUCCESS : KERN_FAILURE;
        default:
            return KERN_INVALID_ARGUMENT;
    }
}

