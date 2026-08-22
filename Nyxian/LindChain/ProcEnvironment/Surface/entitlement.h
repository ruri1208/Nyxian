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
#include <ksurface_config.h>

typedef struct ksurface_proc ksurface_proc_t;
typedef struct ksurface_nxtr_blob ksurface_nxtr_blob_t;
typedef struct ksurface_nxtr_result ksurface_nxtr_result_t;

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
    
    kPEEntitlementAll                               = kPEEntitlementGetTaskAllowed | kPEEntitlementTaskForPid | kPEEntitlementProcessEnumeration | kPEEntitlementProcessKill | kPEEntitlementProcessSpawn | kPEEntitlementProcessSpawnSignedOnly | kPEEntitlementProcessElevate | kPEEntitlementHostManager | kPEEntitlementCredentialsManager | kPEEntitlementLaunchServicesStart | kPEEntitlementLaunchServicesStop | kPEEntitlementLaunchServicesToggle | kPEEntitlementLaunchServicesGetEndpoint | kPEEntitlementLaunchServicesSetEndpoint | kPEEntitlementDyldHideLiveProcess | kPEEntitlementProcessSpawnInheriteEntitlements | kPEEntitlementPlatform | kPEEntitlementPlatformRoot | kPEEntitlementFileRootRW | kPEEntitlementFileBundleRW | kPEEntitlementFileContainerRW,
};

/* foundational */
#define KSURFACE_EXT2_ENTITLEMENT_ID_PLATFORM           CFSTR("org.emexlabs.nyxian.platform")
#define KSURFACE_EXT2_ENTITLEMENT_ID_PLATFORM_ROOT      CFSTR("org.emexlabs.nyxian.platform-root")
#define KSURFACE_EXT2_ENTITLEMENT_ID_GET_TASK_ALLOW     CFSTR("org.emexlabs.nyxian.get-task-allow")
#define KSURFACE_EXT2_ENTITLEMENT_ID_TASK_FOR_PID       CFSTR("org.emexlabs.nyxian.task-for-pid")
#define KSURFACE_EXT2_ENTITLEMENT_ID_SUGID              CFSTR("org.emexlabs.nyxian.sugid")

/* dyld */
#define KSURFACE_EXT2_ENTITLEMENT_ID_DYLD_HIDE_LP       CFSTR("org.emexlabs.nyxian.dyld.hide-live-process")

/* process */
#define KSURFACE_EXT2_ENTITLEMENT_ID_PROC_ENUM          CFSTR("org.emexlabs.nyxian.process.enumeration")
#define KSURFACE_EXT2_ENTITLEMENT_ID_PROC_KILL          CFSTR("org.emexlabs.nyxian.process.kill")
#define KSURFACE_EXT2_ENTITLEMENT_ID_PROC_SPAWN         CFSTR("org.emexlabs.nyxian.process.spawn")
#define KSURFACE_EXT2_ENTITLEMENT_ID_PROC_SPAWN_SIGNED  CFSTR("org.emexlabs.nyxian.process.spawn.signed-only")
#define KSURFACE_EXT2_ENTITLEMENT_ID_PROC_INHERITE_ENT  CFSTR("org.emexlabs.nyxian.process.inherite-entitlements")

/* management */
#define KSURFACE_EXT2_ENTITLEMENT_ID_MGMT_HOST          CFSTR("org.emexlabs.nyxian.management.host")
#define KSURFACE_EXT2_ENTITLEMENT_ID_MGMT_CREDENTIALS   CFSTR("org.emexlabs.nyxian.management.credentials")
#define KSURFACE_EXT2_ENTITLEMENT_ID_MGMT_LAUNCHSERVICE CFSTR("org.emexlabs.nyxian.management.launch-services")

/* launch services */
#define KSURFACE_EXT2_ENTITLEMENT_ID_LS_START           CFSTR("org.emexlabs.nyxian.launch-services.start")
#define KSURFACE_EXT2_ENTITLEMENT_ID_LS_STOP            CFSTR("org.emexlabs.nyxian.launch-services.stop")
#define KSURFACE_EXT2_ENTITLEMENT_ID_LS_TOGGLE          CFSTR("org.emexlabs.nyxian.launch-services.toggle")
#define KSURFACE_EXT2_ENTITLEMENT_ID_LS_GET_ENDPOINT    CFSTR("org.emexlabs.nyxian.launch-services.get-endpoint")
#define KSURFACE_EXT2_ENTITLEMENT_ID_LS_SET_ENDPOINT    CFSTR("org.emexlabs.nyxian.launch-services.set-endpoint")

/* sandbox */
#define KSURFACE_EXT2_ENTITLEMENT_ID_FILE_READ          CFSTR("org.emexlabs.nyxian.sandbox.file.read-only") /* type shall be CFArray */
#define KSURFACE_EXT2_ENTITLEMENT_ID_FILE_READ_WRITE    CFSTR("org.emexlabs.nyxian.sandbox.file.read-only") /* type shall be CFArray */
    
struct __attribute__((packed)) ksurface_nxtr_blob {
    PEEntitlement entitlement;
    char cdhash[USER_FSIGNATURES_CDHASH_LEN];
    uint64_t nonce;
    uint8_t mac[72];
    size_t mac_len;
};

/* header contains everything signed  */
struct __attribute__((packed)) ksurface_nxt2_blob_header {
    char cdhash[USER_FSIGNATURES_CDHASH_LEN];
    uint64_t nonce;
    size_t plist_len;
    const char plist_str[];
};

/* footer remains unsigned, it contains the signing identity */
struct __attribute__((packed))ksurface_nxt2_blob_footer {
    size_t mac_len;
    uint8_t mac[];
};

struct ksurface_nxt2 {
    bool cdhash_valid;
    bool blob_valid;
    char cdhash[USER_FSIGNATURES_CDHASH_LEN];
    CFDictionaryRef entitlements;
};

struct ksurface_nxtr_result {
    struct ksurface_nxtr_blob blob;
    bool cdhash_valid;
    bool blob_valid;
};

#define entitlement_got_entitlement(present,needed) (((present) & (needed)) == (needed))
#define entitlement_strip(present,strip) (present) &= ~(strip)

kern_return_t entitlement_token_mach_gen(ksurface_nxtr_blob_t *blob, const char *cdhash, PEEntitlement entitlement);
kern_return_t entitlement_mach_verify(ksurface_nxtr_result_t *mach, uint8_t *pub_key, size_t pub_key_len);
PEEntitlement entitlement_get_path(const char *path, bool *wasLocallySigned);
bool entitlement_set_path(const char *path, PEEntitlement entitlement);

#if KSURFACE_SEC_SANITIZE_ENTITLEMENTS
PEEntitlement entitlement_sanitize(PEEntitlement base);
#else
#define entitlement_sanitize(base) (base)
#endif /* KSURFACE_SEC_SANITIZE_ENTITLEMENTS */

#endif /* PROC_ENTITLEMENT_H */
