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

#import <LindChain/Utils/DynaMod.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCUtils.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>

unsigned char shellcode[] = {
    0x20, 0x00, 0x80, 0xd2,  // mov  x0, #1        (stdout)
    0xe1, 0x00, 0x00, 0x10,  // adr  x1, #28       (-> msg)
    0xc2, 0x01, 0x80, 0xd2,  // mov  x2, #14       (len)
    0x90, 0x00, 0x80, 0xd2,  // mov  x16, #4       (write)
    0x01, 0x10, 0x00, 0xd4,  // svc  #0x80
    0x00, 0x00, 0x80, 0xd2,  // mov  x0, #0
    0x40, 0x05, 0x80, 0xd2,  // mov  x0, #42
    0xc0, 0x03, 0x5f, 0xd6,  // ret
    0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x2c, 0x20,      // "Hello, "
    0x57, 0x6f, 0x72, 0x6c, 0x64, 0x21, 0x0a       // "World!\n"
};

unsigned char tim_shellcode[] = {
    0x20, 0x00, 0x80, 0xd2,  // mov  x0, #1        (stdout)
    0xe1, 0x00, 0x00, 0x10,  // adr  x1, #28       (-> msg)
    0xc2, 0x01, 0x80, 0xd2,  // mov  x2, #14       (len)
    0x90, 0x00, 0x80, 0xd2,  // mov  x16, #4       (write)
    0x01, 0x10, 0x00, 0xd4,  // svc  #0x80
    0x00, 0x00, 0x80, 0xd2,  // mov  x0, #0
    0x40, 0x05, 0x80, 0xd2,  // mov  x0, #42
    0xc0, 0x03, 0x5f, 0xd6,  // ret
    0x47, 0x6f, 0x6f, 0x64, 0x20, 0x6d, 0x6f, 0x72,  // "Good mor"  /* what does he say on every Apple WWDC xD */
    0x6e, 0x69, 0x6e, 0x67, 0x2e, 0x0a               // "ning.\n"
};

int dynamod_mprotect(void *addr,
                     size_t len,
                     int prot)
{
    if(prot & PROT_EXEC && !(prot & PROT_WRITE))
    {
        /* aligning */
        uintptr_t alignedAddr = (uintptr_t)addr & ~(uintptr_t)0x3FFF;
        size_t alignedLen = (len + 0x3FFF) & ~(size_t)0x3FFF;
        
        /* create MachO object file for it */
        NSData *data = MDKMachOObjectFileEmitWithText((void*)alignedAddr, alignedLen);
        NSLog(@"%@", data);
        
        /* emit MachO header */
        [data writeToURL:[[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@"/Documents/jit.macho"] atomically:YES];
        
        /* now we gotta link this shit */
        MDKJob *job = [MDKJob jobWithType:kCCJobTypeLinker withArguments:@[
            @"-arch",
            @"arm64",
            @"-platform_version",
            @"ios",
            @"18.0",
            @"18.0",
            @"-sectalign", @"__TEXT", @"__text", @"0x4000",
            @"-dylib",
            @"-o",
            [[[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@"/Documents/jit.dylib"] path],
            [[[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@"/Documents/jit.macho"] path],
        ]];
        
        NSArray<MDKDiagnostic*> *diagnostics;
        if(![job executeJobWithOutDiagnostics:&diagnostics withOutMainSource:nil])
        {
            for(MDKDiagnostic *diagnostic in diagnostics)
            {
                NSLog(@"%@", diagnostic.message);
            }
            goto do_fallback;
        }
        
        /* now we gotta sign that shit */
        NSURL *dylibURL = [[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@"/Documents/jit.dylib"];
        if(![LCUtils signMachOAtURL:dylibURL])
        {
            goto do_fallback;
        }
        NSLog(@"signed!");
        
        /* now we try to map it fast */
        LCMachO *machO = LCMapMachO(dylibURL.path.UTF8String, false);
        if(!machO)
        {
            goto do_fallback;
        }
        
        bool isAppleSigned = LCCheckCodeSignature(machO);   /* asks the XNU kernel nicely */
        if(!isAppleSigned)
        {
            LCUnmapMachO(machO);
            goto do_fallback;
        }
        
        NSLog(@"meaninglessly mapped!");
        
        const uint8_t *vptr = ((const uint8_t *)machO->header) + sizeof(struct mach_header_64);
        off_t sliceOffset = (uint8_t*)machO->header - (uint8_t*)machO->map;
        uint64_t ncmds = machO->header->ncmds;
        for(uint32_t i = 0; i < ncmds; i++)
        {
            const struct load_command *lc = (const struct load_command *)vptr;
            if(lc->cmd == LC_SEGMENT_64)
            {
                const struct segment_command_64 *sc = (const struct segment_command_64 *)vptr;
                if(sc->vmsize == 0)
                {
                    vptr += lc->cmdsize;
                    continue;
                }
                
                /* now a lot of math ^^ */
                off_t fileOff = sliceOffset + sc->fileoff;
                if(sc->initprot & VM_PROT_EXECUTE)
                {
                    /* executable mappings cannot be writable */
                    NSLog(@"found exec page!");
                    
                    if(sc->filesize > 0)
                    {
                        /*
                         * it doesn't matter where you map something, it will still be
                         * executable, even if the executable is not entirely mapped.
                         * which is crazy.
                         */
                        void *r = mmap((void*)alignedAddr, sc->filesize - VM_PAGE_SIZE, prot, MAP_FIXED | MAP_PRIVATE, machO->fd, fileOff + VM_PAGE_SIZE);
                        NSLog(@"mapped exec page at %p vs %p (first is JIT mapping location)", (void*)alignedAddr, r);
                    }
                    break;
                }
            }
            vptr += lc->cmdsize;
        }
        
        LCUnmapMachO(machO);
    }
do_fallback:
    return mprotect(addr, len, prot);
}

__attribute__((constructor))
void test(void)
{
    /* the JIT mapping basically */
    void *ptr = mmap(0, sizeof(shellcode), PROT_READ | PROT_WRITE,  MAP_ANON | MAP_PRIVATE, -1, 0);
    if(ptr == MAP_FAILED)
    {
        perror("mmap failed");
        return;
    }
    
    /* memcpy shellcode to pointer */
    memcpy(ptr, shellcode, sizeof(shellcode));
    
    /* create MachO object file for it */
    dynamod_mprotect(ptr, sizeof(shellcode), PROT_READ | PROT_EXEC);
    
    /* correctly mapped shall be executable and it does execute */
    int (*func)(void) = (int (*)(void))ptr;
    func();
    
    dynamod_mprotect(ptr, sizeof(shellcode), PROT_READ | PROT_WRITE);
    
    memcpy(ptr, tim_shellcode, sizeof(tim_shellcode));
    
    dynamod_mprotect(ptr, sizeof(shellcode), PROT_READ | PROT_EXEC);
    
    /* doesn't work yet */
    //func();
}
