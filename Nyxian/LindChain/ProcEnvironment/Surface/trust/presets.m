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

#import <Foundation/Foundation.h>
#import <LindChain/ProcEnvironment/Surface/trust/presets.h>

CFDictionaryRef kPEEntitlementsNXT2PresetsKernel;
CFDictionaryRef kPEEntitlementsNXT2PresetsDaemon;

__attribute__((constructor))
void TrustPresetsInit(void)
{
    kPEEntitlementsNXT2PresetsKernel = (__bridge CFDictionaryRef)@{
        /* platformization */
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM: @(YES),
    };
    
    kPEEntitlementsNXT2PresetsDaemon = (__bridge CFDictionaryRef)@{
        /* platformization */
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM: @(YES),
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_USER: @(0),   /* make sure once set they cannot go back up */
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_GROUP: @(0),
        
        /* process */
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_PROC_ENUM: @(YES),
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN_SIGNED: @(YES),
        
        /* management */
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_HOST: @(YES),
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_LAUNCHSERVICE: @(YES),
        
        /* sandbox */
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ_WRITE: @[
            @"$(ROOTFS)"
        ],
        (__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_SB_NO_CONTAINER: @(YES),
    };
}
