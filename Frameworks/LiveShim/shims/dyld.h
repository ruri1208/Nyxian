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

#ifndef LIVESHIM_DYLD_H
#define LIVESHIM_DYLD_H

#include <dlfcn.h>

typedef void (*dlopen_cdhash_verifier_failed_callback_t)(int fd, bool *deny_open);

void *dlopen_cdhash_verified(const char *path, int flags, const char *cdhash, dlopen_cdhash_verifier_failed_callback_t callback);

const char *dyld_get_mmap_sandbox_map_exec_allowed_path(void);

#endif /* LIVESHIM_DYLD_H */
