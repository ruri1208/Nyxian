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

#ifndef TRUST_SIGNING_H
#define TRUST_SIGNING_H

/* ----------------------------------------------------------------------
 *  System Headers
 * -------------------------------------------------------------------- */
#include <CoreFoundation/CoreFoundation.h>
#include <mach/kern_return.h>

/* ----------------------------------------------------------------------
 *  Project Headers
 * -------------------------------------------------------------------- */
#include <LindChain/ProcEnvironment/Surface/trust/entitlement.h>

/* ----------------------------------------------------------------------
 *  Function Prototypes
 * -------------------------------------------------------------------- */
kern_return_t trust_remove_blob(const char *path);
kern_return_t trust_remove_blob_fd(int fd);

kern_return_t trust_nxtr_sign(const char *path, PEEntitlement entitlement);
kern_return_t trust_nxtr_sign_fd(int fd, PEEntitlement entitlement);
kern_return_t trust_nxtr_read(const char *path, ksurface_nxtr_result_t *result);
kern_return_t trust_nxtr_read_fd(int fd, ksurface_nxtr_result_t *result);

kern_return_t trust_nxt2_sign(const char *path, CFDictionaryRef entitlements, bool signBlob);
kern_return_t trust_nxt2_sign_fd(int fd, CFDictionaryRef entitlements, bool signBlob);
kern_return_t trust_nxt2_read(const char *path, ksurface_nxt2_t *result);
kern_return_t trust_nxt2_read_fd(int fd, ksurface_nxt2_t *result);

#endif /* TRUST_SIGNING_H */
