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

#import <dlfcn.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <LindChain/ProcEnvironment/litehook/litehook.h>
#import <LindChain/ProcEnvironment/Shims/environment.h>
#import <LindChain/ProcEnvironment/Shims/proxy.h>
#import <LindChain/ProcEnvironment/Shims/posix_spawn.h>
#import <LindChain/ProcEnvironment/Surface/surface.h>
#import <LindChain/ProcEnvironment/PEFileTable.h>
#import <LindChain/ServiceKit/Service.h>
#import <LindChain/Services/applicationmgmtd/LDEApplicationWorkspaceInternal.h>
#import <ResecureDecoder.h>
#import <LiveShim/LiveShimSyscall.h>
#import <LiveShim/dyld.h>
#import <ksurface_config.h>

bool performHookDyldApi(const char* functionName, uint32_t adrpOffset, void** origFunction, void* hookFunction);

static NSExtensionContext *lcExtensionContext;

@interface LiveProcessHandler : NSObject<NSExtensionRequestHandling>

@end

@implementation LiveProcessHandler

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context
{
    lcExtensionContext = context;
    /* returns control back to LiveContainerMain */
    CFRunLoopStop(CFRunLoopGetMain());
}

@end

extern char **environ;
void clear_environment(void)
{
    while(environ[0] != NULL)
    {
        char *eq = strchr(environ[0], '=');
        if(eq)
        {
            size_t len = eq - environ[0];
            char key[len + 1];
            strncpy(key, environ[0], len);
            key[len] = '\0';
            
            if(unsetenv(key) != 0)
            {
                environ++;
            }
        }
        else
        {
            environ++;
        }
    }
}

void overwriteEnvironmentProperties(NSDictionary *enviroDict)
{
    if(enviroDict)
    {
        clear_environment();
        
        for (NSString *key in enviroDict)
        {
            NSString *value = enviroDict[key];
            setenv([key UTF8String], [value UTF8String], 0);
        }
    }
}

void overwriteArguments(NSArray<NSObject<NSSecureCoding,NSCopying>*> *arguments,
                        int *argc,
                        char ***argv)
{
    assert(argc != NULL && argv != NULL);
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    [NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:arguments ? arguments : @[]];
#pragma clang diagnostic pop
    
    if(!arguments || arguments.count < 1)
    {
        *argc = 0;
        return;
    }
    
    NSInteger count = arguments.count;
    *argc = (int)count;
    
    *argv = malloc(sizeof(char *) * (count + 1));
    for(NSInteger i = 0; i < count; i++)
    {
        NSObject<NSSecureCoding,NSCopying> *arg = arguments[i];
        
        if([arg isKindOfClass:[NSString class]])
        {
            (*argv)[i] = strdup(((NSString*)arg).UTF8String);
        }
    }
    (*argv)[count] = NULL;
}

int LiveProcessMain(int argc, char *argv[])
{
    /* let NSExtensionContext initialize, once it's done it will call CFRunLoopStop */
    CFRunLoopRun();
    NSDictionary *appInfo = [lcExtensionContext.inputItems.firstObject userInfo];
    
#if !DEBUG
    /* destroying payload once MARK: this is removed in debug mode to easier test vulnerabilities  */
    lcExtensionContext = nil;
#endif /* !DEBUG */
    
    NSXPCListenerEndpoint* endpoint = appInfo[@"PEEndpoint"];
    NSString* executablePath = appInfo[@"PEExecutablePath"];
    NSString *service = appInfo[@"PEIntegratedServiceClass"];
    NSDictionary *environmentDictionary = appInfo[@"PEEnvironment"];
    NSArray *argumentDictionary = appInfo[@"PEArguments"];
    PEFileTable *fileTable = appInfo[@"PEFileTable"];
    PEMachPort *syscallPort = appInfo[@"PESyscallPort"];
    NSString *workingDirectory = appInfo[@"PEWorkingDirectory"];
    uid_t serviceUserIdentifier = [appInfo[@"PEUserIdentifier"] unsignedIntValue];
    gid_t serviceGroupIdentifier = [appInfo[@"PEGroupIdentifier"] unsignedIntValue];
    
    /* for the start */
    NSDictionary *filePermissions = appInfo[@"PEFilePermissions"];
    for(NSData *filePermission in filePermissions)
    {
        extern int64_t sandbox_extension_consume(const char *token);
        int64_t handle = sandbox_extension_consume((const char *)filePermission.bytes);
        if(handle < 0)
        {
            return 1;
        }
    }
    
    /* destroy the payload once in for all */
    appInfo = nil;
    
    assert(endpoint != nil && executablePath != nil && syscallPort != nil);
    
    /* setting working directory correctly */
    if(workingDirectory != nil &&
       [workingDirectory isKindOfClass:[NSString class]])
    {
        /* was passed, setting to destination */
        chdir([workingDirectory UTF8String]);
    }
    else
    {
        /* wasnt passed, setting to root */
        chdir([[NSHomeDirectory() stringByAppendingPathComponent:@"/Documents"] UTF8String]);
    }
    
    if([fileTable isKindOfClass:[PEFileTable class]])
    {
        /* apply file descriptor map passed from host environment */
        [fileTable apply];
        setvbuf(stdout, NULL, _IONBF, 0);
        setvbuf(stderr, NULL, _IONBF, 0);
    }
    
    /*
     * connecting to the host environment which serves
     * the guest environment.
     */
    environment_client_connect_to_host(endpoint);   /* will soon vanish */
    environment_client_connect_to_syscall_proxy(syscallPort);
    
    /* overwriting environment and arguments */
    overwriteEnvironmentProperties(environmentDictionary);
    overwriteArguments(argumentDictionary, &argc, &argv);
    
#if DEBUG
    setenv("DYLD_MMAP_SANDBOX_EXEC_ALLOWED_PATH", dyld_get_mmap_sandbox_map_exec_allowed_path(), 0);
#endif /* DEBUG */
    
    /* for integrated launch services */
    if(service != nil)
    {
        if(![service isKindOfClass:[NSString class]])
        {
            /* type validation failure */
            return 1;
        }
        
        Class ServiceClass = NSClassFromString(service);
        if(ServiceClass == nil ||
           ![ServiceClass conformsToProtocol:@protocol(PEServiceProtocol)])
        {
            /* class protocol validation failure */
            return 1;
        }
        
        /*
         * custom execution, because daemons arent dylibified
         * executables yet but its a TODO already to dylibify
         * them and separate them more from Nyxians main
         * codebase.
         */
        environment_init(EnvironmentExecCustom, executablePath, argc, argv);

#if KSURFACE_SYS_UCRED_ENABLED
        /*
         * first ever step is to elevate their permitives as
         * they are usually platformized, but they shall also
         * gain higher permitives.
         */
        if(liveshim_syscall(SYS_setgid, serviceGroupIdentifier) != 0 ||
           liveshim_syscall(SYS_setuid, serviceUserIdentifier) != 0)
        {
            return 1;
        }
#endif /* KSURFACE_SYS_UCRED_ENABLED */
        
#if DEBUG
        NSLog(@"ping");
#endif /* DEBUG */
        
        /*
         * we get the class of the daemon, internal Nyxian
         * daemons name their class within their launch
         * service file.
         */
        return PEServiceMain(argc, argv, ServiceClass);
    }
    else
    {
        /*
         * path for normal spawns (they go through LC, thanks to
         * Duy Tran and his research <3), anyways this goes through
         * LC and when the main symbol returns then we get its return
         * value which we redirect to the env.
         */
        return environment_init(EnvironmentExecLiveContainer, executablePath, argc, argv);
    }
    
    return 1;
}

/* this is our fake UIApplicationMain called from _xpc_objc_uimain (xpc_main) */
__attribute__((visibility("default")))
int UIApplicationMain(int argc, char * argv[], NSString * principalClassName, NSString * delegateClassName)
{
    exit(LiveProcessMain(argc, argv));
}

/* literally redirecting UIApplicationMain to our own one */
DEFINE_HOOK(dlsym, void*, (void* dyldApiInstancePtr, void* handle, const char* symbol))
{
    /* checking if process is looking for it */
    if(symbol && !strcmp(symbol, "UIApplicationMain"))
    {
        performHookDyldApi("dlsym", 2, (void**)&orig_dlsym, orig_dlsym);
        return (void*)&UIApplicationMain;   /* should not break jailbreak compatibility */
    }
    
    /* pass it to the real one */
    __attribute__((musttail)) return orig_dlsym(dyldApiInstancePtr, handle, symbol);
}

/* Extension entry point */
int NSExtensionMain(int argc, char * argv[])
{
    /* resecure decoder, instead of bluntly removing validation entirely */
    ResecureDecoder();
    
    /*
     * hook dlopen to catch UIKit framework load and trick it
     * into thinking that our UIApplicationMain is the real
     * legitimate one
     */
    performHookDyldApi("dlsym", 2, (void**)&ORIG_FUNC(dlsym), HOOK_FUNC(dlsym));
    
    /*
     * call the real NSExtensionMain, which calls
     * then our UIApplicationMain.
     */
    int (*orig_NSExtensionMain)(int argc, char * argv[]) = dlsym(RTLD_NEXT, "NSExtensionMain");
    return orig_NSExtensionMain(argc, argv);
}
