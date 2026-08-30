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

#import <LindChain/ProcEnvironment/KextLoader/PEKext.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#import <LindChain/ProcEnvironment/Surface/trust/signing.h>
#import <LindChain/ProcEnvironment/Surface/kext.h>
#import <LindChain/ProcEnvironment/Utils/klog.h>

@implementation PEKext

- (instancetype)initWithPath:(NSString*)path
{
    self = [super init];
    if(self)
    {
        if(path == nil)
        {
            return NULL;
        }
        
        NSBundle *kextBundle = [NSBundle bundleWithPath:path];
        if(kextBundle == nil)
        {
            return nil;
        }
        
        /* integrity check */
        NSString *executable = kextBundle.executablePath;
        if(executable == nil)
        {
            return nil;
        }
        
        /* validate apple signature */
        LCMachO *machO = LCMapMachO(executable.UTF8String, true);
        if(machO == NULL)
        {
            return nil;
        }
        
        bool isAppleSigned = LCCheckCodeSignature(machO);
        LCUnmapMachO(machO);
        if(!isAppleSigned)
        {
            return nil;
        }
        
        /* validate kext's nxt2 blob */
        ksurface_nxt2_t result = {};
        kern_return_t kr = trust_nxt2_read(executable.UTF8String, &result);
        if(kr != KERN_SUCCESS ||
           !result.isValid ||
           !result.isSigned ||
           !result.isCdHashValid)
        {
            if(result.entitlements != nil)
            {
                CFRelease(result.entitlements);
            }
            return nil;
        }
        
        /* check entitlements */
        bool hasEntitlement = CFDictionaryGetValue(result.entitlements, kNXT2EntitlementKsurfaceKEXTLoading) == kCFBooleanTrue;
        CFRelease(result.entitlements);
        if(!hasEntitlement)
        {
            return nil;
        }
        
        _executablePath = kextBundle.executablePath;
        if(_executablePath == nil)
        {
            return nil;
        }
        
        kinfo_mod_t info = {};
        kmod_dependency_t *deps = NULL;
        uint32_t ndeps = 0;
        
        kr = ksurface_kext_copy_kmod(_executablePath.UTF8String, &info, &deps, &ndeps);
        if(kr != KERN_SUCCESS)
        {
            return nil;
        }
        
        NSMutableArray<PEDependency*> *dependencies = [NSMutableArray array];
        
        klog_log("ksurface:kextloader", "%s v%u.%u.%u (abi %u, flags 0x%llx)", info.identifier, KMOD_VERSION_MAJOR(info.version), KMOD_VERSION_MINOR(info.version), KMOD_VERSION_PATCH(info.version), info.abi_version, (unsigned long long)info.flags);
        for(uint32_t i = 0; i < ndeps; i++)
        {
            PEDependency *dependency = [[PEDependency alloc] init];
            dependency.bundleID = [NSString stringWithCString:deps[i].identifier encoding:NSUTF8StringEncoding];
            dependency.minVersion = [NSString stringWithFormat:@"%u.%u.%u", KMOD_VERSION_MAJOR(deps[i].min_version), KMOD_VERSION_MINOR(deps[i].min_version), KMOD_VERSION_PATCH(deps[i].min_version)];
            dependency.maxVersion = [NSString stringWithFormat:@"%u.%u.%u", KMOD_VERSION_MAJOR(deps[i].max_version), KMOD_VERSION_MINOR(deps[i].max_version), KMOD_VERSION_PATCH(deps[i].max_version)];
            
            if(dependency.bundleID == nil || dependency.minVersion == nil || dependency.maxVersion == nil)
            {
                ksurface_kext_free_deps(deps);
                return nil;
            }
            [dependencies addObject:dependency];
            klog_log("ksurface:kextloader", "  needs %s [%u.%u.%u .. %u.%u.%u]", deps[i].identifier, KMOD_VERSION_MAJOR(deps[i].min_version), KMOD_VERSION_MINOR(deps[i].min_version), KMOD_VERSION_PATCH(deps[i].min_version), KMOD_VERSION_MAJOR(deps[i].max_version), KMOD_VERSION_MINOR(deps[i].max_version), KMOD_VERSION_PATCH(deps[i].max_version));
        }
        ksurface_kext_free_deps(deps);
        
        _dependencies = [dependencies copy];
        _bundleID = [NSString stringWithCString:info.identifier encoding:NSUTF8StringEncoding];
        _version = [NSString stringWithFormat:@"%u.%u.%u", KMOD_VERSION_MAJOR(info.version), KMOD_VERSION_MINOR(info.version), KMOD_VERSION_PATCH(info.version)];
        _bundlePath = kextBundle.bundlePath;
        
        /* final check */
        if(_bundleID == nil || _version == nil || _executablePath == nil || _dependencies == nil || _bundlePath == nil)
        {
            return nil;
        }
    }
    return self;
}

+ (instancetype)ksurfaceMainKext
{
    PEKext *kext = [[self alloc] init];
    kext.executablePath = @"ksurface";
    kext.bundleID = @"ksurface";
    kext.version = @"0.11.4";
    return kext;
}

+ (BOOL)isVersion:(NSString *)version
       betweenMin:(NSString *)minVersion
              max:(NSString *)maxVersion
{
    if(minVersion)
    {
        NSComparisonResult minCheck = [version compare:minVersion options:NSNumericSearch];
        if(minCheck == NSOrderedAscending)
        {
            return NO;
        }
    }
    
    if(maxVersion)
    {
        NSComparisonResult maxCheck = [version compare:maxVersion options:NSNumericSearch];
        if(maxCheck == NSOrderedDescending)
        {
            return NO;
        }
    }
    
    return YES;
}

+ (NSArray<PEKext*>*)generateLoadChainForPath:(NSString*)path
{
    NSArray<NSString*> *kextPaths = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    if(kextPaths == nil)
    {
        return nil;
    }
    
    /* getting kexts initially */
    NSMutableArray<PEKext*> *allKexts = [NSMutableArray array];
    [allKexts addObject:[PEKext ksurfaceMainKext]];
    for(NSString *kextPath in kextPaths)
    {
        PEKext *kext = [[PEKext alloc] initWithPath:[path stringByAppendingPathComponent:kextPath]];
        if(kext == nil)
        {
            continue;
        }
        [allKexts addObject:kext];
    }
    
    /* intiliting map */
    NSMutableDictionary<NSString *, PEKext *> *kextMap = [NSMutableDictionary dictionary];
    for(PEKext *kext in allKexts)
    {
        kextMap[kext.bundleID] = kext;
    }
    
    BOOL removedAny;
    do
    {
        removedAny = NO;
        NSArray *currentBundleIDs = [kextMap.allKeys copy];
        
        for(NSString *bundleID in currentBundleIDs)
        {
            PEKext *kext = kextMap[bundleID];
            BOOL dependenciesSatisfied = YES;
            
            for(PEDependency *dep in kext.dependencies)
            {
                PEKext *resolvedDep = kextMap[dep.bundleID];
                if(!resolvedDep)
                {
                    dependenciesSatisfied = NO;
                    break;
                }
                
                if(![self isVersion:resolvedDep.version betweenMin:dep.minVersion max:dep.maxVersion])
                {
                    dependenciesSatisfied = NO;
                    break;
                }
            }
            
            if(!dependenciesSatisfied)
            {
                [kextMap removeObjectForKey:bundleID];
                removedAny = YES;
            }
        }
    } while(removedAny);
    
    NSMutableDictionary<NSString*,NSNumber*> *inDegree = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString*,NSMutableArray<NSString*>*> *dependents = [NSMutableDictionary dictionary];
    
    for(PEKext *kext in kextMap.allValues)
    {
        inDegree[kext.bundleID] = @(kext.dependencies.count);
        for(PEDependency *dep in kext.dependencies)
        {
            if(!dependents[dep.bundleID])
            {
                dependents[dep.bundleID] = [NSMutableArray array];
            }
            [dependents[dep.bundleID] addObject:kext.bundleID];
        }
    }
    
    /* kexts without dependencies shall load first */
    NSMutableArray<PEKext *> *queue = [NSMutableArray array];
    for(NSString *bundleID in inDegree)
    {
        if([inDegree[bundleID] integerValue] == 0)
        {
            [queue addObject:kextMap[bundleID]];
        }
    }
    
    /* the final load order */
    NSMutableArray<PEKext *> *loadOrder = [NSMutableArray array];
    while(queue.count > 0)
    {
        PEKext *current = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [loadOrder addObject:current];
        NSArray *dependentIDs = dependents[current.bundleID];
        for(NSString *depID in dependentIDs)
        {
            NSInteger count = [inDegree[depID] integerValue] - 1;
            inDegree[depID] = @(count);
            if(count == 0)
            {
                [queue addObject:kextMap[depID]];
            }
        }
    }
    
    if(loadOrder.count != kextMap.count)
    {
        return nil;
    }
    
    return loadOrder;
}

@end
