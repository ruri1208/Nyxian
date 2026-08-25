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
 *  Constants
 * -------------------------------------------------------------------- */
const char *trustDaemonPath[] = {   /* those paths are immutable */
    "/sbin/launchd",
    "/usr/libexec/bootstrapd",
};

/* ----------------------------------------------------------------------
 *  Functions
 * -------------------------------------------------------------------- */
static CFDictionaryRef trust_identity_entitlements_from_legacy_entitlements(PEEntitlement entitlement)
{
    CFMutableDictionaryRef dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if(dictionary == NULL)
    {
        return NULL;
    }
    
    /* foundational */
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM, entitlement_got_entitlement(entitlement, kPEEntitlementPlatform) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_ROOT, entitlement_got_entitlement(entitlement, kPEEntitlementPlatformRoot) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_GET_TASK_ALLOW, entitlement_got_entitlement(entitlement, kPEEntitlementGetTaskAllowed) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_TASK_FOR_PID, entitlement_got_entitlement(entitlement, kPEEntitlementTaskForPid) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_SUGID, entitlement_got_entitlement(entitlement, kPEEntitlementProcessElevate) ? kCFBooleanTrue : kCFBooleanFalse);
    
    /* dyld */
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_DYLD_HIDE_LP, entitlement_got_entitlement(entitlement, kPEEntitlementDyldHideLiveProcess) ? kCFBooleanTrue : kCFBooleanFalse);
    
    /* process */
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_ENUM, entitlement_got_entitlement(entitlement, kPEEntitlementProcessEnumeration) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_KILL, entitlement_got_entitlement(entitlement, kPEEntitlementProcessKill) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN, entitlement_got_entitlement(entitlement, kPEEntitlementProcessSpawn) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN_SIGNED, entitlement_got_entitlement(entitlement, kPEEntitlementProcessSpawnSignedOnly) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN_INHERITE_ENT, entitlement_got_entitlement(entitlement, kPEEntitlementProcessSpawnInheriteEntitlements) ? kCFBooleanTrue : kCFBooleanFalse);
    
    /* management */
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_HOST, entitlement_got_entitlement(entitlement, kPEEntitlementHostManager) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_CREDENTIALS, entitlement_got_entitlement(entitlement, kPEEntitlementCredentialsManager) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_LAUNCHSERVICE, entitlement_got_entitlement(entitlement, kPEEntitlementLaunchServicesManager) ? kCFBooleanTrue : kCFBooleanFalse);
    
    /* launch services */
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_LS_START, entitlement_got_entitlement(entitlement, kPEEntitlementLaunchServicesStart) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_LS_STOP, entitlement_got_entitlement(entitlement, kPEEntitlementLaunchServicesStop) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_LS_TOGGLE, entitlement_got_entitlement(entitlement, kPEEntitlementLaunchServicesToggle) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_LS_GET_ENDPOINT, entitlement_got_entitlement(entitlement, kPEEntitlementLaunchServicesGetEndpoint) ? kCFBooleanTrue : kCFBooleanFalse);
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_LS_SET_ENDPOINT, entitlement_got_entitlement(entitlement, kPEEntitlementLaunchServicesSetEndpoint) ? kCFBooleanTrue : kCFBooleanFalse);
    
    /* sandbox */
    CFMutableArrayRef filePermissions = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if(filePermissions == NULL)
    {
        CFRelease(dictionary);
        return NULL;
    }
    
    CFDictionaryAddValue(dictionary, KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ_WRITE, filePermissions);
    return dictionary;
}

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
        { KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM,            CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_ROOT,       CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_USER,       CFNumberGetTypeID()  },
        { KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_GROUP,      CFNumberGetTypeID()  },
        { KSURFACE_NXT2_ENTITLEMENT_ID_GET_TASK_ALLOW,      CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_TASK_FOR_PID,        CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_SUGID,               CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_SYSTEM_TASK_PORTS,   CFBooleanGetTypeID() },
        
        /* dyld */
        { KSURFACE_NXT2_ENTITLEMENT_ID_DYLD_HIDE_LP,        CFBooleanGetTypeID() },
        
        /* process */
        { KSURFACE_NXT2_ENTITLEMENT_ID_PROC_ENUM,           CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_PROC_KILL,           CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN,          CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN_SIGNED,   CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN_INHERITE_ENT, CFBooleanGetTypeID() },
        
        /* management */
        { KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_HOST,           CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_CREDENTIALS,    CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_LAUNCHSERVICE,  CFBooleanGetTypeID() },
        
        /* launch services */
        { KSURFACE_NXT2_ENTITLEMENT_ID_LS_START,            CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_LS_STOP,             CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_LS_TOGGLE,           CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_LS_GET_ENDPOINT,     CFBooleanGetTypeID() },
        { KSURFACE_NXT2_ENTITLEMENT_ID_LS_SET_ENDPOINT,     CFBooleanGetTypeID() },
        
        /* sandbox */
        { KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ,        CFArrayGetTypeID()   },
        { KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ_WRITE,  CFArrayGetTypeID()   },
        { KSURFACE_NXT2_ENTITLEMENT_ID_SB_NO_CONTAINER,     CFBooleanGetTypeID() },
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
    CFArrayRef existing = CFDictionaryGetValue(clean, KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ_WRITE);
    if(existing)
    {
        rwPaths = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, existing);
    }
    else
    {
        rwPaths = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    }
    
    CFMutableArrayRef roPaths;
    CFArrayRef roExisting = CFDictionaryGetValue(clean, KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ);
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
        if(CFDictionaryGetValue(clean, KSURFACE_NXT2_ENTITLEMENT_ID_SB_NO_CONTAINER) != kCFBooleanTrue)
        {
            /* grant container access */
            CFArrayAppendValue(roPaths, CFSTR("$(CONTAINER)"));
            CFArrayAppendValue(rwPaths, CFSTR("$(CONTAINER)/*"));
        }
        
        CFDictionarySetValue(clean, KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ, roPaths);
        CFDictionarySetValue(clean, KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ_WRITE, rwPaths);
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
        NSArray<NSString*> *readFilePermissions = nsEntitlements[(__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ];
        NSArray<NSString*> *readWriteFilePermissions = nsEntitlements[(__bridge NSString*)KSURFACE_NXT2_ENTITLEMENT_ID_SB_FILE_READ_WRITE];
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

static PEEntitlement trust_identity_legacy_entitlements_from_entitlements(CFDictionaryRef entitlements)
{
    PEEntitlement legacyEntitlements = kPEEntitlementNone;
    if(entitlements == NULL)
    {
        return legacyEntitlements;
    }
    
    #define ENT_IS_TRUE(dict, key) \
        ({ CFTypeRef _v = CFDictionaryGetValue((dict), (key)); \
        (_v != NULL && CFGetTypeID(_v) == CFBooleanGetTypeID() \
        && CFBooleanGetValue((CFBooleanRef)_v)); })
    
    /* foundational */
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM)) legacyEntitlements |= kPEEntitlementPlatform;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_ROOT)) legacyEntitlements |= kPEEntitlementPlatformRoot;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_GET_TASK_ALLOW)) legacyEntitlements |= kPEEntitlementGetTaskAllowed;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_TASK_FOR_PID)) legacyEntitlements |= kPEEntitlementTaskForPid;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_SUGID)) legacyEntitlements |= kPEEntitlementProcessElevate;
    
    /* dyld */
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_DYLD_HIDE_LP)) legacyEntitlements |= kPEEntitlementDyldHideLiveProcess;
    
    /* process */
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_ENUM)) legacyEntitlements |= kPEEntitlementProcessEnumeration;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_KILL)) legacyEntitlements |= kPEEntitlementProcessKill;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN)) legacyEntitlements |= kPEEntitlementProcessSpawn;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN_SIGNED)) legacyEntitlements |= kPEEntitlementProcessSpawnSignedOnly;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN_INHERITE_ENT)) legacyEntitlements |= kPEEntitlementProcessSpawnInheriteEntitlements;
    
    /* management */
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_HOST)) legacyEntitlements |= kPEEntitlementHostManager;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_CREDENTIALS)) legacyEntitlements |= kPEEntitlementCredentialsManager;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_MGMT_LAUNCHSERVICE)) legacyEntitlements |= kPEEntitlementLaunchServicesManager;
    
    /* launch services */
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_LS_START)) legacyEntitlements |= kPEEntitlementLaunchServicesStart;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_LS_STOP)) legacyEntitlements |= kPEEntitlementLaunchServicesStop;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_LS_TOGGLE)) legacyEntitlements |= kPEEntitlementLaunchServicesToggle;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_LS_GET_ENDPOINT)) legacyEntitlements |= kPEEntitlementLaunchServicesGetEndpoint;
    if(ENT_IS_TRUE(entitlements, KSURFACE_NXT2_ENTITLEMENT_ID_LS_SET_ENDPOINT)) legacyEntitlements |= kPEEntitlementLaunchServicesSetEndpoint;
    
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
        identity->legacyEntitlements = trust_identity_legacy_entitlements_from_entitlements(identity->entitlements);
        identity->maxLegacyEntitlements = identity->legacyEntitlements;
        
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
    for(int index = 0; index < sizeof(trustDaemonPath) / sizeof(const char*); index++)
    {
        if(strncmp(path, trustDaemonPath[index], MAXPATHLEN - 1) == 0)
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
            identity->entitlements = CFDictionaryCreateCopy(kCFAllocatorDefault, kPEEntitlementsNXT2PresetsDaemon);
            if(identity->entitlements == NULL)
            {
                errno = ENOMEM;
                CFRelease(executableString);
                return NULL;
            }
            identity->legacyEntitlements = trust_identity_legacy_entitlements_from_entitlements(kPEEntitlementsNXT2PresetsDaemon);
            identity->legacyEntitlements = identity->legacyEntitlements;
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
                free(identity);
                goto fallback;
            }
            identity->legacyEntitlements = trust_identity_legacy_entitlements_from_entitlements(identity->entitlements);
            identity->maxLegacyEntitlements = identity->legacyEntitlements;
            identity->filePermissions = trust_identity_give_file_permissions(executableString, identity->entitlements);
            return identity;
        }
    }
#endif /* KSURFACE_CS_ALLOW_NXT2 */
    
#if KSURFACE_CS_ALLOW_NXTR
    {
        ksurface_nxtr_result_t result_nxtr;
        if(trust_nxtr_read(path, &result_nxtr) == KERN_SUCCESS)
        {
            /* check if blob was signed */
            if(entitlement_mach_verify(&result_nxtr, ksurface->pub_key, ksurface->pub_key_len) != KERN_SUCCESS)
            {
                CFRelease(executableString);
                return NULL;
            }
            
            if(!result_nxtr.blob_valid || !result_nxtr.cdhash_valid)
            {
                CFRelease(executableString);
                return NULL;
            }
            
            ksurface_trust_identity_t *identity = calloc(1, sizeof(ksurface_trust_identity_t));
            if(identity == NULL)
            {
                CFRelease(executableString);
                return NULL;
            }
            
            strlcpy(identity->path, path, MAXPATHLEN);
            memcpy(identity->cdhash, result_nxtr.blob.cdhash, USER_FSIGNATURES_CDHASH_LEN);
            
            identity->trustLevel = kPETrustLevelSignature;
            
            CFDictionaryRef convertedEntitlements = trust_identity_entitlements_from_legacy_entitlements(result_nxtr.blob.entitlement);
            if(convertedEntitlements == NULL)
            {
                free(identity);
                CFRelease(executableString);
                return NULL;
            }
            
            identity->entitlements = trust_identity_validate_entitlements(executableString, convertedEntitlements);
            CFRelease(convertedEntitlements);
            if(identity->entitlements == NULL)
            {
                free(identity);
                CFRelease(executableString);
                return NULL;
            }
            identity->legacyEntitlements = result_nxtr.blob.entitlement;
            identity->maxLegacyEntitlements = identity->legacyEntitlements;
            identity->filePermissions = trust_identity_give_file_permissions(executableString, identity->entitlements);
            return identity;
        }
    }
#endif /* KSURFACE_CS_ALLOW_NXTR */
    
    /* fallback */
fallback:
    {
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
        identity->legacyEntitlements = kPEEntitlementNone;
        identity->maxLegacyEntitlements = kPEEntitlementNone;
        identity->filePermissions = trust_identity_give_file_permissions(executableString, identity->entitlements);
        
        CFRelease(executableString);
        return identity;
    }
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
    if(CFDictionaryGetValue(parentMergingEntitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM) != kCFBooleanTrue)
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
       CFDictionaryGetValue(parentMergingEntitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PROC_SPAWN_INHERITE_ENT) == kCFBooleanTrue)
    {
        /*
         * entitlements which shall be stripped from parent
         * merging entitlements, because they are just too
         * over powered.
         */
        CFDictionaryRemoveValue(parentMergingEntitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM);
        CFDictionaryRemoveValue(parentMergingEntitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_ROOT);
        CFDictionaryRemoveValue(parentMergingEntitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_USER);
        CFDictionaryRemoveValue(parentMergingEntitlements, KSURFACE_NXT2_ENTITLEMENT_ID_PLATFORM_GROUP);
        CFDictionaryRemoveValue(parentMergingEntitlements, KSURFACE_NXT2_ENTITLEMENT_ID_TASK_FOR_PID);
        CFDictionaryRemoveValue(parentMergingEntitlements, KSURFACE_NXT2_ENTITLEMENT_ID_SUGID);
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
    childIdentity->maxLegacyEntitlements = trust_identity_legacy_entitlements_from_entitlements(childNewEntitlements);
    childIdentity->legacyEntitlements = childIdentity->maxLegacyEntitlements;
    
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
