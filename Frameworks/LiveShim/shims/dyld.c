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
#include <LiveShim/dyld.h>
#include <LiveShim/dyld_node_remap.h>
#include <LiveShim/cdhash.h>
#include <Frameworks/HWHook/HWHookThreadContext.h>
#include <mach-o/dyld_images.h>
#include <sys/mman.h>
#include <copyfile.h>
#include <sys/clonefile.h>
#include <copyfile.h>
#include <time.h>
#include <os/lock.h>
#include <LiveShim/ptrcache.h>

#if __has_include(<ksurface_config.h>)
#include <ksurface_config.h>
#else
#define KSURFACE_DYLD_HOOK_LOGGING_ENABLED 0
#define KSURFACE_DYLD_HARDENED_CDHASH_VERIFIER 1
#endif /* __has_include(<ksurface_config.h>) */

#if KSURFACE_DYLD_HOOK_LOGGING_ENABLED

static inline void _dyld_hook_log_timestamp(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    printf("[%6ld.%03ldms] ", ts.tv_sec % 1000, ts.tv_nsec / 1000000);
}

#define dyld_hook_log(fmt, ...) \
    do { \
        _dyld_hook_log_timestamp(); \
        printf(fmt, ##__VA_ARGS__); \
    } while (0)

#else
#define dyld_hook_log(fmt, ...) ((void)0)
#endif /* KSURFACE_DYLD_HOOK_LOGGING_ENABLED */

static int (*orig_dyld_open)(const char *path, int flags, mode_t mode);
static int (*orig_dyld_fcntl)(int fildes, int cmd, void *param);
static int (*orig_dyld_fstat64)(int fildes, struct stat *buf);
static int (*orig_dyld_stat64)(const char *path, struct stat *buf);
static int (*orig_dyld_openat)(int fd, const char *path, int flags, mode_t mode);

static int hook_fcntl(int fildes,
                      int cmd,
                      void *param)
{
    dyld_hook_log("[hook_fcntl:args] (fildes = %d, cmd: %d, param: %p)\n", fildes, cmd, param);
    int ret = orig_dyld_fcntl(fildes, cmd, param);
    if(cmd == F_GETPATH)
    {
        dyld_hook_log("[hook_fcntl:orig_return] (ret = %d, path: %s)\n", ret, (char*)param);
        dyld_hook_log("[hook_fcntl] [library validation bypass] fooling da cutie dyld >:3\n");
        if(inode_bank_get_path(inode_for_fd(fildes), param, MAXPATHLEN))
        {
            dyld_hook_log("[hook_fcntl] [library validation bypass] redirecting (fd = %d) to (path = %s)\n", fildes, (char*)param);
        }
    }
#if KSURFACE_DYLD_HOOK_LOGGING_ENABLED
    else
    {
        dyld_hook_log("[hook_fcntl:orig_return] (ret = %d)\n", ret);
    }
#endif /* KSURFACE_DYLD_HOOK_LOGGING_ENABLED */
    
#if KSURFACE_DYLD_HOOK_LOGGING_ENABLED
    if(cmd == F_GETPATH)
    {
        dyld_hook_log("[hook_fcntl:return] (ret = %d, path: %s)\n", ret, (char*)param);
    }
    else
    {
        dyld_hook_log("[hook_fcntl:return] (ret = %d)\n", ret);
    }
#endif /* KSURFACE_DYLD_HOOK_LOGGING_ENABLED */
    
    return ret;
}

static const char *mmap_sandbox_map_exec_allowed_path = NULL;

static _Thread_local bool cdhash_verified = false;
static _Thread_local bool cdhash_must_valid;
static _Thread_local bool open_hardlock;
static _Thread_local const char *cdhash_data_container_match;
static _Thread_local dlopen_cdhash_verifier_failed_callback_t cdhash_verifier_failed_callback;
static int path_validation_bypass_open(int fd,
                                       int flags)
{
    char actualPath[PATH_MAX];
    if(fcntl(fd, F_GETPATH, actualPath) != -1)
    {
        dyld_hook_log("[path_validation_bypass_open:path] %s\n", actualPath);
        
        const char prefix[] = "/private/var/mobile/Containers/Data";
        if(strncmp(actualPath, prefix, sizeof(prefix) - 1) == 0)
        {
            /* need a new path */
            char newTmpPath[PATH_MAX];
            snprintf(newTmpPath, sizeof(newTmpPath),  "%s/tmp/%d/0x%llx.dylib", mmap_sandbox_map_exec_allowed_path, getpid(), inode_for_fd(fd));    /* use tmp so iOS clears it automatically in LP home */
            
            dyld_hook_log("[path_validation_bypass_open] [library validation bypass] new path: %s\n", newTmpPath);
            dyld_hook_log("[path_validation_bypass_open] [library validation bypass] dyld needs to think that %s is located at %s\n", newTmpPath, actualPath);
            
            int copyfd = open(newTmpPath, flags);
            if(copyfd >= 0)
            {
                close(fd);
                dup2(copyfd, fd);
                close(copyfd);
                dyld_hook_log("[path_validation_bypass_open] [library validation bypass] path already has APFS CoW copy\n");
                goto lv_bypass_setup_done;
            }
            
            dyld_hook_log("[path_validation_bypass_open] [library validation bypass] APFS CoW copy needed\n");
            if(fclonefileat(fd, AT_FDCWD, newTmpPath, 0) == 0)
            {
                dyld_hook_log("[path_validation_bypass_open] [library validation bypass] APFS CoW copy succeeded\n");
                copyfd = open(newTmpPath, flags);
                if(copyfd < 0)
                {
                    dyld_hook_log("[path_validation_bypass_open] [library validation bypass] couldn't open file descriptor\n");
                    goto lv_bypass_setup_done;
                }
            }
            else
            {
             
                dyld_hook_log("[path_validation_bypass_open] [library validation bypass] APFS CoW copy failed(errno: %s), falling back to copyfile\n", strerror(errno));
                copyfd = open(newTmpPath, O_RDWR | O_CREAT | O_TRUNC, 0777);
                if(copyfd < 0)
                {
                    dyld_hook_log("[path_validation_bypass_open] [library validation bypass] couldn't open file descriptor\n");
                    goto lv_bypass_setup_done;
                }
            
                int ret = fcopyfile(fd, copyfd, NULL, COPYFILE_DATA);
                close(copyfd);
                if(ret != 0)
                {
                    dyld_hook_log("[path_validation_bypass_open] [library validation bypass] fcopyfile failed: %s\n", strerror(errno));
                    goto lv_bypass_setup_done;
                }
                dyld_hook_log("[path_validation_bypass_open] [library validation bypass] fcopyfile succeeded\n");
                
                copyfd = open(newTmpPath, flags);
                if(copyfd < 0)
                {
                    dyld_hook_log("[path_validation_bypass_open] [library validation bypass] couldn't open file descriptor\n");
                    goto lv_bypass_setup_done;
                }
            }
            
            /* this to orient or selfs */
            ino_t inode = inode_for_fd(copyfd);
            dyld_hook_log("[path_validation_bypass_open] [library validation bypass] setting up inode redirection for inode: 0x%llx\n", inode);
            inode_bank_put(inode, newTmpPath);
            inode_bank_set_redirect(inode, actualPath);
            
            close(fd);
            dup2(copyfd, fd);
            close(copyfd);
            
        lv_bypass_setup_done:
            
            if(cdhash_must_valid && !cdhash_verified)
            {
                /* no matter what this is not reentrant */
                cdhash_must_valid = false;
                cdhash_verified = false;
                
                lseek(fd, 0, SEEK_SET);
                /* need to get cdhash and then reset it's position */
                
                char *cdhash = cdhash_of_fd(fd);
                dyld_hook_log("[path_validation_bypass_open] [nyxian cdhash verifier] (foundCdhash = %p, cdhash = %p)\n", cdhash, cdhash_data_container_match);
                
                /* match */
                if(cdhash == NULL ||
                   cdhash_data_container_match == NULL ||
                   memcmp(cdhash_data_container_match, cdhash, USER_FSIGNATURES_CDHASH_LEN) != 0)
                {
                    cdhash_verified = false;
                    dyld_hook_log("[path_validation_bypass_open] [nyxian cdhash verifier] cdhash does not match, calling callback if givven\n");
                    
#if KSURFACE_DYLD_HARDENED_CDHASH_VERIFIER
                    open_hardlock = true;
#else
                    if(cdhash_verifier_failed_callback != NULL)
                    {
                        cdhash_verifier_failed_callback(fd, &open_hardlock);
                    }
#endif /* !KSURFACE_DYLD_HARDENED_CDHASH_VERIFIER */
                    
                    /* callback can set open hardlock */
                    if(open_hardlock)
                    {
                        dyld_hook_log("[path_validation_bypass_open] [error: hard locked]\n");
                        errno = EACCES;
                        close(fd);
                        fd = -1;
                    }
                }
                else
                {
                    dyld_hook_log("[path_validation_bypass_open] [nyxian cdhash verifier] cdhash valid!\n");
                    cdhash_verified = true;
                    lseek(fd, 0, SEEK_SET);
                }
                
                /* reset position */
                free(cdhash);   /* free on macOS/iOS is NULL safe */
            }
        }
    }
    return fd;
}

static int hook_open(const char *path,
                     int flags,
                     mode_t mode)
{
    dyld_hook_log("[hook_open:args] (path = %s, flags = %d, mode = %d)\n", path, flags, mode);
    if(open_hardlock)
    {
        dyld_hook_log("[hook_open:args] [error: hard locked]\n");
        errno = EACCES;
        return -1;
    }
    
    int fd = orig_dyld_open(path, flags, mode);
    if(fd < 0 || flags & O_DIRECTORY)
    {
        goto just_return;
    }
    
    fd = path_validation_bypass_open(fd, flags);
    
just_return:
    dyld_hook_log("[hook_open:return] (fd = %d)\n", fd);
    return fd;
}

static int hook_openat(int dirfd,
                       const char *path,
                       int flags,
                       mode_t mode)
{
    dyld_hook_log("[hook_openat:args] (dirfd = %d, path = %s, flags = %d, mode = %d)\n", dirfd, path, flags, mode);
    if(open_hardlock)
    {
        dyld_hook_log("[hook_openat:args] [error: hard locked]\n");
        errno = EACCES;
        return -1;
    }
    
    int fd = orig_dyld_openat(dirfd, path, flags, mode);
    if(fd < 0 || flags & O_DIRECTORY)
    {
        goto just_return;
    }
    
    fd = path_validation_bypass_open(fd, flags);
    
just_return:
    dyld_hook_log("[hook_openat:return] (fd = %d)\n", fd);
    return fd;
}

static const time_t fake_time = 1700000000;

static int hook_fstat64(int fd,
                        struct stat *buf)
{
    dyld_hook_log("[hook_fstat64:args] (fd = %d, buf = %p)\n", fd, buf);
    int ret = orig_dyld_fstat64(fd, buf);
    if(ret == 0)
    {
        char canon[PATH_MAX];
        if(inode_bank_get_path(buf->st_ino, canon, sizeof(canon)) || orig_dyld_fcntl(fd, F_GETPATH, canon) != -1)
        {
            ino_t fake_ino = fake_inode_for_path(canon);
            dyld_hook_log("[hook_fstat64] [library validation bypass] changing inode:\n");
            dyld_hook_log("    st_ino: %llu -> %llu\n", buf->st_ino, fake_ino);
            buf->st_ino = fake_ino;
        }
        
        dyld_hook_log("[hook_fstat64] [library validation bypass] changing times:\n");
        dyld_hook_log("    st_mtimespec: %lu -> %lu\n", buf->st_mtimespec.tv_sec, fake_time);
        buf->st_mtimespec.tv_sec = fake_time;
        buf->st_mtimespec.tv_nsec = 0;
        dyld_hook_log("    st_ctimespec: %lu -> %lu\n", buf->st_ctimespec.tv_sec, fake_time);
        buf->st_ctimespec.tv_sec = fake_time;
        buf->st_ctimespec.tv_nsec = 0;
        dyld_hook_log("    st_birthtimespec: %lu -> %lu\n", buf->st_birthtimespec.tv_sec, fake_time);
        buf->st_birthtimespec.tv_sec = fake_time;
        buf->st_birthtimespec.tv_nsec = 0;
        
        dyld_hook_log("[hook_fstat64] [library validation bypass] zeroing out dev device:\n");
        dyld_hook_log("    st_dev: %d -> %d\n", buf->st_dev, 0);
    }
    dyld_hook_log("[hook_fstat64:return] (ret = %d)\n", ret);
    return ret;
}

static int hook_stat64(const char *path,
                       struct stat *buf)
{
    dyld_hook_log("[hook_stat64:args] (path = %s, buf = %p)\n", path, buf);
    int ret = orig_dyld_stat64(path, buf);
    if(ret == 0)
    {
        ino_t fake_ino = fake_inode_for_path(path);
        dyld_hook_log("[hook_stat64] [library validation bypass] changing inode:\n");
        dyld_hook_log("    st_ino: %llu -> %llu\n", buf->st_ino, fake_ino);
        buf->st_ino = fake_ino;   /* canonicalizes internally */
        
        dyld_hook_log("[hook_stat64] [library validation bypass] changing times:\n");
        dyld_hook_log("    st_mtimespec: %lu -> %lu\n", buf->st_mtimespec.tv_sec, fake_time);
        buf->st_mtimespec.tv_sec = fake_time;
        buf->st_mtimespec.tv_nsec = 0;
        dyld_hook_log("    st_ctimespec: %lu -> %lu\n", buf->st_ctimespec.tv_sec, fake_time);
        buf->st_ctimespec.tv_sec = fake_time;
        buf->st_ctimespec.tv_nsec = 0;
        dyld_hook_log("    st_birthtimespec: %lu -> %lu\n", buf->st_birthtimespec.tv_sec, fake_time);
        buf->st_birthtimespec.tv_sec = fake_time;
        buf->st_birthtimespec.tv_nsec = 0;
        
        dyld_hook_log("[hook_stat64] [library validation bypass] zeroing out dev device:\n");
        dyld_hook_log("    st_dev: %d -> %d\n", buf->st_dev, 0);
    }
    dyld_hook_log("[hook_stat64:return] (ret = %d)\n", ret);
    return ret;
}

static HWHookThreadContextRef HWHookDlopenThreadContext(void)
{
    if(!load_ptrcache())
    {
        return NULL;
    }
    
    static HWHookThreadContextRef context = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        orig_dyld_fcntl = (void*)ptrcache[kDyldPtrFcntl];
        orig_dyld_open = (void*)ptrcache[kDyldPtrOpen];
        orig_dyld_fstat64 = (void*)ptrcache[kDyldPtrFstat64];
        orig_dyld_stat64 = (void*)ptrcache[kDyldPtrStat64];
        orig_dyld_openat = (void*)ptrcache[kDyldPtrOpenat];
        if(orig_dyld_fcntl == NULL || orig_dyld_open == NULL || orig_dyld_fstat64 == NULL || orig_dyld_stat64 == NULL || orig_dyld_openat == NULL)
        {
            return;
        }
        
        HWHookRef fcntlHook = HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, orig_dyld_fcntl, hook_fcntl);
        if(fcntlHook == NULL)
        {
            return;
        }
        
        HWHookRef openHook = HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, orig_dyld_open, hook_open);
        if(openHook == NULL)
        {
            CFRelease(fcntlHook);
            return;
        }
        
        HWHookRef fstat64Hook = HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, orig_dyld_fstat64, hook_fstat64);
        if(fstat64Hook == NULL)
        {
            CFRelease(fcntlHook);
            CFRelease(openHook);
            return;
        }
        
        HWHookRef stat64Hook = HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, orig_dyld_stat64, hook_stat64);
        if(fstat64Hook == NULL)
        {
            CFRelease(fcntlHook);
            CFRelease(openHook);
            CFRelease(fstat64Hook);
            return;
        }
        
        HWHookRef openatHook = HWHookCreateWithPointerToSymbol(kCFAllocatorDefault, orig_dyld_openat, hook_openat);
        if(openatHook == NULL)
        {
            CFRelease(fcntlHook);
            CFRelease(openHook);
            CFRelease(fstat64Hook);
            CFRelease(stat64Hook);
            return;
        }
        
        HWHookSetDisableContextHooksInFrame(fcntlHook, true);
        HWHookSetDisableContextHooksInFrame(openHook, true);
        HWHookSetDisableContextHooksInFrame(fstat64Hook, true);
        HWHookSetDisableContextHooksInFrame(stat64Hook, true);
        HWHookSetDisableContextHooksInFrame(openatHook, true);
        
        context = HWHookThreadContextCreate(kCFAllocatorDefault);
        if(context == NULL)
        {
            goto release_hooks;
        }
        
        if(!HWHookThreadContextAppendHook(context, fcntlHook) ||
           !HWHookThreadContextAppendHook(context, openHook) ||
           !HWHookThreadContextAppendHook(context, fstat64Hook) ||
           !HWHookThreadContextAppendHook(context, stat64Hook) ||
           !HWHookThreadContextAppendHook(context, openatHook))
        {
            CFRelease(context);
        release_hooks:
            CFRelease(fcntlHook);
            CFRelease(openHook);
            CFRelease(fstat64Hook);
            CFRelease(stat64Hook);
            CFRelease(openatHook);
            return;
        }
    });
    return context;
}

void *hook_dlopen(const char *path, int mode);

INTERPOSE(hook_dlopen, dlopen);

void *hook_dlopen(const char *path, int mode)
{
    inode_bank_init();
    
    char newTmpPath[PATH_MAX];
    snprintf(newTmpPath, sizeof(newTmpPath), "%s/tmp", mmap_sandbox_map_exec_allowed_path);
    mkdir(newTmpPath, 0777);
    snprintf(newTmpPath, sizeof(newTmpPath), "%s/tmp/%d", mmap_sandbox_map_exec_allowed_path, getpid());
    mkdir(newTmpPath, 0777);
    
    void *(*darwin_dlopen)(const char *path, int mode) = _interpose_dlopen.replacee;
    dyld_hook_log("[hook_dlopen] %s\n", path);
    
    open_hardlock = false;
    HWHookThreadContextRef context = HWHookDlopenThreadContext();
    HWHookThreadContextEnter(context);  /* is nil safe, so it shall work anyways */
    void *ret = darwin_dlopen(path, mode);
    HWHookThreadContextExit(context);
    
    inode_bank_unlink_all(newTmpPath);
    rmdir(newTmpPath);
    return ret;
}

void *dlopen_cdhash_verified(const char *path,
                             int flags,
                             const char *cdhash,
                             dlopen_cdhash_verifier_failed_callback_t callback)
{
    cdhash_verified = false;
    cdhash_must_valid = true;
    cdhash_data_container_match = cdhash;
    cdhash_verifier_failed_callback = callback;
    void *ret = hook_dlopen(path, flags);
    cdhash_verifier_failed_callback = NULL;
    cdhash_data_container_match = NULL;
    cdhash_must_valid = false;
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

const char *dyld_get_mmap_sandbox_map_exec_allowed_path(void)
{
    return mmap_sandbox_map_exec_allowed_path;
}
