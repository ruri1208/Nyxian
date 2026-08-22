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
 *  Macros
 * -------------------------------------------------------------------- */

/* kernel process configuration */
#define KSURFACE_EMIT_KERNEL_TASK   0   /* adds kernel task entry, instead of Nyxian entry MARK: unsupported currently */
#define KSURFACE_EMIT_LAUNCHD       0   /* adds a launchd entry MARK: unsupported currently */

/* syscalling coverage configuration */
#define KSURFACE_SYS_IO_ENABLED     0   /* very early in development */
#define KSURFACE_SYS_IOCTL_ENABLED  1
#define KSURFACE_SYS_SYSCTL_ENABLED 1
#define KSURFACE_SYS_TASK_ENABLED   1
#define KSURFACE_SYS_UCRED_ENABLED  1
#define KSURFACE_SYS_PROC_ENABLED   1

/* security feature configuration */
#define KSURFACE_SEC_SANITIZE_ENTITLEMENTS      1   /* strips unecessary entitlements at launch time */
#define KSURFACE_SEC_CODESIGNATURE_ACCEPT_NXTR  1

/* dyld debugging feature configuration */
#define KSURFACE_DYLD_HOOK_LOGGING_ENABLED      0   /* enables logging from the hooks */
#define KSURFACE_DYLD_HARDENED_CDHASH_VERIFIER  1   /* hardlocks open on failed cdhash verification (recommended to be enabled as it closes a huge security risk otherwise) */

#endif /* KSURFACE_CONFIG_H */
