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

#include <LindChain/ProcEnvironment/Utils/dlfcn.h>
#include <Frameworks/HWHook/HWHookThreadContext.h>
#include <mach-o/dyld_images.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdlib.h>
#include <string.h>

static const char openSig[] = {0xB0, 0x00, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};

static int (*orig_dyld_open)(const char *path, int flags, mode_t mode);

static struct dyld_all_image_infos *_alt_dyld_get_all_image_infos(void)
{
    static struct dyld_all_image_infos *result;
    if(result)
    {
        return result;
    }
    struct task_dyld_info dyld_info;
    mach_vm_address_t image_infos;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t ret;
    ret = task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if(ret != KERN_SUCCESS)
    {
        return NULL;
    }
    image_infos = dyld_info.all_image_info_addr;
    result = (struct dyld_all_image_infos *)image_infos;
    return result;
}

static char *searchDyldFunction(char *base,
                                char *signature,
                                int length)
{
    char *patchAddr = NULL;
    for(int i=0; i < 0x80000; i+=4)
    {
        if(base[i] == signature[0] && memcmp(base+i, signature, length) == 0)
        {
            patchAddr = base + i;
            break;
        }
    }
    return patchAddr;
}

_Thread_local bool open_exact = false;
_Thread_local char open_fd_path[PATH_MAX] = {};
_Thread_local int open_fd = -1;
static int hook_open(const char *path,
                     int flags,
                     mode_t mode)
{
    int fd = orig_dyld_open(path, flags, mode);
    if(fd < 0 || flags & O_DIRECTORY)
    {
        return fd;
    }
    
    char buf[PATH_MAX];
    if(fcntl(fd, F_GETPATH, buf) == -1)
    {
        goto close_with_fail;
    }
    
    if(strncmp(open_fd_path, buf, PATH_MAX) == 0)
    {
        close(fd);
        fd = dup(open_fd);
        if(fd >= 0)
        {
            lseek(fd, 0, SEEK_SET);
        }
    }
    else if(open_exact)
    {
        goto close_with_fail;
    }
    
    return fd;
    
close_with_fail:
    close(fd);
    errno = ENOENT;
    return -1;
}

static HWHookThreadContextRef HWHookDlopenThreadContext(void)
{
    static HWHookThreadContextRef context = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char *dyldBase = (char *)_alt_dyld_get_all_image_infos()->dyldImageLoadAddress;
        orig_dyld_open = (void *)searchDyldFunction(dyldBase, (char*)openSig, sizeof(openSig));
        if(orig_dyld_open == NULL)
        {
            return;
        }
        
        HWHookRef openHook = HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, orig_dyld_open, hook_open);
        if(openHook == NULL)
        {
            return;
        }
        
        HWHookSetDisableContextHooksInFrame(openHook, true);
        
        context = HWHookThreadContextCreate(kCFAllocatorDefault);
        if(context == NULL)
        {
            goto release_hooks;
        }
        
        if(!HWHookThreadContextAppendHook(context, openHook))
        {
            CFRelease(context);
        release_hooks:
            CFRelease(openHook);
            return;
        }
    });
    return context;
}

void *dlopen_from_fd(int fd,
                     int mode)
{
    if(fd < 0)
    {
        errno = EBADF;
        return NULL;
    }
    
    /* backup position */
    off_t offset = lseek(fd, 0, SEEK_CUR);
    
    /* check extra flags */
    open_fd = fd;
    open_exact = mode & RTLD_EXACT_PATH;
    mode &= ~RTLD_EXACT_PATH;
    
    /* gathering exact path */
    if(fcntl(fd, F_GETPATH, open_fd_path) == -1)
    {
        errno = ENOENT;
        return NULL;
    }
    
    HWHookThreadContextRef contextRef = HWHookDlopenThreadContext();
    HWHookThreadContextEnter(contextRef);
    void *handle = dlopen(open_fd_path, mode);
    HWHookThreadContextExit(contextRef);
    
    /* now restore offset */
    lseek(fd, offset, SEEK_SET);
    return handle;
}
