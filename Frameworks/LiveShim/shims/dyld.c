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
#include <Frameworks/HWHook/HWHookThreadContext.h>
#include <mach-o/dyld_images.h>
#include <sys/mman.h>

/* skidded from LiveContainer */
static const char mmapSig[] = {0xB0, 0x18, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
static const char fcntlSig[] = {0x90, 0x0B, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};

static int (*orig_dyld_fcntl)(int fildes, int cmd, void *param);
static void *(*orig_dyld_mmap)(void *addr, size_t len, int prot, int flags, int fd, off_t offset);

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
    printf("[hook_fcntl:args] (fildes = %d, cmd: %d, param: %p)\n", fildes, cmd, param);
    int ret = orig_dyld_fcntl(fildes, cmd, param);
    char path[PATH_MAX];
    if(orig_dyld_fcntl(fildes, F_GETPATH, path) != -1)
    {
        printf("[hook_fcntl:return] (ret = %d, path: %s)\n", ret, path);
    }
    else
    {
        printf("[hook_fcntl:return] (ret = %d)\n", ret);
    }
    
    return ret;
}

static const char *mmap_sandbox_map_exec_allowed_path = NULL;
static void *hook_mmap(void *addr,
                       size_t len,
                       int prot,
                       int flags,
                       int fd,
                       off_t offset)
{
    printf("[hook_mmap:args] (addr = %p, len = %zu, prot = %d, flags = %d, fd = %d, offset = %lld)\n", addr, len, prot, flags, fd, offset);
    void *ret = orig_dyld_mmap(addr, len, prot, flags, fd, offset);
    if(ret != MAP_FAILED || !(prot & PROT_EXEC) || fd < 0 || mmap_sandbox_map_exec_allowed_path == NULL)
    {
        goto log_return;
    }
    
    char filePath[PATH_MAX];
    if(fcntl(fd, F_GETPATH, filePath) != 0)
    {
        goto log_return;
    }
    char newTmpPath[PATH_MAX];
    /* very smart duy, ima be fair using ASLR as a UUID generator is finally something good you've done */
    sprintf(newTmpPath, "%s/Documents/%p.dylib", mmap_sandbox_map_exec_allowed_path, addr);
    rename(filePath, newTmpPath);
    ret = orig_dyld_mmap(addr, len, prot, flags, fd, offset);
    rename(newTmpPath, filePath);
    
    /* return logging */
log_return:
    {
        char path[PATH_MAX];
        if(orig_dyld_fcntl(fd, F_GETPATH, path) != -1)
        {
            printf("[hook_mmap:return] (ret = %p, path: %s)\n", ret, path);
        }
        else
        {
            printf("[hook_mmap:return] (ret = %p)\n", ret);
        }
    }
    return ret;
}

static HWHookThreadContextRef HWHookDlopenThreadContext(void)
{
    static HWHookThreadContextRef context = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char *dyldBase = (char *)_alt_dyld_get_all_image_infos()->dyldImageLoadAddress;
        orig_dyld_fcntl = (void *)searchDyldFunction(dyldBase, (char*)fcntlSig, sizeof(fcntlSig));
        orig_dyld_mmap = (void *)searchDyldFunction(dyldBase, (char*)mmapSig, sizeof(mmapSig));
        if(orig_dyld_mmap == NULL || orig_dyld_fcntl == NULL)
        {
            return;
        }
        
        HWHookRef fcntlHook = HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, orig_dyld_fcntl, hook_fcntl);
        if(fcntlHook == NULL)
        {
            return;
        }
        
        HWHookRef mmapHook = HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, orig_dyld_mmap, hook_mmap);
        if(mmapHook == NULL)
        {
            CFRelease(mmapHook);
            return;
        }
        
        HWHookSetDisableContextHooksInFrame(fcntlHook, true);
        HWHookSetDisableContextHooksInFrame(mmapHook, true);
        
        context = HWHookThreadContextCreate(kCFAllocatorDefault);
        if(context == NULL)
        {
            goto release_hooks;
        }
        
        if(!HWHookThreadContextAppendHook(context, fcntlHook) ||
           !HWHookThreadContextAppendHook(context, mmapHook))
        {
            CFRelease(context);
        release_hooks:
            CFRelease(fcntlHook);
            CFRelease(mmapHook);
            return;
        }
    });
    return context;
}

void *hook_dlopen(const char *path, int mode);

INTERPOSE(hook_dlopen, dlopen);

void *hook_dlopen(const char *path, int mode)
{
    void *(*darwin_dlopen)(const char *path, int mode) = _interpose_dlopen.replacee;
    printf("[hook_dlopen] %s\n", path);
    
    HWHookThreadContextRef context = HWHookDlopenThreadContext();
    HWHookThreadContextEnter(context);  /* is nil safe, so it shall work anyways */
    void *ret = darwin_dlopen(path, mode);
    HWHookThreadContextExit(context);
    return ret;
}

__attribute__((constructor))
void LiveShimDlopenHookInit(void)
{
    const char *home = getenv("HOME");
    if(home == NULL)
    {
        return;
    }
    
    char *home_copy = strndup(home, MAXPATHLEN);
    if(home_copy == NULL)
    {
        return;
    }
    
    mmap_sandbox_map_exec_allowed_path = home_copy;
}
