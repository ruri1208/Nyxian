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
#if !CLIENT_ENV
#include <LindChain/ProcEnvironment/Surface/trust/apple.h>
#endif /* !CLIENT_ENV */
#include <CoreFoundation/CoreFoundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <libkern/OSByteOrder.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <mach/machine.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

/* ----------------------------------------------------------------------
 *  Constants
 * -------------------------------------------------------------------- */

#define CSMAGIC_EMBEDDED_SIGNATURE              0xfade0cc0
#define CSMAGIC_CODEDIRECTORY                   0xfade0c02

#define CSSLOT_CODEDIRECTORY                    0
#define CSSLOT_ALTERNATE_CODEDIRECTORIES        0x1000
#define CSSLOT_ALTERNATE_CODEDIRECTORY_LIMIT    0x1005

#define CS_HASHTYPE_SHA1                        1
#define CS_HASHTYPE_SHA256                      2
#define CS_HASHTYPE_SHA256_TRUNCATED            3
#define CS_HASHTYPE_SHA384                      4

/* ----------------------------------------------------------------------
 *  Types
 * -------------------------------------------------------------------- */
typedef struct {
    uint32_t type;
    uint32_t offset;
} CS_BlobIndex;

typedef struct {
    uint32_t magic;
    uint32_t length;
    uint32_t count;
    CS_BlobIndex index[];
} CS_SuperBlob;

typedef struct {
    uint32_t magic;
    uint32_t length;
    uint32_t version;
    uint32_t flags;
    uint32_t hashOffset;
    uint32_t identOffset;
    uint32_t nSpecialSlots;
    uint32_t nCodeSlots;
    uint32_t codeLimit;
    
    uint8_t hashSize;
    uint8_t hashType;
    uint8_t platform;
    uint8_t pageSize;
} CS_CodeDirectoryPrefix;

typedef const struct __SecCode *SecStaticCodeRef;
typedef uint32_t SecCSFlags;

extern const CFStringRef kSecCodeInfoEntitlementsDict;
typedef struct __SecRequirement * SecRequirementRef;

#if !__NXTOOL

enum {
    kSecCSDefaultFlags = 0,
    kSecCSSigningInformation = 1 << 1,
    kSecCSRequirementInformation = 1 << 2,
};

#endif /* !__NXTOOL */

/* ----------------------------------------------------------------------
 *  Function Prototypes
 * -------------------------------------------------------------------- */
OSStatus SecStaticCodeCreateWithPath(CFURLRef path, SecCSFlags flags, SecStaticCodeRef *staticCode);
OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef *information);

/* ----------------------------------------------------------------------
 *  Functions
 * -------------------------------------------------------------------- */
#if !CLIENT_ENV && !__NXTOOL
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
    
    CFArrayRef absoluteRwPaths = CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.security.exception.files.absolute-path.read-write"));
    if(absoluteRwPaths != NULL && CFGetTypeID(absoluteRwPaths) == CFArrayGetTypeID())
    {
        CFIndex count = CFArrayGetCount(absoluteRwPaths);
        for(CFIndex index = 0; index < count; index++)
        {
            CFStringRef absoluteRwPath = CFArrayGetValueAtIndex(absoluteRwPaths, index);
            if(CFGetTypeID(absoluteRwPath) == CFStringGetTypeID())
            {
                CFMutableStringRef pathStr = CFStringCreateMutable(kCFAllocatorDefault, 0);
                if(pathStr != NULL)
                {
                    CFStringAppend(pathStr, CFSTR("$(ROOTFS)"));
                    CFStringAppend(pathStr, absoluteRwPath);
                    CFArrayAppendValue(rwPaths, pathStr);
                    CFRelease(pathStr);
                }
            }
        }
    }
    
    CFArrayRef absoluteRoPaths = CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.security.exception.files.absolute-path.read-only"));
    if(absoluteRoPaths != NULL && CFGetTypeID(absoluteRoPaths) == CFArrayGetTypeID())
    {
        CFIndex count = CFArrayGetCount(absoluteRoPaths);
        for(CFIndex index = 0; index < count; index++)
        {
            CFStringRef absoluteRoPath = CFArrayGetValueAtIndex(absoluteRoPaths, index);
            if(CFGetTypeID(absoluteRoPath) == CFStringGetTypeID())
            {
                CFMutableStringRef pathStr = CFStringCreateMutable(kCFAllocatorDefault, 0);
                if(pathStr != NULL)
                {
                    CFStringAppend(pathStr, CFSTR("$(ROOTFS)"));
                    CFStringAppend(pathStr, absoluteRoPath);
                    CFArrayAppendValue(roPaths, pathStr);
                    CFRelease(pathStr);
                }
            }
        }
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.private.MobileContainerManager.allowed")) == kCFBooleanTrue)
    {
        CFArrayAppendValue(lsGetAllowed, CFSTR("org.emexlabs.bootstrapd"));
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.private.security.storage.AppDataContainers")) == kCFBooleanTrue)
    {
        CFArrayAppendValue(rwPaths, CFSTR("$(ROOTFS)/var/mobile/Containers/Data/Application"));
    }
    
    if(CFDictionaryGetValue(appleCSEntitlements, CFSTR("com.apple.private.security.storage.AppBundles")) == kCFBooleanTrue)
    {
        CFArrayAppendValue(rwPaths, CFSTR("$(ROOTFS)/var/containers/Bundle/Application"));
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
            else if(CFStringHasPrefix(value, CFSTR("(allow process-info")))
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
#endif /* !CLIENT_ENV && !__NXTOOL */

bool __range_valid(size_t offset, size_t length, size_t total)
{
    return offset <= total && length <= total - offset;
}

bool __is_code_directory_slot(uint32_t slot)
{
    if(slot == CSSLOT_CODEDIRECTORY)
    {
        return true;
    }
    
    if(slot >= CSSLOT_ALTERNATE_CODEDIRECTORIES &&
       slot < CSSLOT_ALTERNATE_CODEDIRECTORY_LIMIT)
    {
        return true;
    }
    
    return false;
}

bool __cdhash_for_code_directory(const uint8_t *cd_bytes,
                                 size_t available,
                                 uint8_t result[USER_FSIGNATURES_CDHASH_LEN])
{
    if(cd_bytes == NULL ||
       result == NULL ||
       available < sizeof(CS_CodeDirectoryPrefix))
    {
        return false;
    }
    
    CS_CodeDirectoryPrefix cd;
    memcpy(&cd, cd_bytes, sizeof(cd));
    if(OSSwapBigToHostInt32(cd.magic) != CSMAGIC_CODEDIRECTORY)
    {
        return false;
    }
    
    uint32_t length = OSSwapBigToHostInt32(cd.length);
    if(length < sizeof(CS_CodeDirectoryPrefix) || length > available)
    {
        return false;
    }
    
    switch(cd.hashType)
    {
        case CS_HASHTYPE_SHA1:
        {
            uint8_t digest[CC_SHA1_DIGEST_LENGTH];
            CC_SHA1(cd_bytes, (CC_LONG)length, digest);
            memcpy(result, digest, USER_FSIGNATURES_CDHASH_LEN);
            return true;
        }
        case CS_HASHTYPE_SHA256:
        case CS_HASHTYPE_SHA256_TRUNCATED:
        {
            uint8_t digest[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(cd_bytes, (CC_LONG)length, digest);
            memcpy(result, digest, USER_FSIGNATURES_CDHASH_LEN);
            return true;
        }
        case CS_HASHTYPE_SHA384:
        {
            uint8_t digest[CC_SHA384_DIGEST_LENGTH];
            CC_SHA384(cd_bytes, (CC_LONG)length, digest);
            memcpy(result, digest, USER_FSIGNATURES_CDHASH_LEN);
            return true;
        }
        default:
        {
            return false;
        }
    }
}

static bool superblob_contains_cdhash(const uint8_t *signature,
                                      size_t signature_size,
                                      const uint8_t expected[USER_FSIGNATURES_CDHASH_LEN])
{
    if(signature == NULL || expected == NULL || signature_size < sizeof(CS_SuperBlob))
    {
        return false;
    }
    
    CS_SuperBlob header;
    memcpy(&header, signature, offsetof(CS_SuperBlob, index));
    if(OSSwapBigToHostInt32(header.magic) != CSMAGIC_EMBEDDED_SIGNATURE)
    {
        return false;
    }
    
    uint32_t blob_length = OSSwapBigToHostInt32(header.length);
    uint32_t count = OSSwapBigToHostInt32(header.count);
    if(blob_length > signature_size || blob_length < offsetof(CS_SuperBlob, index))
    {
        return false;
    }
    
    size_t fixed = offsetof(CS_SuperBlob, index);
    if(count > (blob_length - fixed) / sizeof(CS_BlobIndex))
    {
        return false;
    }
    
    for(uint32_t i = 0; i < count; i++)
    {
        CS_BlobIndex entry;
        size_t index_offset = fixed + ((size_t)i * sizeof(CS_BlobIndex));
        memcpy(&entry, signature + index_offset, sizeof(entry));
        
        uint32_t type = OSSwapBigToHostInt32(entry.type);
        uint32_t offset = OSSwapBigToHostInt32(entry.offset);
        
        if(!__is_code_directory_slot(type))
        {
            continue;
        }
        
        if(offset >= blob_length)
        {
            /* mfcker >:3 stop trying to punch your broken executables into my code */
            return false;
        }
        
        uint8_t candidate[USER_FSIGNATURES_CDHASH_LEN];
        if(!__cdhash_for_code_directory(signature + offset, blob_length - offset, candidate))
        {
            /* bad CD don't accept it >:3 */
            return false;
        }
        
        if(memcmp(candidate, expected, USER_FSIGNATURES_CDHASH_LEN) == 0)
        {
            /* okay it is this one ^^ */
            return true;
        }
    }
    
    return false;
}

static bool thin_macho_contains_cdhash(const uint8_t *base,
                                       size_t size,
                                       const uint8_t expected[USER_FSIGNATURES_CDHASH_LEN])
{
    if(base == NULL || expected == NULL || size < sizeof(uint32_t))
    {
        return false;
    }
    
    uint32_t magic;
    
    memcpy(&magic, base, sizeof(magic));
    
    size_t header_size;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    
    if(magic == MH_MAGIC_64)
    {
        if(size < sizeof(struct mach_header_64))
        {
            return false;
        }
        
        struct mach_header_64 hdr;
        memcpy(&hdr, base, sizeof(hdr));
        
        header_size = sizeof(hdr);
        ncmds = hdr.ncmds;
        sizeofcmds = hdr.sizeofcmds;
    }
    else if(magic == MH_MAGIC)
    {
        if(size < sizeof(struct mach_header))
        {
            return false;
        }
        
        struct mach_header hdr;
        
        memcpy(&hdr, base, sizeof(hdr));
        
        header_size = sizeof(hdr);
        ncmds = hdr.ncmds;
        sizeofcmds = hdr.sizeofcmds;
    }
    else
    {
        return false;
    }
    
    if(!__range_valid(header_size, sizeofcmds, size))
    {
        return false;
    }
    
    size_t command_offset = header_size;
    size_t command_end = header_size + sizeofcmds;
    
    int lc_code_sig_count = 0;
    
    for(uint32_t i = 0; i < ncmds; i++)
    {
        if(!__range_valid(command_offset, sizeof(struct load_command), command_end))
        {
            return false;
        }
        
        struct load_command lc;
        memcpy(&lc, base + command_offset, sizeof(lc));
        
        if(lc.cmdsize < sizeof(struct load_command))
        {
            return false;
        }
        
        if(!__range_valid(command_offset, lc.cmdsize, command_end))
        {
            return false;
        }
        
        if(lc.cmd == LC_CODE_SIGNATURE)
        {
            if(lc.cmdsize < sizeof(struct linkedit_data_command))
            {
                return false;
            }
            
            struct linkedit_data_command sig;
            if(++lc_code_sig_count > 1)
            {
                /* only one code signature must be present >:3 */
                return false;
            }
            
            memcpy(&sig, base + command_offset, sizeof(sig));
            
            if(!__range_valid(sig.dataoff, sig.datasize, size))
            {
                return false;
            }
            
            return superblob_contains_cdhash(base + sig.dataoff, sig.datasize, expected);
        }
        
        command_offset += lc.cmdsize;
    }
    
    return false;
}

kern_return_t CDHashMatchesCodeDirectory(const uint8_t *base,
                                         size_t size,
                                         const uint8_t expected_cdhash[USER_FSIGNATURES_CDHASH_LEN])
{
    if(base == NULL || expected_cdhash == NULL || size < sizeof(uint32_t))
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    uint32_t magic;
    memcpy(&magic, base, sizeof(magic));
    if(magic == MH_MAGIC || magic == MH_MAGIC_64)
    {
        return thin_macho_contains_cdhash(base, size, expected_cdhash) ? KERN_SUCCESS : KERN_DENIED;
    }
    
    /* is this a fatty? x3 */
    bool fat64;
    if(magic == FAT_CIGAM)
    {
        fat64 = false;
    }
    else if(magic == FAT_CIGAM_64)
    {
        fat64 = true;
    }
    else
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    if(size < sizeof(struct fat_header))
    {
        return KERN_DENIED;
    }
    
    /* hell nah, people still use these?? grow up and use arm64 */
    struct fat_header fat;
    memcpy(&fat, base, sizeof(fat));
    uint32_t nfat_arch =
    OSSwapBigToHostInt32(fat.nfat_arch);
    size_t arch_size = fat64 ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
    if(nfat_arch > (size - sizeof(struct fat_header)) / arch_size)
    {
        return KERN_DENIED;
    }
    
    const size_t table = sizeof(struct fat_header);
    int aarch64_count = 0;
    for(uint32_t i = 0; i < nfat_arch; i++)
    {
        uint64_t slice_offset;
        uint64_t slice_size;
        cpu_type_t cputype;
        
        if(fat64)
        {
            struct fat_arch_64 arch;
            memcpy(&arch, base + table + ((size_t)i * sizeof(arch)), sizeof(arch));
            cputype = OSSwapBigToHostInt32(arch.cputype);
            slice_offset = OSSwapBigToHostInt64(arch.offset);
            slice_size = OSSwapBigToHostInt64(arch.size);
        }
        else
        {
            struct fat_arch arch;
            memcpy(&arch, base + table + ((size_t)i * sizeof(arch)), sizeof(arch));
            cputype = OSSwapBigToHostInt32(arch.cputype);
            slice_offset = OSSwapBigToHostInt32(arch.offset);
            slice_size = OSSwapBigToHostInt32(arch.size);
        }
        
        if(cputype != CPU_TYPE_ARM64)
        {
            continue;
        }
        
        if(++aarch64_count > 1)
        {
            /* only one aarch64 slice */
            return KERN_DENIED;
        }
        
        if(slice_offset > SIZE_MAX || slice_size > SIZE_MAX)
        {
            return KERN_DENIED;
        }
        
        if(!__range_valid((size_t)slice_offset, (size_t)slice_size, size))
        {
            return KERN_DENIED;
        }
        
        if(thin_macho_contains_cdhash(base + (size_t)slice_offset, (size_t)slice_size, expected_cdhash))
        {
            return KERN_SUCCESS;
        }
    }
    
    return KERN_DENIED;
}

kern_return_t CDHashMatchesCodeDirectoryFD(int fd,
                                           const uint8_t expected_cdhash[USER_FSIGNATURES_CDHASH_LEN])
{
    if(fd < 0 || expected_cdhash == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    struct stat st;
    if(fstat(fd, &st) != 0 || st.st_size <= 0)
    {
        return KERN_FAILURE;
    }
    
    size_t size = (size_t)st.st_size;
    const uint8_t *base = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    if(base == MAP_FAILED)
    {
        return KERN_FAILURE;
    }
    
    kern_return_t kr = CDHashMatchesCodeDirectory(base, size, expected_cdhash);
    munmap((void *)base, size);
    return kr;
}

kern_return_t CDHashMatchesCodeDirectoryOfPath(const char *path,
                                               const uint8_t expected_cdhash[USER_FSIGNATURES_CDHASH_LEN])
{
    kern_return_t kr = KERN_FAILURE;
    
    int fd = open(path, O_RDONLY);
    if(fd < 0)
    {
        return kr;
    }
    
    kr = CDHashMatchesCodeDirectoryFD(fd, expected_cdhash);
    close(fd);
    return kr;
}
