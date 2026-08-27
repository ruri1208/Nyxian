/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab
 Copyright (C) 2026 semvis123

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

/* ----------------------------------------------------------------------
 *  System Headers
 * -------------------------------------------------------------------- */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

/* ----------------------------------------------------------------------
 *  Project Headers
 * -------------------------------------------------------------------- */
#import <LindChain/Services/applicationmgmtd/LDEApplicationWorkspace.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#import <LindChain/ProcEnvironment/Surface/trust/trust.h>
#import <LindChain/ProcEnvironment/Surface/surface.h>
#import <LindChain/IDEFoundation/NXBootstrap.h>
#import <ksurface_config.h>

/* ----------------------------------------------------------------------
 *  Types
 * -------------------------------------------------------------------- */
typedef struct {
    const char *path;
    CFDictionaryRef entitlementPreset;
} trustDaemonEntry;

/* ----------------------------------------------------------------------
 *  Functions
 * -------------------------------------------------------------------- */
static bool array_is_all_strings(CFArrayRef arr)
{
    CFIndex n = CFArrayGetCount(arr);
    for(CFIndex i = 0; i < n; i++)
    {
        CFTypeRef e = CFArrayGetValueAtIndex(arr, i);
        if(!e || CFGetTypeID(e) != CFStringGetTypeID())
        {
            return false;
        }
    }
    return true;
}

typedef struct {
    CFStringRef key;
    CFTypeID expected_type;
} entitlement_schema_entry;

static CFDictionaryRef trust_identity_validate_entitlements(CFStringRef executablePath,
                                                            CFDictionaryRef entitlements)
{
    if(entitlements == NULL)
    {
        return NULL;
    }
    
    /* allowance schema */
    const entitlement_schema_entry schema[] = {
        /* foundational */
        { kNXT2EntitlementPlatform,                     CFBooleanGetTypeID() },
        { kNXT2EntitlementPlatformRoot,                 CFBooleanGetTypeID() },
        { kNXT2EntitlementPlatformUser,                 CFNumberGetTypeID()  },
        { kNXT2EntitlementPlatformGroup,                CFNumberGetTypeID()  },
        { kNXT2EntitlementGetTaskAllow,                 CFBooleanGetTypeID() },
        { kNXT2EntitlementTaskForPid,                   CFBooleanGetTypeID() },
        { kNXT2EntitlementSUGID,                        CFBooleanGetTypeID() },
        { kNXT2EntitlementSystemTaskPorts,              CFBooleanGetTypeID() },
        
        /* dyld */
        { kNXT2EntitlementDYLDHideLP,                   CFBooleanGetTypeID() },
        
        /* process */
        { kNXT2EntitlementProcessEnumeration,           CFBooleanGetTypeID() },
        { kNXT2EntitlementProcessKill,                  CFBooleanGetTypeID() },
        { kNXT2EntitlementProcessSpawn,                 CFBooleanGetTypeID() },
        { kNXT2EntitlementProcessSpawnSignedOnly,       CFBooleanGetTypeID() },
        { kNXT2EntitlementProcessSpawnInheriteEntitlements, CFBooleanGetTypeID() },
        
        /* management */
        { kNXT2EntitlementManagementHost,               CFBooleanGetTypeID() },
        
        /* launch services */
        { kNXT2EntitlementLaunchServicesStart,          CFBooleanGetTypeID() },
        { kNXT2EntitlementLaunchServicesStop,           CFBooleanGetTypeID() },
        { kNXT2EntitlementLaunchServicesToggle,         CFBooleanGetTypeID() },
        { kNXT2EntitlementLaunchServicesGetEndpoint,    CFBooleanGetTypeID() },
        { kNXT2EntitlementLaunchServicesSetEndpoint,    CFBooleanGetTypeID() },
        { kNXT2EntitlementLaunchServicesGetEndpointAllowList,   CFArrayGetTypeID() },
        { kNXT2EntitlementLaunchServicesSetEndpointAllowList,   CFArrayGetTypeID() },
        
        /* sandbox */
        { kNXT2EntitlementSandboxFileRead,              CFArrayGetTypeID()   },
        { kNXT2EntitlementSandboxFileReadWrite,         CFArrayGetTypeID()   },
        { kNXT2EntitlementSandboxNoContainer,           CFBooleanGetTypeID() },
    };
    const size_t schema_count = sizeof(schema) / sizeof(schema[0]);
    
    CFMutableDictionaryRef clean = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if(!clean)
    {
        return NULL;
    }
    
    for(size_t i = 0; i < schema_count; i++)
    {
        CFTypeRef val = CFDictionaryGetValue(entitlements, schema[i].key);
        if(val == NULL)
        {
            continue;
        }
        if(CFGetTypeID(val) != schema[i].expected_type)
        {
            continue;
        }
        if(schema[i].expected_type == CFArrayGetTypeID())
        {
            if(!array_is_all_strings((CFArrayRef)val))
            {
                continue;
            }
        }
        CFDictionarySetValue(clean, schema[i].key, val);
    }
    
    /* grant access automatically to executable and blastbox */
    CFMutableArrayRef rwPaths;
    CFArrayRef existing = CFDictionaryGetValue(clean, kNXT2EntitlementSandboxFileReadWrite);
    if(existing)
    {
        rwPaths = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, existing);
    }
    else
    {
        rwPaths = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    }
    
    CFMutableArrayRef roPaths;
    CFArrayRef roExisting = CFDictionaryGetValue(clean, kNXT2EntitlementSandboxFileRead);
    if(roExisting)
    {
        roPaths = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, roExisting);
    }
    else
    {
        roPaths = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    }
    
    if(rwPaths && roPaths)
    {
        /* dyld needs to see the executable */
        CFArrayAppendValue(roPaths, CFSTR("$(EXECUTABLE)"));
        CFArrayAppendValue(roPaths, CFSTR("$(BUNDLE)"));    /* if it is a bundle and bootstrapd has the same opinion about it */
        
        /* some random entitlement */
        if(CFDictionaryGetValue(clean, kNXT2EntitlementSandboxNoContainer) != kCFBooleanTrue)
        {
            /* grant container access */
            CFArrayAppendValue(roPaths, CFSTR("$(CONTAINER)"));
            CFArrayAppendValue(rwPaths, CFSTR("$(CONTAINER)/*"));
        }
        
        CFDictionarySetValue(clean, kNXT2EntitlementSandboxFileRead, roPaths);
        CFDictionarySetValue(clean, kNXT2EntitlementSandboxFileReadWrite, rwPaths);
        CFRelease(rwPaths);
        CFRelease(roPaths);
    }
    
    return clean;
}

static NSArray<NSString *> *PEResolveEntitlementPaths(NSString *pathTemplate,
                                                      NSDictionary<NSString *, NSString *> *vars)
{
    NSMutableString *resolved = [pathTemplate mutableCopy];
    for(NSString *key in vars)
    {
        NSString *token = [NSString stringWithFormat:@"$(%@)", key];
        [resolved replaceOccurrencesOfString:token withString:vars[key] options:0 range:NSMakeRange(0, resolved.length)];
    }
    
    if(![resolved hasSuffix:@"/*"])
    {
        return @[[resolved copy]];
    }
    
    NSString *dir = [resolved substringToIndex:resolved.length - 2];
    while(dir.length > 1 && [dir hasSuffix:@"/"])
    {
        dir = [dir substringToIndex:dir.length - 1];
    }
    
    NSError *err = nil;
    NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:&err];
    if(!entries)
    {
        return @[];
    }
    
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:entries.count];
    for(NSString *name in entries)
    {
        [paths addObject:[dir stringByAppendingPathComponent:name]];
    }
    [paths sortUsingSelector:@selector(compare:)];
    return [paths copy];
}

static NSString *PECanonicalizePath(NSString *path)
{
    char resolved[PATH_MAX];
    if(realpath(path.fileSystemRepresentation, resolved) == NULL)
    {
        return nil;
    }
    return [NSString stringWithUTF8String:resolved];
}

static CFArrayRef trust_identity_give_file_permissions(CFStringRef executableString,
                                                       CFDictionaryRef entitlements)
{
    @autoreleasepool
    {
        NSMutableArray<NSData*> *filePermissions = [[NSMutableArray alloc] init];
        
        /* prepare variables */
        NSMutableDictionary *vars = [@{
            @"ROOTFS": NXBootstrap.shared.rootfsURL.path,
            @"EXECUTABLE": (__bridge NSString*)executableString,
        } mutableCopy];
        
        /* append applicable variables */
        LDEApplicationObject *applicationObject = [[LDEApplicationWorkspace shared] applicationObjectForExecutablePath:(__bridge NSString*)executableString];
        if(applicationObject != nil && applicationObject.bundlePath != nil && applicationObject.containerPath != nil)
        {
            /* is a application bundle */
            vars[@"CONTAINER"] = applicationObject.containerPath;
            vars[@"BUNDLE"] = applicationObject.bundlePath;
        }
        
        NSDictionary *nsEntitlements = (__bridge NSDictionary*)entitlements;
        NSArray<NSString*> *readFilePermissions = nsEntitlements[(__bridge NSString*)kNXT2EntitlementSandboxFileRead];
        NSArray<NSString*> *readWriteFilePermissions = nsEntitlements[(__bridge NSString*)kNXT2EntitlementSandboxFileReadWrite];
        for(NSString *readWriteFilePermission in readWriteFilePermissions)
        {
            NSArray<NSString*> *paths = PEResolveEntitlementPaths(readWriteFilePermission, vars);
            for(NSString *path in paths)
            {
                NSString *actualPath = PECanonicalizePath(path);
                if(actualPath)
                {
                    NSData *sandboxExtension = [NXBootstrap issueSandboxFileExtensionForURL:[NSURL fileURLWithPath:actualPath] readWrite:YES];
                    if(sandboxExtension != nil)
                    {
                        [filePermissions addObject:sandboxExtension];
                    }
                }
            }
        }
        for(NSString *readFilePermission in readFilePermissions)
        {
            NSArray<NSString*> *paths = PEResolveEntitlementPaths(readFilePermission, vars);
            for(NSString *path in paths)
            {
                NSString *actualPath = PECanonicalizePath(path);
                if(actualPath)
                {
                    NSData *sandboxExtension = [NXBootstrap issueSandboxFileExtensionForURL:[NSURL fileURLWithPath:actualPath] readWrite:NO];
                    if(sandboxExtension != nil)
                    {
                        [filePermissions addObject:sandboxExtension];
                    }
                }
            }
        }
        return (__bridge_retained CFArrayRef)filePermissions;
    }
}

PEEntitlementFlags trust_identity_entitlement_flags_from_entitlements(CFDictionaryRef entitlements)
{
    PEEntitlementFlags legacyEntitlements = kPEEntitlementFlagNone;
    if(entitlements == NULL)
    {
        return legacyEntitlements;
    }
    
    #define ENT_IS_TRUE(dict, key) \
        ({ CFTypeRef _v = CFDictionaryGetValue((dict), (key)); \
        (_v != NULL && CFGetTypeID(_v) == CFBooleanGetTypeID() \
        && CFBooleanGetValue((CFBooleanRef)_v)); })
    
    /* foundational */
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementPlatform)) legacyEntitlements |= kPEEntitlementFlagPlatform;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementPlatformRoot)) legacyEntitlements |= kPEEntitlementFlagPlatformRoot;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementGetTaskAllow)) legacyEntitlements |= kPEEntitlementFlagGetTaskAllowed;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementTaskForPid)) legacyEntitlements |= kPEEntitlementFlagTaskForPid;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementSystemTaskPorts)) legacyEntitlements |= kPEEntitlementFlagSystemTaskPorts;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementSUGID)) legacyEntitlements |= kPEEntitlementFlagProcessElevate;
    
    /* dyld */
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementDYLDHideLP)) legacyEntitlements |= kPEEntitlementFlagDyldHideLiveProcess;
    
    /* process */
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementProcessEnumeration)) legacyEntitlements |= kPEEntitlementFlagProcessEnumeration;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementProcessKill)) legacyEntitlements |= kPEEntitlementFlagProcessKill;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementProcessSpawn)) legacyEntitlements |= kPEEntitlementFlagProcessSpawn;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementProcessSpawnSignedOnly)) legacyEntitlements |= kPEEntitlementFlagProcessSpawnSignedOnly;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementProcessSpawnInheriteEntitlements)) legacyEntitlements |= kPEEntitlementFlagProcessSpawnInheriteEntitlements;
    
    /* management */
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementManagementHost)) legacyEntitlements |= kPEEntitlementFlagHostManager;
    
    /* launch services */
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementLaunchServicesStart)) legacyEntitlements |= kPEEntitlementFlagLaunchServicesStart;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementLaunchServicesStop)) legacyEntitlements |= kPEEntitlementFlagLaunchServicesStop;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementLaunchServicesToggle)) legacyEntitlements |= kPEEntitlementFlagLaunchServicesToggle;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementLaunchServicesGetEndpoint)) legacyEntitlements |= kPEEntitlementFlagLaunchServicesGetEndpoint;
    if(ENT_IS_TRUE(entitlements, kNXT2EntitlementLaunchServicesSetEndpoint)) legacyEntitlements |= kPEEntitlementFlagLaunchServicesSetEndpoint;
    
    #undef ENT_IS_TRUE
    return legacyEntitlements;
}

ksurface_trust_identity_t *trust_identity_get_kernel(void)
{
    static ksurface_trust_identity_t *identity = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        identity = calloc(1, sizeof(ksurface_trust_identity_t));
        identity->trustLevel = kPETrustLevelTrusted;
        identity->entitlements = CFDictionaryCreateCopy(kCFAllocatorDefault, kPEEntitlementsNXT2PresetsKernel);
        
        uint32_t bufsize = PATH_MAX;
        if(_NSGetExecutablePath(identity->path, &bufsize) > 0)
        {
            /* shall never happen */
            environment_panic("failed to aquire executable path from dyld");
        }
    });
    return identity;
}

ksurface_trust_identity_t *trust_identity_create_from_path(const char *path)
{
    if(path == NULL)
    {
        errno = EINVAL;
        return NULL;
    }
    
    CFStringRef executableString = CFStringCreateWithCString(kCFAllocatorDefault, path, kCFStringEncodingUTF8);
    if(executableString == NULL)
    {
        return NULL;
    }
    
    /* daemon trustpath validation */
    const trustDaemonEntry trustDaemonPath[] = {   /* those paths are immutable */
        {
            .path = "/usr/libexec/bootstrapd",
            .entitlementPreset = kPEEntitlementsNXT2PresetsDaemonBootstrap,
        }
    };
    
    for(int index = 0; index < sizeof(trustDaemonPath) / sizeof(trustDaemonEntry); index++)
    {
        if(strncmp(path, trustDaemonPath[index].path, MAXPATHLEN - 1) == 0)
        {
            ksurface_trust_identity_t *identity = calloc(1, sizeof(ksurface_trust_identity_t));
            if(identity == NULL)
            {
                /*
                 * returning cause this could become useful in a attack chain.
                 *
                 * 1. exhausting Nyxian's memory.
                 * 2. crash a daemon.
                 * 3. now it runs with fallback entitlements.
                 */
                errno = ENOMEM;
                CFRelease(executableString);
                return NULL;
            }
            strlcpy(identity->path, path, MAXPATHLEN);
            identity->trustLevel = kPETrustLevelTrusted;
            identity->entitlements = CFDictionaryCreateCopy(kCFAllocatorDefault, trustDaemonPath[index].entitlementPreset);
            if(identity->entitlements == NULL)
            {
                errno = ENOMEM;
                CFRelease(executableString);
                return NULL;
            }
            identity->filePermissions = trust_identity_give_file_permissions(executableString, identity->entitlements);
            return identity;
        }
    }
    
    /* check if path is readable and apple signed (required for trust levels lower than kPETrustLevelTrusted, because paths are attacker controlled) */
    if(access(path, R_OK) != 0)
    {
        CFRelease(executableString);
        return NULL;
    }
    
    LCMachO *machO = LCMapMachO(path, false);
    if(machO == NULL)
    {
        CFRelease(executableString);
        return NULL;
    }
    
    bool isAppleSigned = LCCheckCodeSignature(machO);
    LCUnmapMachO(machO);
    if(!isAppleSigned)
    {
        return NULL;
    }
    
    /* signature validation */
#if KSURFACE_CS_ALLOW_NXT2
    {
        ksurface_nxt2_t result_nxt2;
        if(trust_nxt2_read(path, &result_nxt2) == KERN_SUCCESS)
        {
            /* check if blob was signed */
            if(!result_nxt2.isSigned || !result_nxt2.isValid || !result_nxt2.isCdHashValid)
            {
                CFRelease(result_nxt2.entitlements);
                CFRelease(executableString);
                return NULL;
            }
            
            ksurface_trust_identity_t *identity = calloc(1, sizeof(ksurface_trust_identity_t));
            if(identity == NULL)
            {
                CFRelease(result_nxt2.entitlements);
                CFRelease(executableString);
                return NULL;
            }
            
            strlcpy(identity->path, path, MAXPATHLEN);
            memcpy(identity->cdhash, result_nxt2.cdhash, USER_FSIGNATURES_CDHASH_LEN);
            
            identity->trustLevel = kPETrustLevelSignature;
            identity->entitlements = trust_identity_validate_entitlements(executableString, result_nxt2.entitlements);
            CFRelease(result_nxt2.entitlements);
            if(identity->entitlements == NULL)
            {
                CFRelease(executableString);
                free(identity);
                return NULL;
            }
            identity->filePermissions = trust_identity_give_file_permissions(executableString, identity->entitlements);
            return identity;
        }
    }
#endif /* KSURFACE_CS_ALLOW_NXT2 */
    
    /* fallback */
    CFMutableDictionaryRef entitlements = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if(entitlements == NULL)
    {
        CFRelease(executableString);
        errno = ENOMEM;
        return NULL;
    }
    CFDictionaryRef newEntitlements = trust_identity_validate_entitlements(executableString, entitlements); /* gives container access if applicable */
    CFRelease(entitlements);
    if(newEntitlements == NULL)
    {
        CFRelease(executableString);
        errno = ENOMEM;
        return NULL;
    }
    ksurface_trust_identity_t *identity = calloc(1, sizeof(ksurface_trust_identity_t));
    if(identity == NULL)
    {
        CFRelease(executableString);
        errno = ENOMEM;
        return NULL;
    }
    strlcpy(identity->path, path, MAXPATHLEN);
    
    identity->trustLevel = kPETrustLevelFallback;
    identity->entitlements = newEntitlements;
    identity->filePermissions = trust_identity_give_file_permissions(executableString, identity->entitlements);
    
    CFRelease(executableString);
    return identity;
}

ksurface_trust_identity_t *trust_identity_create_from_path_with_parent_identity(const char *path,
                                                                                ksurface_trust_identity_t *parentIdentity)
{
    /* first we create the child's identity */
    ksurface_trust_identity_t *childIdentity = trust_identity_create_from_path(path);
    if(childIdentity == NULL)
    {
        return NULL;
    }
    
    /* entitlement inheritance */
    CFMutableDictionaryRef parentMergingEntitlements = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, parentIdentity->entitlements);
    if(parentMergingEntitlements == NULL)
    {
        return NULL;
    }
    
    CFMutableDictionaryRef childNewEntitlements = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, childIdentity->entitlements);
    if(childNewEntitlements == NULL)
    {
        CFRelease(parentMergingEntitlements);
        return NULL;
    }
    
    /*
     * only a platform identity may be able to
     * cause a process with higher identity
     * than it it self.
     */
    if(CFDictionaryGetValue(parentMergingEntitlements, kNXT2EntitlementPlatform) != kCFBooleanTrue)
    {
        /*
         * child gets nothing extra, removing
         * what parent doesnt have.
         */
        CFIndex childCount = CFDictionaryGetCount(childNewEntitlements);
        if(childCount > 0)
        {
            const void **childKeys = malloc((size_t)childCount * sizeof(*childKeys));
            if(childKeys == NULL)
            {
                return false;
            }
            CFDictionaryGetKeysAndValues(childNewEntitlements, childKeys, NULL);
            for(CFIndex index = 0; index < childCount; index++)
            {
                if(!CFDictionaryContainsKey(parentMergingEntitlements, childKeys[index]))
                {
                    CFDictionaryRemoveValue(childNewEntitlements, childKeys[index]);
                }
            }
            free(childKeys);
        }
    }
    
    if(parentIdentity != trust_identity_get_kernel() && /* the kernel cannot inherite entitlements */
       CFDictionaryGetValue(parentMergingEntitlements, kNXT2EntitlementProcessSpawnInheriteEntitlements) == kCFBooleanTrue)
    {
        /*
         * entitlements which shall be stripped from parent
         * merging entitlements, because they are just too
         * over powered.
         */
        CFDictionaryRemoveValue(parentMergingEntitlements, kNXT2EntitlementPlatform);
        CFDictionaryRemoveValue(parentMergingEntitlements, kNXT2EntitlementPlatformRoot);
        CFDictionaryRemoveValue(parentMergingEntitlements, kNXT2EntitlementPlatformUser);
        CFDictionaryRemoveValue(parentMergingEntitlements, kNXT2EntitlementPlatformGroup);
        CFDictionaryRemoveValue(parentMergingEntitlements, kNXT2EntitlementTaskForPid);
        CFDictionaryRemoveValue(parentMergingEntitlements, kNXT2EntitlementSystemTaskPorts);
        CFDictionaryRemoveValue(parentMergingEntitlements, kNXT2EntitlementSUGID);
    }
    else
    {
        /* not inheriting anything */
        CFDictionaryRemoveAllValues(parentMergingEntitlements);
    }
    
    /* TODO: merging remaining parent entitlements */
    
    /* refreshing childIdentity */
    CFRelease(childIdentity->entitlements);
    childIdentity->entitlements = childNewEntitlements;
    
    return childIdentity;
}

void trust_identity_destroy(ksurface_trust_identity_t *identity)
{
    if(identity == NULL)
    {
        return;
    }
    
    if(identity->entitlements != NULL)
    {
        CFRelease(identity->entitlements);
    }
    if(identity->filePermissions != NULL)
    {
        CFRelease(identity->filePermissions);
    }
    free(identity);
}
