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

#if DEBUG

#import <LindChain/ProcEnvironment/PESurfaceTools.h>
#import <LindChain/ProcEnvironment/Surface/proc/list.h>

@implementation PESurfaceProcDescriptor

- (instancetype)initWithProc:(ksurface_proc_t*)proc
{
    self = [super init];
    if(self)
    {
        if(!kvo_retain(proc))
        {
            return nil;
        }
        
        _rawProc = proc;
        
        kvo_rdlock(proc);
        _pid = proc_getpid(proc);
        _ppid = proc_getppid(proc);
        kvo_unlock(proc);
    }
    return self;
}

- (void)dealloc
{
    kvo_release(_rawProc);
}

- (uid_t)euid
{
    kvo_rdlock(_rawProc);
    uid_t euid = proc_geteuid(_rawProc);
    kvo_unlock(_rawProc);
    return euid;
}

- (uid_t)ruid
{
    kvo_rdlock(_rawProc);
    uid_t euid = proc_getruid(_rawProc);
    kvo_unlock(_rawProc);
    return euid;
}

- (uid_t)svuid
{
    kvo_rdlock(_rawProc);
    uid_t euid = proc_getsvuid(_rawProc);
    kvo_unlock(_rawProc);
    return euid;
}

- (void)setEuid:(uid_t)euid
{
    kvo_wrlock(_rawProc);
    proc_seteuid(_rawProc, euid);
    kvo_unlock(_rawProc);
}

- (void)setRuid:(uid_t)euid
{
    kvo_wrlock(_rawProc);
    proc_setruid(_rawProc, euid);
    kvo_unlock(_rawProc);
}

- (void)setSvuid:(uid_t)svuid
{
    kvo_wrlock(_rawProc);
    proc_setsvuid(_rawProc, svuid);
    kvo_unlock(_rawProc);
}

- (uid_t)egid
{
    kvo_rdlock(_rawProc);
    uid_t euid = proc_getegid(_rawProc);
    kvo_unlock(_rawProc);
    return euid;
}

- (uid_t)rgid
{
    kvo_rdlock(_rawProc);
    uid_t euid = proc_getrgid(_rawProc);
    kvo_unlock(_rawProc);
    return euid;
}

- (uid_t)svgid
{
    kvo_rdlock(_rawProc);
    uid_t euid = proc_getsvgid(_rawProc);
    kvo_unlock(_rawProc);
    return euid;
}

- (void)setEgid:(uid_t)euid
{
    kvo_wrlock(_rawProc);
    proc_setegid(_rawProc, euid);
    kvo_unlock(_rawProc);
}

- (void)setRgid:(uid_t)ruid
{
    kvo_wrlock(_rawProc);
    proc_setrgid(_rawProc, ruid);
    kvo_unlock(_rawProc);
}

- (void)setSvgid:(uid_t)svuid
{
    kvo_wrlock(_rawProc);
    proc_setsvgid(_rawProc, svuid);
    kvo_unlock(_rawProc);
}

- (PEEntitlement)entitlement
{
    kvo_rdlock(_rawProc);
    PEEntitlement entitlement = proc_getentitlements(_rawProc);
    kvo_unlock(_rawProc);
    return entitlement;
}

- (void)setEntitlement:(PEEntitlement)entitlement
{
    kvo_wrlock(_rawProc);
    proc_setentitlements(_rawProc, entitlement);
    kvo_unlock(_rawProc);
}

@end

void pesurface_proc_radix_walker_callback(uint64_t ident,
                                          void *value,
                                          void *ctx)
{
    NSMutableArray *array = (__bridge NSMutableArray*)ctx;
    ksurface_proc_t *proc = value;
    [array addObject:[[PESurfaceProcDescriptor alloc] initWithProc:proc]];
}

@implementation PESurfaceStatic

+ (NSArray<PESurfaceProcDescriptor*>*)allProcesses
{
    proc_table_rdlock();
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:ksurface->proc_info.proc_count];
    radix_walk(&(ksurface->proc_info.tree), pesurface_proc_radix_walker_callback, (void*)(__bridge CFMutableArrayRef)array);
    proc_table_unlock();
    return array;
}

@end

#endif /* DEBUG */
