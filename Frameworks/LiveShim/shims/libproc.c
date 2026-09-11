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

#include <LiveShim/shim.h>
#include <Nyxian/LindChain/ProcEnvironment/Surface/libkern/bsd/proc_info.h>

#if LIVESHIM_PROC_ENABLED

extern int __proc_info(int32_t callnum, int32_t pid, uint32_t flavor, uint64_t arg, user_addr_t buffer, int32_t buffersize);

static int __ksurface_proc_info(int32_t callnum, int32_t pid, uint32_t flavor, uint64_t arg, user_addr_t buffer, int32_t buffersize);
static int ksurface_proc_pidinfo(pid_t pid, int flavor, uint64_t arg, void * buffer, int buffersize);
static int ksurface_proc_name(pid_t pid, void *buffer, uint32_t buffersize);
static int ksurface_proc_pidpath(pid_t pid, void *buffer, uint32_t buffersize);
static int ksurface_proc_listallpids(void *buffer, int buffersize);
static int ksurface_proc_pid_rusage(int pid, int flavor, rusage_info_t *buffer);
static int ksurface_proc_kmsgbuf(void *buffer, uint32_t buffersize);
static int ksurface_kill(pid_t pid, int sig);
static int ksurface_raise(int sig);

INTERPOSE(__ksurface_proc_info, __proc_info);
INTERPOSE(ksurface_proc_pidinfo, proc_pidinfo);
INTERPOSE(ksurface_proc_name, proc_name);
INTERPOSE(ksurface_proc_pidpath, proc_pidpath);
INTERPOSE(ksurface_proc_listallpids, proc_listallpids);
INTERPOSE(ksurface_proc_pid_rusage, proc_pid_rusage);
INTERPOSE(ksurface_proc_kmsgbuf, proc_kmsgbuf);
INTERPOSE(ksurface_kill, kill);
INTERPOSE(ksurface_raise, raise);

static int __ksurface_proc_info(int32_t callnum,
                                int32_t pid,
                                uint32_t flavor,
                                uint64_t arg,
                                user_addr_t buffer,
                                int32_t buffersize)
{
    errno = 0;
    int ret = (int)liveshim_syscall(SYS_proc_info, callnum, pid, flavor, arg, buffer, buffersize);
    if(errno == ENOSYS)
    {
        int (*__darwin_proc_info)(int32_t callnum, int32_t pid, uint32_t flavor, uint64_t arg, user_addr_t buffer, int32_t buffersize) = _interpose___proc_info.replacee;
        __darwin_proc_info(callnum, pid, flavor, arg, buffer, buffersize);
    }
    return ret;
}

static int ksurface_proc_pidinfo(pid_t pid,
                                 int flavor,
                                 uint64_t arg,
                                 void * buffer,
                                 int buffersize)
{
    errno = 0;
    int ret = (int)liveshim_syscall(SYS_proc_info, PROC_INFO_CALL_PIDINFO, pid, flavor, 0, buffer, buffersize);
    if(errno == ENOSYS)
    {
        int (*darwin_proc_pidinfo)(pid_t pid, int flavor, uint64_t arg, void * buffer, int buffersize) = _interpose_proc_pidinfo.replacee;
        return darwin_proc_pidinfo(pid, flavor, arg, buffer, buffersize);
    }
    return ret;
}

static int ksurface_proc_name(pid_t pid,
                              void *buffer,
                              uint32_t buffersize)
{
    struct proc_bsdinfo pbsd;
    if(buffersize < sizeof(pbsd.pbi_name))
    {
        errno = ENOMEM;
        return 0;
    }
    
    int retval = ksurface_proc_pidinfo(pid, PROC_PIDTBSDINFO, 0,  &pbsd, sizeof(pbsd));
    if(retval != 0)
    {
        if(pbsd.pbi_name[0])
        {
            bcopy(&pbsd.pbi_name, buffer, sizeof(pbsd.pbi_name));
        }
        else
        {
            bcopy(&pbsd.pbi_comm, buffer, sizeof(pbsd.pbi_comm));
        }
        return (int)strlen(buffer);
    }
    return 0;
}

static int ksurface_proc_pidpath(pid_t pid,
                                 void *buffer,
                                 uint32_t buffersize)
{
    /* sanity check */
    if(buffersize == 0 || buffer == NULL)
    {
        return 0;
    }
    
    /* syscall with SYS_PROCPATH */
    int retval = ksurface_proc_pidinfo(pid, PROC_PIDPATHINFO, 0, buffer, buffersize);
    if(retval != 0)
    {
        return 0;
    }
    
    /* final return of lenght */
    return (int)strlen((char*)buffer);
}

static int ksurface_proc_listallpids(void *buffer,
                                     int buffersize)
{
    if(buffersize < 0)
    {
        errno = EINVAL;
        return -1;
    }
    
    if(buffersize < 0)
    {
        errno = EINVAL;
        return -1;
    }
    
    struct kinfo_proc kp[500];
    size_t len = sizeof(kp);
    
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    extern int ksurface_user_sysctl(int *name, u_int namelen, void *__sized_by(*oldlenp) oldp, size_t *oldlenp, void *__sized_by(newlen) newp, size_t newlen);
    ksurface_user_sysctl(mib, 3, &kp, &len, NULL, 0);
    
    size_t count = (uint32_t)(len / sizeof(struct kinfo_proc));
    
    size_t n = 0;
    size_t needed_bytes = 0;
    
    needed_bytes = (size_t)count * sizeof(pid_t);
    
    if(buffer != NULL && buffersize > 0)
    {
        size_t capacity = (size_t)buffersize / sizeof(pid_t);
        n = count < capacity ? count : capacity;
        
        pid_t *pids = (pid_t *)buffer;
        
        for(size_t i = 0; i < n; i++)
        {
            pids[i] = kp[i].kp_proc.p_pid;
        }
    }
    
    if(buffer == NULL || buffersize == 0)
    {
        return (int)needed_bytes;
    }
    
    return (int)(n * sizeof(pid_t));
}

static int ksurface_proc_pid_rusage(int pid,
                                    int flavor,
                                    rusage_info_t *buffer)
{
    int retval = (int)liveshim_syscall(SYS_proc_info, PROC_INFO_CALL_PIDRUSAGE, pid, (uint32_t)flavor, (uint64_t)0, buffer, 0);
    if(retval != 0)
    {
        int (*darwin_proc_pid_rusage)(int pid, int flavor, rusage_info_t *buffer) = _interpose_proc_pid_rusage.replacee;
        return darwin_proc_pid_rusage(pid, flavor, buffer);
    }
    return retval;
}

static int ksurface_proc_kmsgbuf(void *buffer,
                                 uint32_t buffersize)
{
    return (int)liveshim_syscall(SYS_proc_info, PROC_INFO_CALL_KERNMSGBUF, 0, 0, (uint64_t)0, buffer, buffersize);
}

static int ksurface_kill(pid_t pid,
                         int sig)
{
    return (int)liveshim_syscall(SYS_kill, pid, sig);
}

static int ksurface_raise(int sig)
{
    return ksurface_kill(getpid(), sig);
}

#endif /* LIVESHIM_PROC_ENABLED */
