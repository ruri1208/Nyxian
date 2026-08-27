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

/* ----------------------------------------------------------------------
 *  Project Headers
 * -------------------------------------------------------------------- */
#include <LindChain/ProcEnvironment/Surface/trust/apple.h>

/* ----------------------------------------------------------------------
 *  Types
 * -------------------------------------------------------------------- */
typedef const struct __SecCode *SecStaticCodeRef;
typedef uint32_t SecCSFlags;

extern const CFStringRef kSecCodeInfoEntitlementsDict;

enum {
    kSecCSDefaultFlags = 0,
    kSecCSSigningInformation = 1 << 1,
    kSecCSRequirementInformation = 1 << 2,
};

/* ----------------------------------------------------------------------
 *  Function Prototypes
 * -------------------------------------------------------------------- */
OSStatus SecStaticCodeCreateWithPath(CFURLRef path, SecCSFlags flags, SecStaticCodeRef *staticCode);
OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef *information);

/* ----------------------------------------------------------------------
 *  Functions
 * -------------------------------------------------------------------- */
CFDictionaryRef CopyAppleCSEntitlementsForPath(CFStringRef path,
                                               OSStatus *outErr)
{
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, false);
    if(!url)
    {
        return NULL;
    }
    
    SecStaticCodeRef code = NULL;
    OSStatus st = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &code);
    CFRelease(url);
    if(st != errSecSuccess)
    {
        if(outErr)
        {
            *outErr = st;
            return NULL;
        }
    }
    
    CFDictionaryRef info = NULL;
    st = SecCodeCopySigningInformation(code, kSecCSSigningInformation | kSecCSRequirementInformation, &info);
    CFRelease(code);
    if(st != errSecSuccess)
    {
        if(outErr)
        {
            *outErr = st;
        }
        return NULL;
    }
    
    CFDictionaryRef ents = CFDictionaryGetValue(info, kSecCodeInfoEntitlementsDict);
    if(ents)
    {
        CFRetain(ents);
    }
    CFRelease(info);
    if(outErr)
    {
        *outErr = errSecSuccess;
    }
    return ents;
}

CFTypeRef AppleCSTypeSanizizeKey(CFDictionaryRef appleCSEntitlements,
                                 CFStringRef key,
                                 CFTypeID type)
{
    CFTypeRef value = CFDictionaryGetValue(appleCSEntitlements, key);
    if(value == NULL)
    {
        return NULL;
    }
    
    if(CFGetTypeID(value) == type)
    {
        return value;
    }
    return NULL;
}

CFDictionaryRef ExtractNXT2OutOfAppleCSEntitlements(CFDictionaryRef appleCSEntitlements)
{
    if(appleCSEntitlements == NULL)
    {
        return NULL;
    }
    
    CFMutableArrayRef roPaths = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if(roPaths == NULL)
    {
        return NULL;
    }
    
    CFMutableArrayRef rwPaths = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if(rwPaths == NULL)
    {
        CFRelease(roPaths);
        return NULL;
    }
    
    CFMutableArrayRef lsGetAllowed = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if(lsGetAllowed == NULL)
    {
        CFRelease(rwPaths);
        CFRelease(roPaths);
        return NULL;
    }
    
    CFMutableDictionaryRef newNXT2Entitlements = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if(newNXT2Entitlements == NULL)
    {
        CFRelease(lsGetAllowed);
        CFRelease(rwPaths);
        CFRelease(roPaths);
        return NULL;
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("get-task-allow")) == kCFBooleanTrue)
    {
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementGetTaskAllow, kCFBooleanTrue);
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("task_for_pid-allow")) == kCFBooleanTrue)
    {
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementTaskForPid, kCFBooleanTrue);
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.system-task-ports")) == kCFBooleanTrue)
    {
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementSystemTaskPorts, kCFBooleanTrue);
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("platform-application")) == kCFBooleanTrue)
    {
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementPlatform, kCFBooleanTrue);
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("proc_info-allow")) == kCFBooleanTrue)
    {
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementProcessEnumeration, kCFBooleanTrue);
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.private.security.no-sandbox")) == kCFBooleanTrue ||
       CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.private.security.no-container")) == kCFBooleanTrue ||
       CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.private.security.container-required")) == kCFBooleanFalse)
    {
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementProcessEnumeration, kCFBooleanTrue);
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementProcessKill, kCFBooleanTrue);
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementProcessSpawnSignedOnly, kCFBooleanTrue);
        
        /* they can read rootfs */
        CFArrayAppendValue(roPaths, CFSTR("$(ROOTFS)"));
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.private.security.storage.AppDataContainers")) == kCFBooleanTrue)
    {
        CFArrayAppendValue(rwPaths, CFSTR("$(ROOTFS)/var/mobile/Containers/Data/Application"));
        CFArrayAppendValue(lsGetAllowed, CFSTR("org.emexlabs.bootstrapd"));
    }
    
    CFArrayRef temporarySBXException = AppleCSTypeSanizizeKey(appleCSEntitlements, CFSTR("com.apple.security.temporary-exception.sbpl"), CFArrayGetTypeID());
    if(temporarySBXException != NULL)
    {
        CFIndex temporarySBXExceptionCount = CFArrayGetCount(temporarySBXException);
        for(CFIndex index = 0; index < temporarySBXExceptionCount; index++)
        {
            CFTypeRef value = CFArrayGetValueAtIndex(temporarySBXException, index);
            if(CFEqual(value, CFSTR("(allow signal)")))
            {
                CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementProcessKill, kCFBooleanTrue);
            }
            else if(CFEqual(value, CFSTR("(allow process-info-listpids)")) ||
                    CFEqual(value, CFSTR("(allow process-info)")) ||
                    CFEqual(value, CFSTR("(allow process-info*)")))
            {
                CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementProcessEnumeration, kCFBooleanTrue);
            }
        }
    }
    
    if(CFArrayGetCount(roPaths) > 0)
    {
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementSandboxFileRead, roPaths);
    }
    if(CFArrayGetCount(rwPaths) > 0)
    {
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementSandboxFileReadWrite, rwPaths);
    }
    if(CFArrayGetCount(lsGetAllowed) > 0)
    {
        CFDictionaryAddValue(newNXT2Entitlements, kNXT2EntitlementLaunchServicesGetEndpointAllowList, lsGetAllowed);
    }
    CFRelease(lsGetAllowed);
    CFRelease(roPaths);
    CFRelease(rwPaths);
    
    return newNXT2Entitlements;
}
