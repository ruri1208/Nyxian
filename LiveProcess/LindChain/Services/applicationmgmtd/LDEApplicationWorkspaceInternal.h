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

#ifndef LDEAPPLICATIONWORKSPACE_H
#define LDEAPPLICATIONWORKSPACE_H

#import <Foundation/Foundation.h>
#import "LDEApplicationObject.h"

@interface LDEApplicationWorkspaceInternal : NSObject

@property (nonatomic,strong) NSURL *applicationsURL;
@property (nonatomic,strong) NSURL *containersURL;
@property (nonatomic,strong) NSURL *binaryURL;
@property (nonatomic,strong) NSURL *homeURL;
@property (nonatomic,strong) NSURL *tmpURL;
@property (nonatomic,strong) NSURL *bootstrapPlistURL;
@property (nonatomic,strong) dispatch_queue_t workspaceQueue;
@property (atomic,readwrite) UInt64 version;
@property (atomic,readonly) BOOL isInstalled;
@property (atomic,readwrite) NSMutableDictionary<NSString*,NSBundle*> *bundles;

- (instancetype)init;
+ (LDEApplicationWorkspaceInternal*)shared;

- (BOOL)installApplicationWithPayloadPath:(NSString*)bundlePath;
- (BOOL)deleteApplicationWithBundleID:(NSString*)bundleID;
- (BOOL)applicationInstalledWithBundleID:(NSString*)bundleID;
- (NSBundle*)applicationBundleForBundleID:(NSString*)bundleID;
- (NSURL*)applicationContainerForBundleID:(NSString *)bundleID;
- (BOOL)doWeTrustThatBundle:(NSBundle*)bundle;
- (BOOL)clearContainerForBundleID:(NSString*)bundleID;

@end

#endif /* LDEAPPLICATIONWORKSPACE_H */
