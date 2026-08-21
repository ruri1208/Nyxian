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

#ifndef KSURFACE_CONFIG_H
#define KSURFACE_CONFIG_H

/* ----------------------------------------------------------------------
 *  Apple API Headers
 * -------------------------------------------------------------------- */
#include <CoreFoundation/CoreFoundation.h>
#include <sys/syscall.h>

/* ----------------------------------------------------------------------
 *  Macros
 * -------------------------------------------------------------------- */

/* kernel process properties */
#define KSURFACE_EMIT_KERNEL_TASK   1   /* adds kernel task entry, instead of Nyxian entry */
#define KSURFACE_EMIT_LAUNCHD       1   /* adds a launchd entry */

/* syscalling coverage */
#define KSURFACE_SYS_IO_ENABLED     0   /* very early in development */
#define KSURFACE_SYS_IOCTL_ENABLED  1
#define KSURFACE_SYS_SYSCTL_ENABLED 1
#define KSURFACE_SYS_TASK_ENABLED   1
#define KSURFACE_SYS_UCRED_ENABLED  1
#define KSURFACE_SYS_PROC_ENABLED   1

/* security features */
#define KSURFACE_SEC_SANITIZE_ENTITLEMENTS  1   /* strips unecessary entitlements at launch time */

/* dyld debugging features */
#define KSURFACE_DYLD_HOOK_LOGGING_ENABLED  0   /* enables logging from the hooks */

/* additional nyxian syscalls for now */
#define SYS_proctb      750     /* MARK: noop */
#define SYS_getent      751     /* getting processes entitlements */
#define SYS_gethostname 752     /* MARK: noop */
#define SYS_sethostname 753     /* MARK: noop */
#define SYS_gettask     754     /* gets task port */
#define SYS_procpath    755     /* gets process path of a pid */
#define SYS_procbsd     756     /* MARK: noop */
#define SYS_handoffep   757     /* handoff exception port to kvirt */
#define SYS_setent      758     /* sets entitlements (sanitized ofc) */
#define SYS_waittask    759     /* waits till task port of a task is available */
#define SYS_pectl       760     /* utility for many proc environment operations */

/* proc environment control mappings */
/* categories */
typedef CF_ENUM(UInt16, PECTLCategory) {
    kPECTLCategoryLaunchService = 0,
    kPECTLCategoryCodeSigning = 1,
    kPECTLCategoryUserInterface = 2,
    kPECTLCategoryUserspace = 3,
    kPECTLCategoryMisceleanous = 4,
};

/* sub categories */
typedef CF_ENUM(UInt16, PECTLLaunchService) {
    kPECTLLaunchServiceGetEndpoint = 0,
    kPECTLLaunchServiceSetEndpoint = 1,
};

typedef CF_ENUM(UInt16, PECTLCodeSigning) {
    kPECTLCodeSigningGetPublicKey = 0,
    kPECTLCodeSigningGetPrivateKey = 1,
    
    kPECTLCodeSigningSignPath = 2,
    kPECTLCodeSigningGetCDHash = 3,
    
    kPECTLCodeSigningAllEntitlements = 4,
    kPECTLCodeSigningGetEntitlements = 5,
    kPECTLCodeSigningSetEntitlements = 6,
    kPECTLCodeSigningDropAllEntitlements = 7,
};

typedef CF_ENUM(UInt16, PECTLUserInterface) {
    kPECTLUserInterfaceInit = 0,
};

typedef CF_ENUM(UInt16, PECTLUserspace) {
    kPECTLUserspaceReboot = 0,
    kPECTLUserspaceGetMode = 1,
};

typedef CF_ENUM(UInt16, PECTLMisceleanous) {
    kPECTLMisceleanousGetBuildType = 0,
};

typedef CF_ENUM(UInt16, PEBuildType) {
    kPEBuildTypeRelease = 0,
    kPEBuildTypeDebug = 1,
};

#endif /* KSURFACE_CONFIG_H */
