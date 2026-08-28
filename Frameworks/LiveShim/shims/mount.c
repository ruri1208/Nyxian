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

#include <sys/param.h>
#include <sys/ucred.h>
#include <sys/mount.h>
#include <LiveShim/shim.h>

static void fill_fake(struct statfs *f)
{
    memset(f, 0, sizeof(*f));
    f->f_bsize = 4096;
    f->f_iosize = 4096;
    f->f_blocks = 1000000;
    f->f_bfree = 500000;
    f->f_bavail = 500000;
    f->f_files = 100000;
    f->f_ffree = 90000;
    f->f_fsid.val[0] = 0x1337;
    f->f_fsid.val[1] = 0xbeef;
    f->f_owner = 0;
    f->f_flags = MNT_LOCAL | MNT_ROOTFS;
    strlcpy(f->f_fstypename, "apfs", sizeof(f->f_fstypename));
    strlcpy(f->f_mntonname, getenv("NXROOT"), sizeof(f->f_mntonname));
    strlcpy(f->f_mntfromname, "nyxian", sizeof(f->f_mntfromname));
}


static int ksurface_getmntinfo(struct statfs **buf, int m);
static int ksurface_getmntinfo_r_np(struct statfs **buf, int m);

INTERPOSE(ksurface_getmntinfo, getmntinfo);
INTERPOSE(ksurface_getmntinfo_r_np, getmntinfo_r_np);

static int ksurface_getmntinfo(struct statfs **mntbufp,
                               int flags)
{
    int (*orig)(struct statfs **, int) = (int (*)(struct statfs **, int))_interpose_getmntinfo.replacee;
    
    struct statfs *buf;
    int n = orig(&buf, flags);
    if(n <= 0)
    {
        *mntbufp = buf;
        return n;
    }
    
    fill_fake(&buf[n]);
    *mntbufp = buf;
    return n + 1;
}

static int ksurface_getmntinfo_r_np(struct statfs **mntbufp,
                                    int flags)
{
    int (*orig)(struct statfs **, int) = (int (*)(struct statfs **, int))_interpose_getmntinfo_r_np.replacee;
    
    struct statfs *buf;
    int n = orig(&buf, flags);
    if(n <= 0)
    {
        *mntbufp = buf;
        return n;
    }
    
    fill_fake(&buf[n]);
    *mntbufp = buf;
    return n + 1;
}
