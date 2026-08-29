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

#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <stdbool.h>
#include <limits.h>
#include <LindChain/ProcEnvironment/Surface/fs/preserver.h>
#include <LindChain/ProcEnvironment/Utils/klog.h>

#define PRES_MAX_NODES    1024
#define PRES_DEBOUNCE_NS  (20ull * NSEC_PER_MSEC)
#define PRES_SWEEP_SECS   30
#define PRES_DIR_MODE     0755

typedef struct {
    FSNodeType type;
    char path[PATH_MAX];
    char target[PATH_MAX];
    char dir[PATH_MAX];
    uint16_t depth;
    uint32_t watch;
    bool intact;
} pres_node_t;

typedef struct {
    char dir[PATH_MAX];
    int fd;
    dispatch_source_t src;
    bool sweep_pending;
    bool rearming;
} pres_watch_t;

static pres_node_t g_node[PRES_MAX_NODES];
static uint32_t g_node_count;
static uint32_t g_order[PRES_MAX_NODES];

static pres_watch_t g_watch[PRES_MAX_NODES];
static uint32_t g_watch_count;

static dispatch_queue_t g_q;
static dispatch_source_t g_timer;
static bool g_started;

static dispatch_queue_t pres_queue(void);
static kern_return_t repair_symlink(const pres_node_t *n);

static int node_index_for_path(const char *p)
{
    for(uint32_t i = 0; i < g_node_count; i++)
    {
        if(strcmp(g_node[i].path, p) == 0)
        {
            return (int)i;
        }
    }
    return -1;
}

static uint16_t path_depth(const char *p)
{
    uint16_t d = 0;
    for(const char *c = p; *c; c++)
    {
        if(*c == '/')
        {
            d++;
        }
    }
    return d;
}

static void path_parent(const char *p,
                        char *out,
                        size_t cap)
{
    const char *slash = strrchr(p, '/');
    if(!slash || slash == p)
    {
        strlcpy(out, "/", cap);
        return;
    }
    size_t n = (size_t)(slash - p);
    if(n >= cap)
    {
        n = cap - 1;
    }
    memcpy(out, p, n);
    out[n] = '\0';
}

static int mkdir_component(const char *p)
{
    struct stat st;
    
    if(lstat(p, &st) == 0)
    {
        if(S_ISDIR(st.st_mode))
        {
            return 0;
        }
        if(S_ISLNK(st.st_mode) && stat(p, &st) == 0 && S_ISDIR(st.st_mode))
        {
            return 0;
        }
    }
    
    int ni = node_index_for_path(p);
    if(ni >= 0 && g_node[ni].type == kFSNodeTypeSymbolicLink)
    {
        return repair_symlink(&g_node[ni]) == KERN_SUCCESS ? 0 : -1;
    }
    
    if(mkdir(p, PRES_DIR_MODE) == 0)
    {
        return 0;
    }
    if(errno == EEXIST)
    {
        return 0;
    }
    
    if(lstat(p, &st) == 0 && S_ISDIR(st.st_mode))
    {
        return 0;
    }
    
    return -1;
}

static int mkdir_chain(const char *path)
{
    char buf[PATH_MAX];
    strlcpy(buf, path, sizeof buf);
    
    for(char *c = buf + 1; *c; c++)
    {
        if(*c != '/')
        {
            continue;
        }
        *c = '\0';
        if(mkdir_component(buf) != 0)
        {
            klog_log("ksurface:fs:preserver", "mkdir %s: %s", buf, strerror(errno));
            return -1;
        }
        *c = '/';
    }
    if(mkdir_component(buf) != 0)
    {
        klog_log("ksurface:fs:preserver", "mkdir %s: %s", buf, strerror(errno));
        return -1;
    }
    return 0;
}

static bool node_intact(const pres_node_t *n)
{
    struct stat st;
    if(lstat(n->path, &st) != 0)
    {
        return false;
    }
    
    if(n->type == kFSNodeTypeSymbolicLink)
    {
        if(!S_ISLNK(st.st_mode))
        {
            return false;
        }
        char buf[PATH_MAX];
        ssize_t k = readlink(n->path, buf, sizeof buf - 1);
        if(k < 0)
        {
            return false;
        }
        buf[k] = '\0';
        return strcmp(buf, n->target) == 0;
    }
    return S_ISDIR(st.st_mode);
}

static kern_return_t repair_symlink(const pres_node_t *n)
{
    struct stat st;
    
    if(lstat(n->path, &st) == 0 && S_ISDIR(st.st_mode))
    {
        char aside[PATH_MAX];
        snprintf(aside, sizeof aside, "%s..displaced%08x", n->path, arc4random());
        
        if(rename(n->path, aside) != 0)
        {
            klog_log("ksurface:fs:preserver", "directory squatting %s, cannot displace: %s", n->path, strerror(errno));
            return KERN_FAILURE;
        }
        klog_log("ksurface:fs:preserver", "displaced directory %s -> %s", n->path, aside);
    }
    
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s..pres%08x", n->path, arc4random());
    
    if(symlink(n->target, tmp) != 0)
    {
        return KERN_FAILURE;
    }
    if(rename(tmp, n->path) != 0)
    {
        unlink(tmp);
        return KERN_FAILURE;
    }
    
    return KERN_SUCCESS;
}

static kern_return_t repair_node(pres_node_t *n)
{
    if(mkdir_chain(n->dir) != 0)
    {
        return KERN_FAILURE;
    }
    
    kern_return_t kr;
    if(n->type == kFSNodeTypeSymbolicLink)
    {
        kr = repair_symlink(n);
    }
    else
    {
        if(mkdir(n->path, PRES_DIR_MODE) == 0 || errno == EEXIST)
        {
            kr = KERN_SUCCESS;
        }
        else if(errno == ENOTDIR)
        {
            unlink(n->path);
            kr = (mkdir(n->path, PRES_DIR_MODE) == 0) ? KERN_SUCCESS : KERN_FAILURE;
        }
        else
        {
            kr = KERN_FAILURE;
        }
    }
    
    n->intact = (kr == KERN_SUCCESS);
    return kr;
}

static void sweep_node(uint32_t idx)
{
    pres_node_t *n = &g_node[idx];
    
    if(node_intact(n))
    {
        n->intact = true;
        return;
    }
    
    if(repair_node(n) != KERN_SUCCESS)
    {
        klog_log("ksurface:fs:preserver", "repair failed: %s (%s)", n->path, strerror(errno));
    }
    else
    {
        klog_log("ksurface:fs:preserver", "repaired %s", n->path);
    }
}

static void sweep_watch(uint32_t widx)
{
    for(uint32_t i = 0; i < g_node_count; i++)
    {
        if(g_node[g_order[i]].watch == widx)
        {
            sweep_node(g_order[i]);
        }
    }
}

static void sweep_all(void)
{
    for(uint32_t i = 0; i < g_node_count; i++)
    {
        sweep_node(g_order[i]);
    }
}

static void arm_watch(uint32_t widx);

static void rearm_dead_watches(void)
{
    for(uint32_t i = 0; i < g_watch_count; i++)
    {
        if(g_watch[i].fd < 0 && !g_watch[i].rearming && !g_watch[i].src)
        {
            arm_watch(i);
        }
    }
}

static void debounce_sweep(uint32_t widx)
{
    pres_watch_t *w = &g_watch[widx];
    if(w->sweep_pending)
    {
        return;
    }
    w->sweep_pending = true;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, PRES_DEBOUNCE_NS), g_q, ^{
        g_watch[widx].sweep_pending = false;
        sweep_watch(widx);
    });
}

static void arm_watch(uint32_t widx)
{
    pres_watch_t *w = &g_watch[widx];
    
    if(mkdir_chain(w->dir) != 0)
    {
        klog_log("ksurface:fs:preserver", "cannot materialize %s", w->dir);
        return;
    }
    
    w->fd = open(w->dir, O_EVTONLY | O_DIRECTORY);
    if(w->fd < 0)
    {
        klog_log("ksurface:fs:preserver", "open %s: %s (will retry)", w->dir, strerror(errno));
        w->fd = -1;
        return;
    }
    
    w->src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, w->fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME, g_q);
    
    dispatch_source_set_event_handler(w->src, ^{
        pres_watch_t *ww = &g_watch[widx];
        unsigned long fl = dispatch_source_get_data(ww->src);
        
        if(fl & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME))
        {
            if(ww->rearming)
            {
                return;
            }
            ww->rearming = true;
            dispatch_source_cancel(ww->src);
            return;
        }
        debounce_sweep(widx);
    });
    
    dispatch_source_set_cancel_handler(w->src, ^{
        pres_watch_t *ww = &g_watch[widx];
        close(ww->fd);
        ww->fd = -1;
        ww->src = NULL;
        if(ww->rearming)
        {
            ww->rearming = false;
            arm_watch(widx);
            sweep_watch(widx);
        }
    });
    
    dispatch_resume(w->src);
}

static uint32_t watch_for_dir(const char *dir)
{
    for(uint32_t i = 0; i < g_watch_count; i++)
    {
        if(strcmp(g_watch[i].dir, dir) == 0)
        {
            return i;
        }
    }
    uint32_t i = g_watch_count++;
    strlcpy(g_watch[i].dir, dir, PATH_MAX);
    g_watch[i].fd = -1;
    return i;
}

static kern_return_t pres_append_locked(FSNodeType type,
                                        const char *name,
                                        const char *target)
{
    if(!name || name[0] != '/')
    {
        return KERN_INVALID_ARGUMENT;
    }
    if(type == kFSNodeTypeSymbolicLink && (!target || target[0] != '/'))
    {
        return KERN_INVALID_ARGUMENT;
    }
    if(g_node_count >= PRES_MAX_NODES)
    {
        return KERN_RESOURCE_SHORTAGE;
    }
    
    for(uint32_t i = 0; i < g_node_count; i++)
    {
        if(strcmp(g_node[i].path, name) == 0)
        {
            return KERN_NAME_EXISTS;
        }
    }
    
    pres_node_t *n = &g_node[g_node_count];
    memset(n, 0, sizeof *n);
    n->type = type;
    strlcpy(n->path, name, PATH_MAX);
    if(target)
    {
        strlcpy(n->target, target, PATH_MAX);
    }
    path_parent(n->path, n->dir, PATH_MAX);
    n->depth  = path_depth(n->path);
    n->intact = false;
    g_node_count++;
    
    return KERN_SUCCESS;
}

kern_return_t ksurface_fs_preserver_add_node(FSPreserverNode node)
{
    __block kern_return_t kr;
    dispatch_sync(pres_queue(), ^{
        if(g_started)
        {
            kr = KERN_FAILURE;
            return;
        }
        kr = pres_append_locked(node.type, node.name, node.type == kFSNodeTypeSymbolicLink ? node.target : NULL);
    });
    return kr;
}

kern_return_t ksurface_fs_preserver_add_nodes(const FSPreserverDesc *v,
                                              size_t count,
                                              size_t *failed_index)
{
    if(!v || count == 0)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    __block kern_return_t kr = KERN_SUCCESS;
    __block size_t bad = 0;
    
    dispatch_sync(pres_queue(), ^{
        if(g_started)
        {
            kr = KERN_FAILURE;
            return;
        }
        
        uint32_t mark = g_node_count;
        for(size_t i = 0; i < count; i++)
        {
            kr = pres_append_locked(v[i].type, v[i].name, v[i].target);
            if(kr != KERN_SUCCESS)
            {
                bad = i;
                break;
            }
        }
        
        if(kr != KERN_SUCCESS)
        {
            g_node_count = mark;
        }
    });
    
    if(kr != KERN_SUCCESS && failed_index)
    {
        *failed_index = bad;
    }
    return kr;
}

static int cmp_depth(const void *a,
                     const void *b)
{
    uint16_t da = g_node[*(const uint32_t *)a].depth;
    uint16_t db = g_node[*(const uint32_t *)b].depth;
    return (da > db) - (da < db);
}

kern_return_t ksurface_fs_preserver_kickstart(void)
{
    __block kern_return_t kr = KERN_SUCCESS;
    
    dispatch_sync(pres_queue(), ^{
        if(g_started)
        {
            kr = KERN_FAILURE;
            return;
        }
        if(!g_node_count)
        {
            kr = KERN_FAILURE;
            return;
        }
        g_started = true;
        
        struct rlimit rl;
        if(getrlimit(RLIMIT_NOFILE, &rl) == 0)
        {
            rl.rlim_cur = rl.rlim_max;
            setrlimit(RLIMIT_NOFILE, &rl);
        }
        
        for(uint32_t i = 0; i < g_node_count; i++)
        {
            g_order[i] = i;
        }
        qsort(g_order, g_node_count, sizeof g_order[0], cmp_depth);
        
        for(uint32_t i = 0; i < g_node_count; i++)
        {
            g_node[i].watch = watch_for_dir(g_node[i].dir);
        }
        
        sweep_all();
        for(uint32_t i = 0; i < g_watch_count; i++)
        {
            arm_watch(i);
        }
        sweep_all();
        
        g_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, g_q);
        dispatch_source_set_timer(g_timer, dispatch_time(DISPATCH_TIME_NOW, PRES_SWEEP_SECS * NSEC_PER_SEC), PRES_SWEEP_SECS * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(g_timer, ^{
            sweep_all();
            rearm_dead_watches();
        });
        dispatch_resume(g_timer);
        
        klog_log("ksurface:fs:preserver", "armed: %u nodes, %u watches", g_node_count, g_watch_count);
    });
    
    return kr;
}

static dispatch_queue_t pres_queue(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_q = dispatch_queue_create("org.emexlabs.nyxian.fs-preserver", DISPATCH_QUEUE_SERIAL);
    });
    return g_q;
}
