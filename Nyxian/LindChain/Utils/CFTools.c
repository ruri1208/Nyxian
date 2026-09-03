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

#include <LindChain/Utils/CFTools.h>
#include <assert.h>
#include <malloc/malloc.h>

void CFOverwrite(CFTypeRef dst,
                 CFTypeRef src)
{
    assert(src != NULL && dst != NULL);
    
    /* literally overwriting object, this is normal memory */
    CFTypeID srcID = CFGetTypeID(src);
    CFTypeID dstID = CFGetTypeID(dst);
    assert(srcID == dstID);
    
    /*
     * CFRuntimeBase = isa (8) + refcount/flags (8) = 16 bytes
     * skip it... preserve identity (pointer) and retain count
     */
    size_t src_size = malloc_size(src);
    size_t size = malloc_size(dst);
    assert(src_size <= size);
    
    /*
     * retain everything in src payload first
     * so objects survive when dst's old pointers get orphaned.
     */
    CFRetain(src);
    
    memcpy((uint8_t *)dst + cfheader_size(), (uint8_t *)src + cfheader_size(), size - cfheader_size());
}

Boolean CFSwap(CFTypeRef ref1,
               CFTypeRef ref2)
{
    if(ref1 == NULL || ref2 == NULL || CFGetTypeID(ref1) != CFGetTypeID(ref2))
    {
        return false;
    }
    
    /*
     * CFRuntimeBase = isa (8) + refcount/flags (8) = 16 bytes
     * skip it... preserve identity (pointer) and retain count
     */
    size_t len = malloc_size(ref1);
    if(len != malloc_size(ref2))
    {
        return false;
    }
    
    /* lets do the magic */
    UInt8 buffer[len];
    memcpy(buffer + cfheader_size(), (UInt8*)ref1 + cfheader_size(), len - cfheader_size());
    memcpy((UInt8*)ref1 + cfheader_size(), (UInt8*)ref2 + cfheader_size(), len - cfheader_size());
    memcpy((UInt8*)ref2 + cfheader_size(), buffer + cfheader_size(), len - cfheader_size());
    return true;
}

static inline CFIndex __CFBundleGetBinaryTypeOffset(CFBundleRef hostBundle)
{
    static CFIndex discoveredOffset = -1;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uint32_t *ptr = (uint32_t *)hostBundle;
        for(CFIndex i = 4; i < 30; i++)
        {
            if(ptr[i] == __CFBundleDYLDExecutableBinary || ptr[i] == __CFBundleDYLDFrameworkBinary)
            {
                discoveredOffset = i * sizeof(uint32_t);
                return;
            }
        }
    });
    return discoveredOffset;
}

void CFBundleSetBinaryType(CFBundleRef bundle,
                           __CFPBinaryType type)
{
    if(bundle == NULL)
    {
        return;
    }
    
    CFIndex offset = __CFBundleGetBinaryTypeOffset(bundle);
    if(offset < 0)
    {
        return;
    }
    
    ((UInt8*)bundle)[offset] = (UInt8)type;
}

__CFPBinaryType CFBundleGetBinaryType(CFBundleRef bundle)
{
    if(bundle == NULL)
    {
        return __CFBundleUnknownBinary;
    }
    
    CFIndex offset = __CFBundleGetBinaryTypeOffset(bundle);
    if(offset < 0)
    {
        return __CFBundleUnknownBinary;
    }
    
    return (__CFPBinaryType)((UInt8*)bundle)[offset];
}

void CFReleaseTry(CFTypeRef ref)
{
    if(ref != NULL)
    {
        CFRelease(ref);
    }
}
