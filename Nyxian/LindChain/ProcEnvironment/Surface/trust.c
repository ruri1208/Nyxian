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

#import <LindChain/ProcEnvironment/Surface/trust.h>
#import <LindChain/ProcEnvironment/Surface/entitlement.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#include <LindChain/ProcEnvironment/Surface/cdhash.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <sys/stat.h>
#import <CommonCrypto/CommonCrypto.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>

#define APPEND_TAG_NXTR "NXTR"
#define APPEND_TAG_NXT2 "NXT2"

ssize_t read_at(int fd, off_t offset, void *buf, size_t len)
{
    if(lseek(fd, offset, SEEK_SET) < 0)
    {
        return KERN_FAILURE;
    }
    
    return read(fd, buf, len);
}

kern_return_t nxtr_sign(const char *path,
                       PEEntitlement entitlement)
{
    int fd = open(path, O_RDWR);
    if(fd < 0)
    {
        return KERN_FAILURE;
    }
    
    kern_return_t retval = nxtr_sign_fd(fd, entitlement);
    fsync(fd);
    close(fd);
    return retval;
}

kern_return_t nxtr_sign_fd(int fd, PEEntitlement entitlement)
{
    LCMachO *machO = LCMapMachOFromFDRO(dup(fd));
    if(machO == NULL)
    {
        return KERN_FAILURE;
    }
    char *cdhash = cdhash_of_hdr((const uint8_t*)machO->header, machO->size);
    LCUnmapMachO(machO);
    
    ksurface_nxtr_blob_t token;
    if(entitlement_token_mach_gen(&token, cdhash, entitlement) != KERN_SUCCESS)
    {
        free(cdhash);
        return KERN_FAILURE;
    }
    free(cdhash);

    char tag[4];
    off_t eof = lseek(fd, 0, SEEK_END);
    
    if(eof >= (off_t)(sizeof(ksurface_nxtr_blob_t) + sizeof(uint32_t) + 4))
    {
        read_at(fd, eof - 4, tag, 4);
        if(memcmp(tag, APPEND_TAG_NXTR, 4) == 0)
        {
            uint32_t data_len;
            read_at(fd, eof - 4 - sizeof(uint32_t), &data_len, sizeof(uint32_t));
            eof -= (off_t)(data_len + sizeof(uint32_t) + 4);
            ftruncate(fd, eof);
        }
    }

    if(lseek(fd, eof, SEEK_SET) < 0)
    {
        return KERN_FAILURE;
    }

    if(write(fd, &token, sizeof(ksurface_nxtr_blob_t)) != (ssize_t)sizeof(ksurface_nxtr_blob_t))
    {
        return KERN_FAILURE;
    }

    size_t data_len = sizeof(ksurface_nxtr_blob_t);
    if(write(fd, &data_len, sizeof(uint32_t)) != sizeof(uint32_t))
    {
        return KERN_FAILURE;
    }
    if(write(fd, APPEND_TAG_NXTR, 4) != 4)
    {
        return KERN_FAILURE;
    }

    return KERN_SUCCESS;
}

kern_return_t nxtr_read(const char *path,
                        ksurface_nxtr_result_t *result)
{
    int fd = open(path, O_RDONLY);
    if(fd < 0)
    {
        return KERN_FAILURE;
    }
    
    int ret = nxtr_read_fd(fd, result);
    close(fd);
    return ret;
}

kern_return_t nxtr_read_fd(int fd,
                           ksurface_nxtr_result_t *result)
{
    bzero(result, sizeof(ksurface_nxtr_result_t));
    
    char tag[4];
    uint32_t len;
    
    if(lseek(fd, -4, SEEK_END) < 0)
    {
        return KERN_FAILURE;
    }
    if(read(fd, tag, 4) != 4)
    {
        return KERN_FAILURE;
    }
    
    if(memcmp(tag, APPEND_TAG_NXTR, 4) != 0)
    {
        return KERN_FAILURE;
    }
    
    if(lseek(fd, -8, SEEK_END) < 0)
    {
        return KERN_FAILURE;
    }
    if(read(fd, &len, sizeof(uint32_t)) != sizeof(uint32_t))
    {
        return KERN_FAILURE;
    }
    
    if(lseek(fd, -(off_t)(8 + len), SEEK_END) < 0)
    {
        return KERN_FAILURE;
    }
    
    if(len != sizeof(ksurface_nxtr_blob_t))
    {
        return KERN_FAILURE;
    }
    
    if(read(fd, &(result->blob), len) != (ssize_t)len)
    {
        return KERN_FAILURE;
    }
    
    LCMachO *machO = LCMapMachOFromFDRO(dup(fd));
    if(machO == NULL)
    {
        return KERN_FAILURE;
    }
    char *hash = cdhash_of_hdr((const uint8_t*)machO->header, machO->size);
    LCUnmapMachO(machO);
    
    if(hash == NULL)
    {
        result->cdhash_valid = false;
        goto out_no_cdhas;
    }
    else if(strncmp(hash, result->blob.cdhash, USER_FSIGNATURES_CDHASH_LEN) == 0)
    {
        free(hash);
        result->cdhash_valid = true;
    out_no_cdhas:
        return KERN_SUCCESS;
    }
    
    free(hash);
    return KERN_FAILURE;
}
