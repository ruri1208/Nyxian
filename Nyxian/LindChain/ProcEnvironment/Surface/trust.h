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

#ifndef SIGNING_TRUST_H
#define SIGNING_TRUST_H

/* ----------------------------------------------------------------------
 *  Surface API Headers
 * -------------------------------------------------------------------- */
#include <LindChain/ProcEnvironment/Surface/entitlement.h>
#include <sys/param.h>
#include <stdbool.h>

kern_return_t nxtr_sign(const char *path, PEEntitlement entitlement);
kern_return_t nxtr_sign_fd(int fd, PEEntitlement entitlement);
kern_return_t nxtr_read(const char *path, ksurface_nxtr_result_t *result);
kern_return_t nxtr_read_fd(int fd, ksurface_nxtr_result_t *result);

kern_return_t nxt2_sign(const char *path, CFDictionaryRef entitlements, bool signBlob);
kern_return_t nxt2_sign_fd(int fd, CFDictionaryRef entitlements, bool signBlob);
kern_return_t nxt2_read(const char *path, ksurface_nxt2_t *result);
kern_return_t nxt2_read_fd(int fd, ksurface_nxt2_t *result);

typedef enum: UInt8 {
    kPETrustTypeFallback = 0,
    kPETrustTypeSignature = 1,
    kPETrustTypeTrusted = 2,
} PETrustType;

typedef struct {
    char path[MAXPATHLEN];
    bool isValid;           /* unlike in nxtr a valid blob in nxt2 means it passes sanity checks! */
    bool isSigned;          /* means the blob is signed */
    bool isCdHashValid;
    char cdhash[USER_FSIGNATURES_CDHASH_LEN];
    CFDictionaryRef entitlements;
    CFArrayRef filePermissions;
    PEEntitlement legacyEntitlements;
    PEEntitlement maxLegacyEntitlements;
    PETrustType type;
} ksurface_trust_identity_t;

ksurface_trust_identity_t *trust_identity_get_kernel(void);

/* they are immutable, except for maxLegacyEntitlements! */
ksurface_trust_identity_t *trust_identity_create_from_path(const char *path);
/* ksurface_trust_identity_t *trust_identity_create_from_path_with_parent_identity(const char *path, ksurface_trust_identity_t *parentIdentity); */
void trust_identity_destroy(ksurface_trust_identity_t *identity);

#endif /* SIGNING_TRUST_H */
