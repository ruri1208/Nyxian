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

#include <LindChain/ProcEnvironment/Surface/fs/mount.h>
#include <string.h>

kern_return_t ksurface_fs_mount(FSMountPermissionFlags permissions,
                                const char *mount_dir,
                                const char *bind_dir)
{
    if(mount_dir == NULL || mount_dir[0] != '/')
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    if(permissions != kFSMountPermissionNone &&
       permissions != kFSMountPermissionRead &&
       permissions != kFSMountPermissionReadWrite)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    if(bind_dir != NULL && bind_dir[0] != '/')
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    /* if bind_dir is givven it becomes a directory */
    FSNodeType type = (bind_dir != NULL) ? kFSNodeTypeSymbolicLink : kFSNodeTypeDirectory;
    
    /* preparing node */
    FSPreserverNode node = { .type = type, 0 };
    strlcpy(node.name, mount_dir, PATH_MAX);
    if(bind_dir != NULL)
    {
        strlcpy(node.target, bind_dir, PATH_MAX);
    }
    
    /* and register it */
    kern_return_t kr = ksurface_fs_preserver_add_node(node);
    if(kr != KERN_SUCCESS)
    {
        return kr;
    }
    
    return ksurface_fs_registry_add(permissions, type, mount_dir, bind_dir);
}
