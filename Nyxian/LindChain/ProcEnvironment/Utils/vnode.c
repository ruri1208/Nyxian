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

#include <LindChain/ProcEnvironment/Utils/vnode.h>
#include <sys/clonefile.h>
#include <copyfile.h>
#include <unistd.h>
#include <fcntl.h>

bool vnode_refresh_at_path(const char* path)
{
    int fd = open(path, O_RDWR);
    if(fd < 0)
    {
        return false;
    }
    
    /* destroys existing VFS node */
    if(unlink(path) != 0)
    {
        close(fd);
        return false;
    }
    
    /* creates new node at zero cost */
    if(fclonefileat(fd, AT_FDCWD, path, 0) == 0)
    {
        /* yayyy =3 */
        close(fd);
        return true;
    }
    
    /* fallback is using copy file */
    int copyfd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0777);
    if(copyfd < 0)
    {
        /* something went terribly wrong */
        close(fd);
        return false;
    }
    
    /* more expensive, but more efficient than nothing */
    if(fcopyfile(fd, copyfd, NULL, COPYFILE_DATA) == 0)
    {
        /* atleast this worked :3 */
        close(copyfd);
        close(fd);
        return true;
    }
    
    close(copyfd);
    close(fd);
    return false;
}
