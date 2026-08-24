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
 *  System Headers
 * -------------------------------------------------------------------- */
#import <CommonCrypto/CommonCrypto.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>

/* ----------------------------------------------------------------------
 *  Project Headers
 * -------------------------------------------------------------------- */
#import <LindChain/ProcEnvironment/Surface/trust/cdhash.h>

/* ----------------------------------------------------------------------
 *  Constants
 * -------------------------------------------------------------------- */
#define CSMAGIC_EMBEDDED_SIGNATURE      0xfade0cc0
#define CSMAGIC_CODEDIRECTORY           0xfade0c02
#define CSSLOT_CODEDIRECTORY            0
#define CS_HASHTYPE_SHA256              2
#define CS_HASHTYPE_SHA256_TRUNCATED    3

/* ----------------------------------------------------------------------
 *  Types
 * -------------------------------------------------------------------- */
typedef struct __BlobIndex {
    uint32_t type;
    uint32_t offset;
} CS_BlobIndex;

typedef struct __SuperBlob {
    uint32_t magic;
    uint32_t length;
    uint32_t count;
    CS_BlobIndex index[];
} CS_SuperBlob;

typedef struct __CodeDirectory {
    uint32_t magic;
    uint32_t length;
    uint32_t version;
    uint32_t flags;
    uint32_t hashOffset;
    uint32_t identOffset;
    uint32_t nSpecialSlots;
    uint32_t nCodeSlots;
    uint32_t codeLimit;
    uint8_t  hashSize;
    uint8_t  hashType;
    uint8_t  platform;
    uint8_t  pageSize;
    uint32_t spare2;
    // v0x20200+
    uint32_t scatterOffset;
    uint32_t teamOffset;
    // v0x20300+
    uint32_t spare3;
    uint64_t codeLimit64;
    // v0x20400+
    uint64_t execSegBase;
    uint64_t execSegLimit;
    uint64_t execSegFlags;
} CS_CodeDirectory;

/* ----------------------------------------------------------------------
 *  Functions
 * -------------------------------------------------------------------- */
char *cdhash_of_hdr(const uint8_t *base,
                    size_t size)
{
    const uint8_t *mach_header = base;
    uint32_t magic = *(uint32_t *)base;
    if(magic == FAT_CIGAM ||
       magic == FAT_MAGIC ||
       magic == FAT_CIGAM_64 ||
       magic == FAT_MAGIC_64)
    {
        struct fat_header *fat = (struct fat_header *)base;
        uint32_t n_arches = OSSwapBigToHostInt32(fat->nfat_arch);
        struct fat_arch *arches = (struct fat_arch *)(base + sizeof(struct fat_header));
        for(uint32_t i = 0; i < n_arches; i++)
        {
            cpu_type_t cputype = OSSwapBigToHostInt32(arches[i].cputype);
            if(cputype == CPU_TYPE_ARM64)
            {
                mach_header = base + OSSwapBigToHostInt32(arches[i].offset);
                break;
            }
        }
    }
    char *result = NULL;

    int is64 = (*(uint32_t *)mach_header == MH_MAGIC_64);
    uint32_t ncmds = is64 ? ((struct mach_header_64 *)mach_header)->ncmds : ((struct mach_header *)mach_header)->ncmds;

    const uint8_t *cmd = mach_header + (is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header));

    for(uint32_t i = 0; i < ncmds; i++)
    {
        struct load_command *lc = (struct load_command *)cmd;

        if(lc->cmd == LC_CODE_SIGNATURE)
        {
            struct linkedit_data_command *sig_cmd = (struct linkedit_data_command *)cmd;
            CS_SuperBlob *super_blob = (CS_SuperBlob *)(mach_header + sig_cmd->dataoff);

            if(OSSwapBigToHostInt32(super_blob->magic) != CSMAGIC_EMBEDDED_SIGNATURE)
            {
                goto done;
            }

            uint32_t count = OSSwapBigToHostInt32(super_blob->count);
            for(uint32_t j = 0; j < count; j++)
            {
                uint32_t type   = OSSwapBigToHostInt32(super_blob->index[j].type);
                uint32_t offset = OSSwapBigToHostInt32(super_blob->index[j].offset);

                if(type == CSSLOT_CODEDIRECTORY)
                {
                    CS_CodeDirectory *cd = (CS_CodeDirectory *)((uint8_t *)super_blob + offset);

                    if(OSSwapBigToHostInt32(cd->magic) != CSMAGIC_CODEDIRECTORY)
                    {
                        goto done;
                    }
                    
                    uint32_t cd_length = OSSwapBigToHostInt32(cd->length);
                    uint8_t hash_type  = cd->hashType;

                    if(hash_type == CS_HASHTYPE_SHA256 ||
                       hash_type == CS_HASHTYPE_SHA256_TRUNCATED)
                    {
                        result = malloc(CC_SHA256_DIGEST_LENGTH);
                        if(!result)
                        {
                            goto done;
                        }
                        CC_SHA1(cd, cd_length, (unsigned char*)result);
                    }
                    else
                    {
                        result = malloc(CC_SHA1_DIGEST_LENGTH);
                        if(!result)
                        {
                            goto done;
                        }
                        CC_SHA1(cd, cd_length, (unsigned char*)result);
                    }
                    goto done;
                }
            }
        }
        cmd += lc->cmdsize;
    }

done:
    return result;
}

char *cdhash_of_fd(int fd)
{
    struct stat st;
    if(fstat(fd, &st) != 0)
    {
        return NULL;
    }

    size_t size = (size_t)st.st_size;
    if(size == 0)
    {
        return NULL;
    }

    uint8_t *base = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    if(base == MAP_FAILED)
    {
        return NULL;
    }
    
    char *result = cdhash_of_hdr(base, size);
    munmap(base, size);
    return result;
}
