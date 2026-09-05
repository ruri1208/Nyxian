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
#include <LindChain/ProcEnvironment/Surface/proc/lookup.h>
#include <LindChain/ProcEnvironment/Surface/proc/spawn.h>
#include <LindChain/ProcEnvironment/Surface/proc/permit.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <os/lock.h>

static os_unfair_lock g_kernmsgbuf_lock = OS_UNFAIR_LOCK_INIT;

DEFINE_SYSCALL_HANDLER(proc_info_listpids)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_pidinfo)
{
    uint32_t u_flavour = (uint32_t)args[2];
    
    switch(u_flavour)
    {
        case PROC_PIDLISTFDS:
        case PROC_PIDTASKALLINFO:
        case PROC_PIDTBSDINFO:
        case PROC_PIDTASKINFO:
        case PROC_PIDTHREADINFO:
        case PROC_PIDLISTTHREADS:
        case PROC_PIDREGIONINFO:
        case PROC_PIDREGIONPATHINFO:
        case PROC_PIDVNODEPATHINFO:
        case PROC_PIDTHREADPATHINFO:
            sys_return_failure_with_errno(ENOSYS);
        case PROC_PIDPATHINFO:
        {
            /* prepare arguments */
            pid_t u_pid = (pid_t)args[1];
            userspace_pointer_t u_buffer_ptr = (userspace_pointer_t)args[4];
            int32_t u_size = (int32_t)args[5];
            
            if(u_size < PROC_PIDPATHINFO_SIZE)
            {
                /* XNU semantic */
                sys_return_failure_with_errno(ENOMEM);
            }
            
            if(u_size > PROC_PIDPATHINFO_MAXSIZE)
            {
                /* XNU semantic */
                sys_return_failure_with_errno(EOVERFLOW);
            }
            
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
            
            /* getting buffer of target (we shouldn't hold it for long) */
            char path[sizeof(target->nyx.identity->path)];
            kvo_rdlock(target);
            size_t size = strlcpy(path, target->nyx.identity->path, sizeof(target->nyx.identity->path)) + 1;
            kvo_unlock(target);
            kvo_release(target);
            
            /* final copy out */
            if(!syscall_copy_out(sys_task_, size, path, u_buffer_ptr))
            {
                sys_return_failure_with_errno(EFAULT);
            }
            sys_return;
        }
        case PROC_PIDWORKQUEUEINFO:
        case PROC_PIDT_SHORTBSDINFO:
        case PROC_PIDLISTFILEPORTS:
        case PROC_PIDTHREADID64INFO:
        case PROC_PIDUNIQIDENTIFIERINFO:
        case PROC_PIDT_BSDINFOWITHUNIQID:
        case PROC_PIDARCHINFO:
        case PROC_PIDCOALITIONINFO:
        case PROC_PIDNOTEEXIT:
        case PROC_PIDREGIONPATHINFO2:
        case PROC_PIDREGIONPATHINFO3:
        case PROC_PIDEXITREASONINFO:
        case PROC_PIDEXITREASONBASICINFO:
        case PROC_PIDLISTUPTRS:
        case PROC_PIDLISTDYNKQUEUES:
        case PROC_PIDLISTTHREADIDS:
        case PROC_PIDVMRTFAULTINFO:
        case PROC_PIDPLATFORMINFO:
        case PROC_PIDREGIONPATH:
        case PROC_PIDIPCTABLEINFO:
        default:
            sys_return_failure_with_errno(ENOSYS);
    }
    sys_return_failure_with_errno(EINVAL);
}

DEFINE_SYSCALL_HANDLER(proc_info_pidfdinfo)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_kernmsgbuf)
{
    /* first permission checks */
    if(proc_geteuid(sys_proc_snapshot_) != 0 && !entitlement_got_entitlement(proc_getmaxentitlements(sys_proc_snapshot_), kPEEntitlementFlagPlatform))
    {
        sys_return_failure_with_errno(EPERM);
    }
    
    /* parsing arguments */
    userspace_pointer_t u_buffer = (userspace_pointer_t)args[4];
    int32_t u_buffersize = (int32_t)args[5];
    
    /* getting size */
    extern int kfd; /* file descriptor to kernel log */
    struct stat kfdstat;
    if(fstat(kfd, &kfdstat) != 0)
    {
        return 0;
    }
    off_t currentSize = kfdstat.st_size;
    off_t copySize = (u_buffersize < currentSize) ? u_buffersize : currentSize;
    
    /* is it asking for the size? */
    if(u_buffersize == 0 && u_buffer == NULL)
    {
        return (int)currentSize;
    }
    
    /* copy! (locked so it doesn't become a memory starvation vector) */
    os_unfair_lock_lock(&g_kernmsgbuf_lock);
    void *klog_mem = mmap(NULL, currentSize, PROT_READ, MAP_SHARED, kfd, 0);
    if(klog_mem == MAP_FAILED)
    {
        os_unfair_lock_unlock(&g_kernmsgbuf_lock);
        sys_return_failure_with_errno(ENOMEM);  /* "if you run out of memory, you run out of memory" - speedyfriendy67 (such a retarded quote bruh ^^) */
    }
    bool success = syscall_copy_out(sys_task_, copySize, klog_mem, u_buffer);
    munmap(klog_mem, currentSize);
    os_unfair_lock_unlock(&g_kernmsgbuf_lock);
    if(!success)
    {
        sys_return_failure_with_errno(EFAULT);
    }
    
    return (int)copySize;
}

DEFINE_SYSCALL_HANDLER(proc_info_setcontrol)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_pidfileportinfo)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_terminate)
{
    /* parsing arguments */
    pid_t u_pid = (pid_t)args[1];
    
    if(!proc_snapshot_primitive_over_pid_allowed(sys_proc_snapshot_, u_pid, kPEEntitlementFlagProcessKill, kPEEntitlementFlagNone))
    {
        sys_return_failure_with_errno(errno);
    }
    
    /* we need the process */
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
    
    /* now terminating it lol */
    proc_kill(target, SIGKILL);
    kvo_release(target);
    sys_return;
}

DEFINE_SYSCALL_HANDLER(proc_info_dirtycontrol)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_pidrusage)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_pidoriginatorinfo)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_listcoalitions)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_canusefghw)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_piddynkqueueinfo)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info_udata_info)
{
    sys_return_failure_with_errno(ENOSYS);
}

DEFINE_SYSCALL_HANDLER(proc_info)
{
    /* parse arguments */
    int32_t u_callnum = (int32_t)args[0];
    /*
     * pid_t u_pid = (pid_t)args[1];
     * uint32_t u_flavour = (uint32_t)args[2];
     * uint64_t u_arg = (uint64_t)args[3];
     * userspace_pointer_t u_buffer = (userspace_pointer_t)args[4];
     * int32_t u_buffersize = (int32_t)args[5];
     */
    
    switch(u_callnum)
    {
        case PROC_INFO_CALL_LISTPIDS:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_listpids);
        case PROC_INFO_CALL_PIDINFO:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_pidinfo);
        case PROC_INFO_CALL_PIDFDINFO:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_pidfdinfo);
        case PROC_INFO_CALL_KERNMSGBUF:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_kernmsgbuf);
        case PROC_INFO_CALL_SETCONTROL:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_setcontrol);
        case PROC_INFO_CALL_PIDFILEPORTINFO:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_pidfileportinfo);
        case PROC_INFO_CALL_TERMINATE:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_terminate);
        case PROC_INFO_CALL_DIRTYCONTROL:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_dirtycontrol);
        case PROC_INFO_CALL_PIDRUSAGE:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_pidrusage);
        case PROC_INFO_CALL_PIDORIGINATORINFO:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_pidoriginatorinfo);
        case PROC_INFO_CALL_LISTCOALITIONS:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_listcoalitions);
        case PROC_INFO_CALL_CANUSEFGHW:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_canusefghw);
        case PROC_INFO_CALL_PIDDYNKQUEUEINFO:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_piddynkqueueinfo);
        case PROC_INFO_CALL_UDATA_INFO:
            return SYSCALL_HANDLER_REDIRECT_TO_HANDLER(proc_info_udata_info);
        default:
            break;
    }
    sys_return_failure_with_errno(ENOSYS);
}
