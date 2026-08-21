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

#ifndef PROC_ENTITLEMENT_H
#define PROC_ENTITLEMENT_H

#include <CoreFoundation/CoreFoundation.h>
#include <mach/kern_return.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <fcntl.h>

typedef struct ksurface_proc ksurface_proc_t;
typedef struct ksurface_ent_blob ksurface_ent_blob_t;
typedef struct ksurface_ent_result ksurface_ent_result_t;

/*!
 @enum PEEntitlement
 @abstract Entitlements which are responsible for the permitives of the environment hostsided
 */
typedef CF_OPTIONS(uint64_t, PEEntitlement) {
    /*! No entitlements at all */
    kPEEntitlementNone                              = 0,
    
    /*! Grants other processes with appropriate permitives to get task port of process .*/
    kPEEntitlementGetTaskAllowed                    = 1ull << 0,
    
    /*! Grants process to get task port of processes. */
    kPEEntitlementTaskForPid                        = 1ull << 1,
    
    /*
     * MARK: banned, because too powerful and replaced with PEEntitlementPlatform
     *
     * PEEntitlementTaskForPidHost                  = 1ull << 2,
     */
    
    /*! Grants process to enumerate processes. */
    kPEEntitlementProcessEnumeration                = 1ull << 3,
    
    /*! Grants process to kill other processes. */
    kPEEntitlementProcessKill                       = 1ull << 5,
    
    /*! Grants process to spawn other processes. */
    kPEEntitlementProcessSpawn                      = 1ull << 6,
    
    /*! Grants process to spawn other processes, under the condition that the binary must be signed. */
    kPEEntitlementProcessSpawnSignedOnly            = 1ull << 7,
    
    /*! Grants process to elevate permitive. */
    kPEEntitlementProcessElevate                    = 1ull << 8,
    
    /*! Grants process to manage host. */
    kPEEntitlementHostManager                       = 1ull << 9,
    
    /*! Grants process to manage credentials. */
    kPEEntitlementCredentialsManager                = 1ull << 10,
    
    /*! Grants process to start launch services. */
    kPEEntitlementLaunchServicesStart               = 1ull << 11,
    
    /*! Grants process to stop launch services. */
    kPEEntitlementLaunchServicesStop                = 1ull << 12,
    
    /*! Grants process to manage launch services. */
    kPEEntitlementLaunchServicesToggle              = 1ull << 13,
    
    /*! Grants process to get endpoint of launch services. */
    kPEEntitlementLaunchServicesGetEndpoint         = 1ull << 14,
    
    /*! Grants process to set endpoint of launch services. */
    kPEEntitlementLaunchServicesSetEndpoint         = 1ull << 15,
    
    /*! Grants process to manage launch services. */
    kPEEntitlementLaunchServicesManager             = kPEEntitlementLaunchServicesStart | kPEEntitlementLaunchServicesStop | kPEEntitlementLaunchServicesToggle | kPEEntitlementLaunchServicesSetEndpoint | kPEEntitlementLaunchServicesGetEndpoint,
    
    /*
     * MARK: there is no device spoofing currently, but preserving for the future 
     *
     * PEEntitlementEnforceDeviceSpoof                 = 1ull << 17,
     */
    
    /*! Hides LiveProcess in DYLD Api. (recommended) */
    kPEEntitlementDyldHideLiveProcess               = 1ull << 18,   /* TODO: this is the opposite of a capability, better rename to PEEntitlementDyldDontHideEnvironment */
    
    /*! Makes a process retain entitlements across processes, made for sandboxed applications and such. Its a security feature. */
    kPEEntitlementProcessSpawnInheriteEntitlements  = 1ull << 19,
    
    /*! Security feature for daemons and such */
    kPEEntitlementPlatform                          = 1ull << 20,
    
    /*! Security feature for daemons to start as root process, requires `PEEntitlementPlatform` to be present */
    kPEEntitlementPlatformRoot                      = 1ull << 21,
    
    /*! New experimentation flags   */
    kPEEntitlementFileRootRW                        = 1ull << 22,
    kPEEntitlementFileBundleRW                      = 1ull << 23,
    kPEEntitlementFileContainerRW                   = 1ull << 24,
    
    kPEEntitlementSandboxedApplication              = kPEEntitlementNone,
    kPEEntitlementUserApplication                   = kPEEntitlementGetTaskAllowed | kPEEntitlementProcessSpawnInheriteEntitlements | kPEEntitlementProcessEnumeration | kPEEntitlementProcessKill | kPEEntitlementProcessSpawnSignedOnly | kPEEntitlementLaunchServicesGetEndpoint | kPEEntitlementDyldHideLiveProcess,
    kPEEntitlementSystemApplication                 = kPEEntitlementTaskForPid | kPEEntitlementProcessEnumeration | kPEEntitlementProcessKill | kPEEntitlementProcessSpawn | kPEEntitlementLaunchServicesManager | kPEEntitlementDyldHideLiveProcess,
    kPEEntitlementSystemDaemon                      = kPEEntitlementTaskForPid | kPEEntitlementProcessEnumeration | kPEEntitlementProcessKill | kPEEntitlementProcessSpawn | kPEEntitlementLaunchServicesManager | kPEEntitlementDyldHideLiveProcess | kPEEntitlementPlatform | kPEEntitlementPlatformRoot,
    kPEEntitlementKernel                            = kPEEntitlementPlatform,   /* doesn't need more, the kernel is the platform, it is the entitlements. */
    
    kPEEntitlementAll                               = kPEEntitlementGetTaskAllowed | kPEEntitlementTaskForPid | kPEEntitlementProcessEnumeration | kPEEntitlementProcessKill | kPEEntitlementProcessSpawn | kPEEntitlementProcessSpawnSignedOnly | kPEEntitlementProcessElevate | kPEEntitlementHostManager | kPEEntitlementCredentialsManager | kPEEntitlementLaunchServicesStart | kPEEntitlementLaunchServicesStop | kPEEntitlementLaunchServicesToggle | kPEEntitlementLaunchServicesGetEndpoint | kPEEntitlementLaunchServicesSetEndpoint | kPEEntitlementDyldHideLiveProcess | kPEEntitlementProcessSpawnInheriteEntitlements | kPEEntitlementPlatform | kPEEntitlementPlatformRoot | kPEEntitlementFileRootRW | kPEEntitlementFileBundleRW | kPEEntitlementFileContainerRW,
};
    
struct __attribute__((packed)) ksurface_ent_blob {
    PEEntitlement entitlement;
    char cdhash[USER_FSIGNATURES_CDHASH_LEN];
    uint64_t nonce;
    uint8_t mac[72];
    size_t mac_len;
};

struct ksurface_ent_result {
    struct ksurface_ent_blob blob;
    bool cdhash_valid;
    bool blob_valid;
};

#define entitlement_got_entitlement(present,needed) (((present) & (needed)) == (needed))
#define entitlement_strip(present,strip) (present) &= ~(strip)

kern_return_t entitlement_token_mach_gen(ksurface_ent_blob_t *blob, const char *cdhash, PEEntitlement entitlement);
kern_return_t entitlement_mach_verify(ksurface_ent_result_t *mach, uint8_t *pub_key, size_t pub_key_len);
PEEntitlement entitlement_get_path(const char *path, bool *wasLocallySigned);
bool entitlement_set_path(const char *path, PEEntitlement entitlement);
PEEntitlement entitlement_sanitize(PEEntitlement base);

#endif /* PROC_ENTITLEMENT_H */
