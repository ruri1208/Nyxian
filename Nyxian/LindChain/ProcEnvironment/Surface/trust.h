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
#import <LindChain/ProcEnvironment/Surface/entitlement.h>

kern_return_t nxtr_sign(const char *path, PEEntitlement entitlement);
kern_return_t nxtr_sign_fd(int fd, PEEntitlement entitlement);
kern_return_t nxtr_read(const char *path, ksurface_nxtr_result_t *result);
kern_return_t nxtr_read_fd(int fd, ksurface_nxtr_result_t *result);

#endif /* SIGNING_TRUST_H */
