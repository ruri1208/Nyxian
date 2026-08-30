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

#ifndef SURFACE_KEXT_H
#define SURFACE_KEXT_H

#include <stdbool.h>
#include <mach/kern_return.h>

/*
 * this is not a toy API once a malicious kext is
 * loaded there is unfourtunetly nothing I can do
 * to safe your data stored in Nyxian, use this
 * API at your own risk. May the gods of kernel
 * engineering be with you my friend.
 */
#define KSURFACE_KMOD_MAGIC 0x4B4D4F44
#define KSURFACE_KMOD_ABI_VERSION 1
#define KMOD_MAX_NAME 64
#define KMOD_MAX_DEPENDENCIES 32

#define KMOD_VERSION(major, minor, patch) \
    (((uint32_t)(major) & 0xFF) << 16) | \
    (((uint32_t)(minor) & 0xFF) << 8)  | \
     ((uint32_t)(patch) & 0xFF)

#define KMOD_VERSION_MAJOR(v) ((v >> 16) & 0xFF)
#define KMOD_VERSION_MINOR(v) ((v >> 8) & 0xFF)
#define KMOD_VERSION_PATCH(v) (v & 0xFF)

#define EXPORT_KSURFACE_MODULE(...) \
    __attribute__((used, section("__DATA,__ksurfacemod"))) \
    const kinfo_mod_t ksurface_kext_info = __VA_ARGS__;

typedef enum {
    KMOD_FLAG_NONE             = 0,         /* sentinel */
    KMOD_FLAG_PERSISTENT       = (1 << 0),  /* cannot be unloaded */
    KMOD_FLAG_BACKGROUND_ONLY  = (1 << 1),  /* requires it's own thread */
} kmod_flags_t;

typedef struct {
    char identifier[KMOD_MAX_NAME];
    uint32_t min_version;
    uint32_t max_version;
} kmod_dependency_t;

typedef struct kinfo_mod {
    /* identity */
    uint32_t magic;
    uint32_t abi_version;
    const char identifier[KMOD_MAX_NAME];
    uint32_t version;
    uint64_t flags;
    uint32_t dependency_count;
    
    /* handlers */
    kern_return_t (*init)(void);    /* runs synchronious with the other loads, so don't waste resources, except you specify KMOD_FLAG_BACKGROUND_ONLY */
    kern_return_t (*deinit)(void);  /* runs synchronious with the other loads, so don't waste resources, except you specify KMOD_FLAG_BACKGROUND_ONLY */
    kern_return_t (*start)(void);   /* always runs on background thread */
    kern_return_t (*stop)(void);
    
    /* dependencies */
    kmod_dependency_t dependencies[];
} kinfo_mod_t;

kern_return_t ksurface_kext_copy_kmod(const char *path, kinfo_mod_t *out_info, kmod_dependency_t **out_deps, uint32_t *out_dep_count);
void ksurface_kext_free_deps(kmod_dependency_t *deps);
kern_return_t ksurface_kext_load_at_path(const char *path, uint64_t *key);
kern_return_t ksurface_kext_unload_with_key(uint64_t key);

#endif /* SURFACE_KEXT_H */
