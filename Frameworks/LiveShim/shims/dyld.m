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

#import <LiveShim/shim.h>
#import <Frameworks/HWHook/HWHKHookThreadContext.h>
#import <mach-o/dyld_images.h>

/* skidded from LiveContainer */
extern void* __mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset);
extern int __fcntl(int fildes, int cmd, void* param);

static const char mmapSig[] = {0xB0, 0x18, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
static const char fcntlSig[] = {0x90, 0x0B, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
static const char syscallSig[] = {0x01, 0x10, 0x00, 0xD4};
static int (*orig_dyld_fcntl)(int fildes, int cmd, void *param);
static int (*orig_dyld_mmap)(int fildes, int cmd, void *param);

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
/* skidded end */

static int hook_fcntl(int fildes,
                      int cmd,
                      void *param)
{
    HWHKHookThreadContext *context = [HWHKHookThreadContext context];
    [context disableHooks];
    
    printf("[hook_fcntl:args] (fildes = %d, cmd: %d, param: %p)\n", fildes, cmd, param);
    int ret = __fcntl(fildes, cmd, param);
    char path[PATH_MAX];
    if(__fcntl(fildes, F_GETPATH, path) != -1)
    {
        printf("[hook_fcntl:return] (ret = %d, path: %s)\n", ret, path);
    }
    else
    {
        printf("[hook_fcntl:return] (ret = %d)\n", ret);
    }
    
    [context enableHooks];
    return ret;
}

static void *hook_mmap(void *addr,
                       size_t len,
                       int prot,
                       int flags,
                       int fd,
                       off_t offset)
{
    HWHKHookThreadContext *context = [HWHKHookThreadContext context];
    [context disableHooks];
    
    printf("[hook_mmap:args] (addr = %p, len = %zu, prot = %d, flags = %d, fd = %d, offset = %lld)\n", addr, len, prot, flags, fd, offset);
    void *ret = __mmap(addr, len, prot, flags, fd, offset);
    char path[PATH_MAX];
    if(__fcntl(fd, F_GETPATH, path) != -1)
    {
        printf("[hook_mmap:return] (ret = %p, path: %s)\n", ret, path);
    }
    else
    {
        printf("[hook_mmap:return] (ret = %p)\n", ret);
    }
    
    [context enableHooks];
    return ret;
}

static HWHKHookThreadContext *HWHKHookDlopenThreadContext(void)
{
    static HWHKHookThreadContext *context = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char *dyldBase = (char *)_alt_dyld_get_all_image_infos()->dyldImageLoadAddress;
        orig_dyld_fcntl = (void *)searchDyldFunction(dyldBase, (char*)fcntlSig, sizeof(fcntlSig));
        orig_dyld_mmap = (void *)searchDyldFunction(dyldBase, (char*)mmapSig, sizeof(mmapSig));
        
        context = [HWHKHookThreadContext context];
        [context addHook:[HWHKHook hookWithPointerToSymbol:orig_dyld_fcntl withReplacementSymbol:hook_fcntl]];
        [context addHook:[HWHKHook hookWithPointerToSymbol:orig_dyld_mmap withReplacementSymbol:hook_mmap]];
    });
    return context;
}

void *hook_dlopen(const char *path, int mode);

INTERPOSE(hook_dlopen, dlopen);

void *hook_dlopen(const char *path, int mode)
{
    void *(*darwin_dlopen)(const char *path, int mode) = _interpose_dlopen.replacee;
    printf("[hook_dlopen] %s\n", path);
    
    HWHKHookThreadContext *context = HWHKHookDlopenThreadContext();
    [context enter];
    void *ret = darwin_dlopen(path, mode);
    [context exit];
    return ret;
}
