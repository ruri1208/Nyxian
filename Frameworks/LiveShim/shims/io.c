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
#include <Broadpatch/Broadpatch.h>
#include <sys/ioccom.h>
#include <sys/stat.h>

LIBKERN_PATCH(int, access, (const char *path,
                            int mode),
{
    if(mode & X_OK)
    {
        struct stat sb;
        if(stat(path, &sb) == 0)
        {
            if(sb.st_mode & S_IXUSR)
            {
                if(mode == X_OK)
                {
                    return 0;
                }
                return LIBKERN_ORIG(access)(path, mode & ~X_OK);
            }
        }
    }
    return LIBKERN_ORIG(access)(path, mode);
});


LIBKERN_PATCH(int, faccessat, (int dirfd,
                               const char *path,
                               int mode,
                               int flags),
{
    if(mode & X_OK)
    {
        struct stat sb;
        int stat_flags = (flags & AT_SYMLINK_NOFOLLOW) ? AT_SYMLINK_NOFOLLOW : 0;
        if(fstatat(dirfd, path, &sb, stat_flags) == 0)
        {
            if(sb.st_mode & S_IXUSR)
            {
                if(mode == X_OK)
                {
                    return 0;
                }
                return LIBKERN_ORIG(faccessat)(dirfd, path, mode & ~X_OK, flags);
            }
        }
    }
    return LIBKERN_ORIG(faccessat)(dirfd, path, mode, flags);
});

__attribute__((constructor))
static void InstallPatches(void)
{
    LIBKERN_INSTALL_PATCH(access);
    LIBKERN_INSTALL_PATCH(faccessat);
}
