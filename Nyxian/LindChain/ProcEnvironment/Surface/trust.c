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

#include <LindChain/ProcEnvironment/Surface/trust.h>
#include <LindChain/ProcEnvironment/Surface/entitlement.h>
#include <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#include <LindChain/ProcEnvironment/Surface/surface.h>
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
#include <OpenSSL/evp.h>
#include <OpenSSL/err.h>
#include <OpenSSL/ec.h>
#include <OpenSSL/pem.h>

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
    
    kern_return_t kr = nxtr_sign_fd(fd, entitlement);
    fsync(fd);
    close(fd);
    return kr;
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
    
    kern_return_t ret = nxtr_read_fd(fd, result);
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

kern_return_t nxt2_sign(const char *path,
                        CFDictionaryRef entitlements,
                        bool signBlob)
{
    int fd = open(path, O_RDWR);
    if(fd < 0)
    {
        return KERN_FAILURE;
    }
    
    kern_return_t kr = nxt2_sign_fd(fd, entitlements, signBlob);
    fsync(fd);
    close(fd);
    return kr;
}

kern_return_t nxt2_sign_fd(int fd,
                           CFDictionaryRef entitlements,
                           bool signBlob)
{
    LCMachO *machO = LCMapMachOFromFDRO(dup(fd));
    if(machO == NULL)
    {
        return KERN_FAILURE;
    }
    char *cdhash = cdhash_of_hdr((const uint8_t*)machO->header, machO->size);
    LCUnmapMachO(machO);
    
    /* find eof */
    char tag[4];
    off_t eof = lseek(fd, 0, SEEK_END);
    
    if(eof >= (off_t)(sizeof(ksurface_nxtr_blob_t) + sizeof(uint32_t) + 4))
    {
        read_at(fd, eof - 4, tag, 4);
        if(memcmp(tag, APPEND_TAG_NXT2, 4) == 0)
        {
            uint32_t data_len;
            read_at(fd, eof - 4 - sizeof(uint32_t), &data_len, sizeof(uint32_t));
            eof -= (off_t)(data_len + sizeof(uint32_t) + 4);
            ftruncate(fd, eof);
        }
    }
    
    if(lseek(fd, eof, SEEK_SET) < 0)
    {
        free(cdhash);
        return KERN_FAILURE;
    }
    
    if(ftruncate(fd, eof) < 0)
    {
        free(cdhash);
        return KERN_FAILURE;
    }
    
    /* generate nxt2 blob (nxt2 unlike nxtr requires us to do it our selves and not entitlements api) */
    CFDataRef entitlementsData = entitlement_dict_to_plist(entitlements);
    if(entitlementsData == NULL)
    {
        free(cdhash);
        return KERN_FAILURE;
    }
    CFIndex entitlementsDataLength = CFDataGetLength(entitlementsData);
    size_t header_size = sizeof(ksurface_nxt2_blob_header_t) + (size_t)entitlementsDataLength;
    
    /* allocating the blob header */
    ksurface_nxt2_blob_header_t *blob_header = calloc(1, header_size);
    if(blob_header == NULL)
    {
        CFRelease(entitlementsData);
        free(cdhash);
        return KERN_FAILURE;
    }
    
    /* writing entitlement data */
    memcpy((void*)blob_header->plist_data, CFDataGetBytePtr(entitlementsData), (size_t)entitlementsDataLength);
    blob_header->plist_len = (size_t)entitlementsDataLength;
    CFRelease(entitlementsData);
    
    ksurface_nxt2_blob_footer_t *blob_footer = NULL;
    size_t footer_size;
    
    /* signing blob if applicable */
    if(signBlob && cdhash != NULL)
    {
        /* sign blob mode requires cdhash */
        memcpy((void*)(blob_header->cdhash), cdhash, USER_FSIGNATURES_CDHASH_LEN);
        free(cdhash);
        
        /* generating nonce so it's harder to crack */
        arc4random_buf(&(blob_header->nonce), sizeof(uint64_t));
        
        /* signing blob */
        const uint8_t *p = ksurface->priv_key;
        EVP_PKEY *priv = d2i_PrivateKey(EVP_PKEY_EC, NULL, &p, (long)ksurface->priv_key_len);
        if(!priv)
        {
            free(blob_header);
            return KERN_FAILURE;
        }
        
        EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
        if(!mdctx)
        {
            free(blob_header);
            EVP_PKEY_free(priv);
            return KERN_FAILURE;
        }
        
        if(EVP_DigestSignInit(mdctx, NULL, EVP_sha256(), NULL, priv) != 1)
        {
            free(blob_header);
            EVP_MD_CTX_free(mdctx);
            EVP_PKEY_free(priv);
            return KERN_FAILURE;
        }
        
        size_t mac_len = 0;
        if(EVP_DigestSign(mdctx, NULL, &mac_len, (const unsigned char *)blob_header, header_size) != 1)
        {
            free(blob_header);
            EVP_MD_CTX_free(mdctx);
            EVP_PKEY_free(priv);
            return KERN_FAILURE;
        }
        
        if(mac_len > sizeof(blob_footer->mac))
        {
            free(blob_header);
            EVP_MD_CTX_free(mdctx);
            EVP_PKEY_free(priv);
            return KERN_FAILURE;
        }
        
        /* allocate the blob footer to hold the signature */
        footer_size = sizeof(ksurface_nxt2_blob_footer_t);
        blob_footer = calloc(1, sizeof(ksurface_nxt2_blob_footer_t) + mac_len);
        if(blob_footer == NULL)
        {
            free(blob_header);
            EVP_MD_CTX_free(mdctx);
            EVP_PKEY_free(priv);
            return KERN_FAILURE;
        }
        blob_footer->mac_len = mac_len;
        
        if(EVP_DigestSign(mdctx, blob_footer->mac, &mac_len, (const unsigned char *)blob_header, header_size) != 1)
        {
            free(blob_footer);
            free(blob_header);
            EVP_MD_CTX_free(mdctx);
            EVP_PKEY_free(priv);
            return KERN_FAILURE;
        }
        
        EVP_MD_CTX_free(mdctx);
        EVP_PKEY_free(priv);
    }
    else if(cdhash != NULL)
    {
        free(cdhash);
        free(blob_header);
        return KERN_NOT_SUPPORTED;
    }
    else
    {
        free(blob_header);
        return KERN_NOT_SUPPORTED;
    }
    
    /* write blob */
    if(write(fd, blob_header, header_size) != (ssize_t)header_size)
    {
        free(blob_footer);
        free(blob_header);
        return KERN_FAILURE;
    }
    
    if(write(fd, blob_footer, footer_size) != (ssize_t)footer_size)
    {
        free(blob_footer);
        free(blob_header);
        return KERN_FAILURE;
    }
    
    free(blob_footer);
    free(blob_header);
    
    /* write tag */
    uint32_t data_len = (uint32_t)(header_size + footer_size);
    if(header_size + footer_size > UINT32_MAX)
    {
        return KERN_FAILURE;
    }
    
    if(write(fd, &data_len, sizeof(uint32_t)) != (ssize_t)sizeof(uint32_t))
    {
        return KERN_FAILURE;
    }
    
    if(write(fd, APPEND_TAG_NXT2, 4) != 4)
    {
        return KERN_FAILURE;
    }
    
    fsync(fd);
    
    return KERN_SUCCESS;
}

kern_return_t nxt2_read(const char *path,
                        ksurface_nxt2_t *result)
{
    int fd = open(path, O_RDONLY);
    if(fd < 0)
    {
        return KERN_FAILURE;
    }
    
    kern_return_t kr = nxt2_read_fd(fd, result);
    close(fd);
    return kr;
}

kern_return_t nxt2_read_fd(int fd,
                           ksurface_nxt2_t *result)
{
    if(fd < 0)
    {
        return KERN_INVALID_ARGUMENT;
    }
    
    if(result == NULL)
    {
        return KERN_INVALID_ADDRESS;
    }
    
    result->isValid = false;
    result->isCdHashValid = false;
    result->isSigned = false;
    
    /* read nxt2 tag */
    char tag[4];
    uint32_t len = 0;
    
    if(lseek(fd, -4, SEEK_END) < 0)
    {
        return KERN_FAILURE;
    }
    if(read(fd, tag, 4) != 4)
    {
        return KERN_FAILURE;
    }
    
    if(memcmp(tag, APPEND_TAG_NXT2, 4) != 0)
    {
        return KERN_FAILURE;
    }
    
    /* read nxt2 length */
    if(lseek(fd, -8, SEEK_END) < 0)
    {
        return KERN_FAILURE;
    }
    if(read(fd, &len, sizeof(uint32_t)) != (ssize_t)sizeof(uint32_t))
    {
        return KERN_FAILURE;
    }
    
    /* check sizing */
    size_t min_blob = offsetof(ksurface_nxt2_blob_header_t, plist_data) + sizeof(ksurface_nxt2_blob_footer_t);
    if(len < min_blob)
    {
        /* NXT2 blob doesn't fit */
        return KERN_DENIED;
    }
    
    if(len > PAGE_SIZE)
    {
        /* could be a exhaustion attack */
        return KERN_DENIED;
    }
    
    if(lseek(fd, -(off_t)(8 + len), SEEK_END) < 0)
    {
        return KERN_FAILURE;
    }
    
    /* reading the blob */
    uint8_t *blob_buf = malloc(len);
    if(blob_buf == NULL)
    {
        return KERN_NO_SPACE;
    }
    
    if(read(fd, blob_buf, len) != (ssize_t)len)
    {
        free(blob_buf);
        return KERN_FAILURE;
    }
    
    /* now we get the footer and validate it */
    ksurface_nxt2_blob_footer_t *blob_footer = (ksurface_nxt2_blob_footer_t*)((blob_buf + len) - sizeof(ksurface_nxt2_blob_footer_t));
    if(blob_footer->mac_len > sizeof(blob_footer->mac))
    {
        free(blob_buf);
        return KERN_DENIED;
    }
    
    /* now we get the header and validate it */
    ksurface_nxt2_blob_header_t *blob_header = (ksurface_nxt2_blob_header_t*)blob_buf;
    size_t plist_gap_len = len - (offsetof(ksurface_nxt2_blob_header_t, plist_data) + sizeof(ksurface_nxt2_blob_footer_t));
    if(blob_header->plist_len > plist_gap_len)
    {
        free(blob_buf);
        return KERN_DENIED;
    }
    
    /* getting entitlements back */
    CFDataRef entitlementsData = CFDataCreate(kCFAllocatorDefault, (const UInt8*)blob_header->plist_data, (CFIndex)blob_header->plist_len);
    if(entitlementsData == NULL)
    {
        free(blob_buf);
        return KERN_NO_SPACE;
    }
    
    CFDictionaryRef entitlements = entitlement_plist_to_dict(entitlementsData);
    CFRelease(entitlementsData);
    if(entitlements == NULL)
    {
        free(blob_buf);
        return KERN_NO_SPACE;
    }
    
    result->isValid = true; /* everything parsed successfully */
    
    memcpy(result->cdhash, blob_header->cdhash, USER_FSIGNATURES_CDHASH_LEN);
    LCMachO *machO = LCMapMachOFromFDRO(fd);
    if(machO != NULL)
    {
        char *cdhash = cdhash_of_hdr((const uint8_t*)machO->header, machO->size);
        if(cdhash != NULL && memcmp(cdhash, result->cdhash, USER_FSIGNATURES_CDHASH_LEN) == 0)
        {
            result->isCdHashValid = true;
        }
        LCUnmapMachO(machO);
    }
    
    if(result->isCdHashValid && result->isValid)
    {
        /* cdhash and blob must be valid for signature check, some checks are not performed twice */
        const uint8_t *p = ksurface->pub_key;
        EVP_PKEY *pub = d2i_PUBKEY(NULL, &p, ksurface->pub_key_len);
        if(!pub)
        {
            goto signature_invalid;
        }
        
        EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
        if(!mdctx)
        {
            EVP_PKEY_free(pub);
            goto signature_invalid;
        }
        
        if(EVP_DigestVerifyInit(mdctx, NULL, EVP_sha256(), NULL, pub) != 1)
        {
            EVP_MD_CTX_free(mdctx);
            EVP_PKEY_free(pub);
            goto signature_invalid;
        }
        
        if(EVP_DigestVerify(mdctx, blob_footer->mac, blob_footer->mac_len, (unsigned char *)blob_header, offsetof(ksurface_nxt2_blob_header_t, plist_data) + blob_header->plist_len) == 1)
        {
            result->isSigned = true;
        }
        
        EVP_MD_CTX_free(mdctx);
        EVP_PKEY_free(pub);
    }
    
signature_invalid:
    
    free(blob_buf);
    
    result->entitlements = entitlements;
    return KERN_SUCCESS;
}

ksurface_trust_identity_t *trust_identity_create(const char *path)
{
    if(path == NULL)
    {
        errno = EINVAL;
        return NULL;
    }
    
    /* modern */
    ksurface_nxt2_t result_nxt2;
    if(nxt2_read(path, &result_nxt2) == KERN_SUCCESS)
    {
        ksurface_trust_identity_t *identity = malloc(sizeof(ksurface_trust_identity_t));
        if(identity == NULL)
        {
            errno = ENOMEM;
            return NULL;
        }
        
        memcpy(identity->cdhash, result_nxt2.cdhash, USER_FSIGNATURES_CDHASH_LEN);
        identity->entitlements = result_nxt2.entitlements;
        identity->isValid = result_nxt2.isValid;
        identity->isSigned = result_nxt2.isSigned;
        identity->isCdHashValid = result_nxt2.isCdHashValid;
        //identity->legacyEntitlements  TODO: need to convert them
        //identity->filePermission      TODO: need to assign them
        return identity;
    }
    
    /* legacy */
    ksurface_nxtr_result_t result_nxtr;
    if(nxtr_read(path, &result_nxtr) == KERN_SUCCESS)
    {
        ksurface_trust_identity_t *identity = malloc(sizeof(ksurface_trust_identity_t));
        if(identity == NULL)
        {
            errno = ENOMEM;
            return NULL;
        }
        
        memcpy(identity->cdhash, result_nxtr.blob.cdhash, USER_FSIGNATURES_CDHASH_LEN);
        //identity->entitlements    TODO: need to convert them
        identity->isValid = result_nxtr.blob_valid;
        identity->isSigned = result_nxtr.blob_valid;    /* the same thing on nxtr */
        identity->isCdHashValid = result_nxtr.cdhash_valid;
        identity->legacyEntitlements = result_nxtr.blob.entitlement;
        //identity->filePermission  TODO: need to convert them
        return identity;
    }
    
    /* unknown or unsigned? */
    errno = ENOTSUP;
    return NULL;
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
    if(identity->filePermission != NULL)
    {
        CFRelease(identity->filePermission);
    }
    free(identity);
}
