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

#ifndef LIVESHIM_DYLD_NODE_REMAP_H
#define LIVESHIM_DYLD_NODE_REMAP_H

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/syslimits.h>
#include <stdbool.h>
#include <stdint.h>

#define INODE_BANK_CAPACITY 1024
#define INODE_INVALID       0x0

typedef struct {
    ino_t ino;
    char real_path[PATH_MAX];
    char redirect_path[PATH_MAX];
    bool in_use;
} DyldInodeEntry;

ino_t inode_for_fd(int fd);
void inode_bank_init(void);
void inode_bank_put(ino_t ino, const char *real_path);
void inode_bank_set_redirect(ino_t ino, const char *redirect_path);
bool inode_bank_get_path(ino_t ino, char *out_path, size_t max_len);
bool inode_bank_get_real_path(ino_t ino, char *out_path, size_t max_len);
bool inode_bank_get_ino_by_path(const char *path, ino_t *out_ino);
void inode_bank_unlink_all(const char *tmp_root);

ino_t fake_inode_for_path(const char *path);

#endif /* LIVESHIM_DYLD_NODE_REMAP_H */
