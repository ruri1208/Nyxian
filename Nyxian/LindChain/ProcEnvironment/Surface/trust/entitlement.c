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
#include <assert.h>

/* ----------------------------------------------------------------------
 *  Project Headers
 * -------------------------------------------------------------------- */
#include <LindChain/ProcEnvironment/Surface/trust/entitlement.h>
#include <LindChain/ProcEnvironment/Surface/proc/proc.h>
#include <LindChain/ProcEnvironment/Surface/key.h>
#include <LindChain/ProcEnvironment/Surface/trust/trust.h>
#include <OpenSSL/evp.h>
#include <OpenSSL/err.h>
#include <OpenSSL/ec.h>
#include <OpenSSL/pem.h>
#include <ksurface_config.h>

/* foundational */
NXT2Entitlement const kNXT2EntitlementPlatform = CFSTR("org.emexlabs.nyxian.platform");
NXT2Entitlement const kNXT2EntitlementPlatformRoot = CFSTR("org.emexlabs.nyxian.platform-root");
NXT2Entitlement const kNXT2EntitlementPlatformUser = CFSTR("org.emexlabs.nyxian.platform.user");
NXT2Entitlement const kNXT2EntitlementPlatformGroup = CFSTR("org.emexlabs.nyxian.platform.group");
NXT2Entitlement const kNXT2EntitlementGetTaskAllow = CFSTR("org.emexlabs.nyxian.get-task-allow");
NXT2Entitlement const kNXT2EntitlementTaskForPid = CFSTR("org.emexlabs.nyxian.task-for-pid");
NXT2Entitlement const kNXT2EntitlementSUGID = CFSTR("org.emexlabs.nyxian.sugid");
NXT2Entitlement const kNXT2EntitlementSystemTaskPorts = CFSTR("org.emexlabs.nyxian.system-task-ports");

/* dyld */
NXT2Entitlement const kNXT2EntitlementDYLDHideLP = CFSTR("org.emexlabs.nyxian.dyld.hide-live-process");

/* process */
NXT2Entitlement const kNXT2EntitlementProcessEnumeration = CFSTR("org.emexlabs.nyxian.process.enumeration");
NXT2Entitlement const kNXT2EntitlementProcessKill = CFSTR("org.emexlabs.nyxian.process.kill");
NXT2Entitlement const kNXT2EntitlementProcessSpawn = CFSTR("org.emexlabs.nyxian.process.spawn");
NXT2Entitlement const kNXT2EntitlementProcessSpawnSignedOnly = CFSTR("org.emexlabs.nyxian.process.spawn.signed-only");
NXT2Entitlement const kNXT2EntitlementProcessSpawnInheriteEntitlements = CFSTR("org.emexlabs.nyxian.process.spawn.inherite-entitlements");

/* management */
NXT2Entitlement const kNXT2EntitlementManagementHost = CFSTR("org.emexlabs.nyxian.management.host");
NXT2Entitlement const kNXT2EntitlementManagementProcEnvironment = CFSTR("org.emexlabs.nyxian.management.proc-environment");

/* launch services */
NXT2Entitlement const kNXT2EntitlementLaunchServicesStart = CFSTR("org.emexlabs.nyxian.launch-services.start");
NXT2Entitlement const kNXT2EntitlementLaunchServicesStop = CFSTR("org.emexlabs.nyxian.launch-services.stop");
NXT2Entitlement const kNXT2EntitlementLaunchServicesToggle = CFSTR("org.emexlabs.nyxian.launch-services.toggle");
NXT2Entitlement const kNXT2EntitlementLaunchServicesGetEndpoint = CFSTR("org.emexlabs.nyxian.launch-services.get-endpoint");
NXT2Entitlement const kNXT2EntitlementLaunchServicesSetEndpoint = CFSTR("org.emexlabs.nyxian.launch-services.set-endpoint");
NXT2Entitlement const kNXT2EntitlementLaunchServicesGetEndpointAllowList = CFSTR("org.emexlabs.nyxian.launch-services.get-endpoint.allow-list");
NXT2Entitlement const kNXT2EntitlementLaunchServicesSetEndpointAllowList = CFSTR("org.emexlabs.nyxian.launch-services.set-endpoint.allow-list");

/* sandbox */
NXT2Entitlement const kNXT2EntitlementSandboxFileRead = CFSTR("org.emexlabs.nyxian.sandbox.file.read");
NXT2Entitlement const kNXT2EntitlementSandboxFileReadWrite = CFSTR("org.emexlabs.nyxian.sandbox.file.read-write");
NXT2Entitlement const kNXT2EntitlementSandboxNoContainer = CFSTR("org.emexlabs.nyxian.sandbox.no-container");

kern_return_t entitlement_token_mach_gen(ksurface_nxtr_blob_t *blob,
                                         const char *cdhash,
                                         PEEntitlement entitlement)
{
    blob->entitlement = entitlement;
    
    /* copy cdhash and entitlements over */
    if(cdhash != NULL)
    {
        memcpy((void*)(blob->cdhash), cdhash, USER_FSIGNATURES_CDHASH_LEN);
    }
    else
    {
        /* dont sign at all (just containing entitlements) */
        bzero((void*)(blob->cdhash), USER_FSIGNATURES_CDHASH_LEN);
        return KERN_SUCCESS;
    }
    
    /* generating nonce so it's harder to crack */
    arc4random_buf(&(blob->nonce), sizeof(uint64_t));

    /* signing blob */
    const uint8_t *p = ksurface->priv_key;
    EVP_PKEY *priv = d2i_PrivateKey(EVP_PKEY_EC, NULL, &p, (long)ksurface->priv_key_len);
    if(!priv)
    {
        return KERN_FAILURE;
    }
    
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    if(!mdctx)
    {
        EVP_PKEY_free(priv);
        return KERN_FAILURE;
    }
    
    if(EVP_DigestSignInit(mdctx, NULL, EVP_sha256(), NULL, priv) != 1)
    {
        EVP_MD_CTX_free(mdctx);
        EVP_PKEY_free(priv);
        return KERN_FAILURE;
    }

    size_t mac_len = sizeof(blob->mac);
    if(EVP_DigestSign(mdctx, blob->mac, &mac_len, (unsigned char*)blob, offsetof(ksurface_nxtr_blob_t, mac)) != 1)
    {
        EVP_MD_CTX_free(mdctx);
        EVP_PKEY_free(priv);
        return KERN_FAILURE;
    }
    blob->mac_len = mac_len;
    
    EVP_MD_CTX_free(mdctx);
    EVP_PKEY_free(priv);
    
    return KERN_SUCCESS;
}

kern_return_t entitlement_mach_verify(ksurface_nxtr_result_t *mach,
                                      uint8_t *pub_key,
                                      size_t pub_key_len)
{
    assert(mach != NULL);
    
    /* the blob's mac length can never exceed the size of mach->blob.mac */
    if(mach->blob.mac_len > sizeof(mach->blob.mac))
    {
        return KERN_DENIED;
    }
    
    /* verify signature from blob */
    const uint8_t *p = pub_key;
    EVP_PKEY *pub = d2i_PUBKEY(NULL, &p, pub_key_len);
    if(!pub)
    {
        return KERN_DENIED;
    }
    
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    if(!mdctx)
    {
        EVP_PKEY_free(pub);
        return KERN_DENIED;
    }
    
    if(EVP_DigestVerifyInit(mdctx, NULL, EVP_sha256(), NULL, pub) != 1)
    {
        EVP_MD_CTX_free(mdctx);
        EVP_PKEY_free(pub);
        return KERN_DENIED;
    }
    
    int ret = EVP_DigestVerify(mdctx, mach->blob.mac, mach->blob.mac_len, (unsigned char *)&mach->blob, offsetof(ksurface_nxtr_blob_t, mac));
    
    EVP_MD_CTX_free(mdctx);
    EVP_PKEY_free(pub);
    
    if(ret != 1)
    {
        return KERN_DENIED;
    }
    
    mach->blob_valid = true;
    if(!mach->cdhash_valid)
    {
        return KERN_DENIED;
    }
    
    return KERN_SUCCESS;
}

PEEntitlement entitlement_get_path(const char *path,
                                   bool *wasLocallySigned)
{
    ksurface_nxtr_result_t mach;
    if(trust_nxtr_read(path, &mach) != KERN_SUCCESS)
    {
        *wasLocallySigned = false;
        return kPEEntitlementNone;
    }
    
    kern_return_t kr = entitlement_mach_verify(&mach, ksurface->pub_key, ksurface->pub_key_len);
    *wasLocallySigned = (kr == KERN_SUCCESS);
    return mach.blob.entitlement;
}

bool entitlement_set_path(const char *path,
                          PEEntitlement entitlement)
{
    int fd = open(path, O_RDWR);
    if(fd < 0)
    {
        return false;
    }
    
    kern_return_t kr = trust_nxtr_sign_fd(fd, entitlement);
    fsync(fd);
    close(fd);
    return (kr == KERN_SUCCESS);
}

#if KSURFACE_CS_SANITIZE_ENTITLEMENTS
PEEntitlement entitlement_sanitize(PEEntitlement base)
{
    base &= kPEEntitlementAll;  /* making sure no unused bit fields are enabled */
    
    /* can it see a other process ever? */
    if(!entitlement_got_entitlement(base, kPEEntitlementProcessSpawn) &&
       !entitlement_got_entitlement(base, kPEEntitlementProcessSpawnSignedOnly) &&
       !entitlement_got_entitlement(base, kPEEntitlementProcessEnumeration))
    {
        /* you cannot do much when you cannot see the target */
        entitlement_strip(base, kPEEntitlementTaskForPid | kPEEntitlementProcessKill);
    }
    
    /* can it spawn a other process ever? */
    if(!entitlement_got_entitlement(base, kPEEntitlementProcessSpawn) &&
       !entitlement_got_entitlement(base, kPEEntitlementProcessSpawnSignedOnly))
    {
        entitlement_strip(base, kPEEntitlementProcessSpawnInheriteEntitlements);
    }
    
    /* can it be platform root? */
    if(entitlement_got_entitlement(base, kPEEntitlementPlatformRoot) &&
       !entitlement_got_entitlement(base, kPEEntitlementPlatform))
    {
        /* you cannot be platformized as root user if you're not platform */
        entitlement_strip(base, kPEEntitlementPlatformRoot);
    }
    return base;
}
#endif /* KSURFACE_CS_SANITIZE_ENTITLEMENTS */
