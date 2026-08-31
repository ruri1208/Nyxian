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

#include <LindChain/ProcEnvironment/Surface/kxld/validation.h>

bool KXValidateCodeSignature(LCMachO *machO)
{
    /* binary must be signed, otherwise no execution */
    struct code_signature_command* codeSignatureCommand = findSignatureCommand(machO->header);
    if(!codeSignatureCommand)
    {
        errno = EPERM;
        return false;
    }
    
    /* checking if the kernel says this is signed */
    off_t sliceOffset = (uint8_t*)machO->header - (uint8_t*)machO->map;
    fsignatures_t siginfo;
    siginfo.fs_file_start = sliceOffset;
    siginfo.fs_blob_start = (void*)(long)(codeSignatureCommand->dataoff);
    siginfo.fs_blob_size = codeSignatureCommand->datasize;
    int addFileSigsReault = fcntl(machO->fd, F_ADDFILESIGS_RETURN, &siginfo);
    if(addFileSigsReault == -1)
    {
        errno = EPERM;
        return false;
    }
    
    /* checking if this can be executed by us */
    fchecklv_t checkInfo;
    checkInfo.lv_error_message_size = 0;
    checkInfo.lv_error_message = NULL;
    checkInfo.lv_file_start= sliceOffset;
    int checkLVresult = fcntl(machO->fd, F_CHECK_LV, &checkInfo);
    if(checkLVresult != 0)
    {
        errno = EPERM;
        return false;
    }
    
    /* checking NXTR kext requirement */
    ksurface_nxt2_t result = {};
    if(trust_nxt2_read_fd(machO->fd, &result) != KERN_SUCCESS ||
       !result.isValid ||
       !result.isCdHashValid ||
       !result.isSigned)
    {
        if(result.entitlements != NULL)
        {
            CFRelease(result.entitlements);
        }
        errno = EPERM;
        return false;
    }
    if(CFDictionaryGetValue(result.entitlements, kNXT2EntitlementKsurfaceKEXTLoading) != kCFBooleanTrue)
    {
        CFRelease(result.entitlements);
        errno = EPERM;
        return false;
    }
    CFRelease(result.entitlements);
    
    return true;
}
