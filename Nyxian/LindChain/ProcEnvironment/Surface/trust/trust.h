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

#ifndef TRUST_TRUST_H
#define TRUST_TRUST_H

/* ----------------------------------------------------------------------
 *  System Headers
 * -------------------------------------------------------------------- */
#include <CoreFoundation/CoreFoundation.h>
#include <sys/param.h>

/* ----------------------------------------------------------------------
 *  Project Headers
 * -------------------------------------------------------------------- */
#include <LindChain/ProcEnvironment/Surface/trust/cdhash.h>
#include <LindChain/ProcEnvironment/Surface/trust/entitlement.h>
#include <LindChain/ProcEnvironment/Surface/trust/signing.h>

/* ----------------------------------------------------------------------
 *  Types
 * -------------------------------------------------------------------- */
typedef enum: UInt8 {
    kPETrustLevelFallback = 0,  /* no trust */
    kPETrustLevelSignature = 1, /* signature trust */
    kPETrustLevelTrusted = 2,   /* system trust */
} PETrustLevel;

typedef struct {
    char path[MAXPATHLEN];
    char cdhash[USER_FSIGNATURES_CDHASH_LEN];
    CFDictionaryRef entitlements;
    CFArrayRef filePermissions;
    PEEntitlement legacyEntitlements;
    PEEntitlement maxLegacyEntitlements;
    PETrustLevel trustLevel;
} ksurface_trust_identity_t;

/* ----------------------------------------------------------------------
 *  Function Prototype
 * -------------------------------------------------------------------- */
ksurface_trust_identity_t *trust_identity_get_kernel(void);

/* they are immutable, except for maxLegacyEntitlements! */
ksurface_trust_identity_t *trust_identity_create_from_path(const char *path);
ksurface_trust_identity_t *trust_identity_create_from_path_with_parent_identity(const char *path, ksurface_trust_identity_t *parentIdentity);

void trust_identity_destroy(ksurface_trust_identity_t *identity);

#endif /* TRUST_TRUST_H */
