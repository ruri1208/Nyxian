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
#include <sys/stat.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <limits.h>

static kern_return_t __ksurface_fs_mount_clear_directory(const char *dir_path)
{
    DIR *dir = opendir(dir_path);
    if(!dir)
    {
        return KERN_NOT_FOUND;
    }
    
    struct dirent *entry;
    char path[PATH_MAX];
    
    while((entry = readdir(dir)) != NULL)
    {
        if(strcmp(entry->d_name, ".") == 0 ||
           strcmp(entry->d_name, "..") == 0)
        {
            continue;
        }
        
        snprintf(path, sizeof(path), "%s/%s", dir_path, entry->d_name);
        
        struct stat statbuf;
        if(lstat(path, &statbuf) == 0)
        {
            if(S_ISDIR(statbuf.st_mode))
            {
                __ksurface_fs_mount_clear_directory(path);
                rmdir(path);
            }
            else
            {
                unlink(path);
            }
        }
    }
    
    closedir(dir);
    return KERN_SUCCESS;
}

kern_return_t ksurface_fs_mount(FSMountAttr attributes,
                                const char *mount_dir,
                                const char *bind_dir,
                                ...)
{
    if(mount_dir == NULL || mount_dir[0] != '/')
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    if(bind_dir != NULL && bind_dir[0] != '/')
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    /* check for yet unsupported flags */
    if(attributes & (kFSMountAttrReadPlatform | kFSMountAttrWritePlatform | kFSMountAttrReadEntitlement | kFSMountAttrWriteEntitlement))
    {
        return KERN_NOT_SUPPORTED;
    }
    
    /* manage permissions */
    FSMountPermissionFlags permissions = kFSMountPermissionNone;
    if((attributes & kFSMountAttrWrite) && !(attributes & kFSMountAttrRead))
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    if(attributes & kFSMountAttrWrite)
    {
        permissions = kFSMountPermissionReadWrite;
    }
    else if(attributes & kFSMountAttrRead)
    {
        permissions = kFSMountPermissionRead;
    }
    else
    {
        permissions = kFSMountPermissionNone;
    }
    
    /* if bind_dir is givven it becomes a directory */
    FSNodeType type = (bind_dir != NULL) ? kFSNodeTypeSymbolicLink : kFSNodeTypeDirectory;
    
    /* shall this be cleared? */
    if(attributes & kFSMountAttrClear)
    {
        switch(type)
        {
            case kFSNodeTypeDirectory:
                __ksurface_fs_mount_clear_directory(mount_dir);
                break;
            case kFSNodeTypeSymbolicLink:
                __ksurface_fs_mount_clear_directory(bind_dir);
                break;
            default:
                return KERN_FAILURE;
        }
    }
    
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
    
    return ksurface_fs_sandbox_registry_add(permissions, type, mount_dir, bind_dir);
}
