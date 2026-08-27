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

#if DEBUG

#ifndef PESURFACETOOLS_H
#define PESURFACETOOLS_H

#import <Foundation/Foundation.h>
#import <LindChain/ProcEnvironment/Surface/surface.h>

@interface PESurfaceProcDescriptor : NSObject

@property (nonatomic,readonly) ksurface_proc_t *rawProc;

/* unchangable immutable process information */
@property (nonatomic,readonly) pid_t pid;
@property (nonatomic,readonly) pid_t ppid;

/* ucred */
@property (nonatomic,readwrite) uid_t euid;
@property (nonatomic,readwrite) uid_t ruid;
@property (nonatomic,readwrite) uid_t svuid;

@property (nonatomic,readwrite) gid_t egid;
@property (nonatomic,readwrite) gid_t rgid;
@property (nonatomic,readwrite) gid_t svgid;

/* entitlements */
@property (nonatomic,readwrite) PEEntitlementFlags entitlement;
@property (nonatomic,readwrite) PEEntitlementFlags maxEntitlement;

@end

@interface PESurfaceStatic : NSObject

@property (class, atomic, readonly) NSArray<PESurfaceProcDescriptor*> *allProcesses;

@end

#endif /* PESURFACETOOLS_H */

#endif /* DEBUG */
