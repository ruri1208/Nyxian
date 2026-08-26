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

#import "LDEApplicationWorkspace.h"
#import <LindChain/Private/FoundationPrivate.h>
#import <LindChain/ProcEnvironment/Server/Server.h>
#import <LindChain/ProcEnvironment/PEArchiveHandle.h>
#import <LindChain/Utils/Zip.h>
#if __has_include(<Nyxian-Swift.h>)
#define LIVEPROCESS 0
#import <Nyxian-Swift.h>
#import <LindChain/ProcEnvironment/PELaunchServiceManager.h>
#else
#include <ksurface_config.h>
#include <ksurface_abi.h>
#import <Frameworks/LiveShim/LiveShimSyscall.h>
#define LIVEPROCESS 1
#endif /* __has_include(<Nyxian-Swift.h>) */

@interface LDEApplicationWorkspace ()

@property (nonatomic) dispatch_semaphore_t syncSema;
@property (nonatomic) BOOL syncDone;
@property (nonatomic,strong) NSMutableDictionary<NSString*,LDEApplicationObject*> *applications;

@end

@implementation LDEApplicationWorkspace

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        _syncSema = dispatch_semaphore_create(0);
        _applications = [[NSMutableDictionary alloc] init];
    }
    return self;
}

+ (instancetype)shared
{
    static LDEApplicationWorkspace *applicationWorkspaceSingleton = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        applicationWorkspaceSingleton = [[LDEApplicationWorkspace alloc] init];
    });
    return applicationWorkspaceSingleton;
}

- (BOOL)connect
{
    if(_connection != NULL && _connection.processIdentifier != 0)
    {
        return YES;
    }
    
#if !LIVEPROCESS
    PELaunchServiceManager *serviceManager = [PELaunchServiceManager shared];
    _connection = [serviceManager connectToService:@"org.emexlabs.bootstrapd" protocol:@protocol(LDEApplicationWorkspaceProxyProtocol) observer:self observerProtocol:@protocol(LDEApplicationWorkspaceProtocol)];
    return _connection != nil;
#else
    extern NSObject<OS_xpc_object> *xpc_endpoint_create_mach_port_4sim(mach_port_t port);
    
    mach_port_t bootstrapd_port;
    if(liveshim_syscall(SYS_pectl, kPECTLCategoryLaunchService, kPECTLLaunchServiceGetEndpoint, "org.emexlabs.bootstrapd", NULL, MACH_PORT_NULL, &bootstrapd_port) != 0)
    {
        NSLog(@"failed looking up org.emexlabs.bootstrapd port: %s", strerror(errno));
        dispatch_semaphore_signal(_syncSema);   /* no permission */
        return NO;
    }
    
    NSXPCListenerEndpoint *endpoint = [[NSXPCListenerEndpoint alloc] init];
    endpoint._endpoint = xpc_endpoint_create_mach_port_4sim(bootstrapd_port);
    if(endpoint == nil || endpoint._endpoint == nil)
    {
        NSLog(@"failed craft NSXPCListenerEndpoint for org.emexlabs.bootstrapd port");
        dispatch_semaphore_signal(_syncSema);   /* something terrible happened? */
        return NO;
    }
    
    _connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
    if(_connection)
    {
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(LDEApplicationWorkspaceProxyProtocol)];
        _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(LDEApplicationWorkspaceProtocol)];
        _connection.exportedObject = self;
        [_connection resume];
    }
#endif /* !LIVEPROCESS */
    return _connection != nil;
}

- (void)ping
{
    [self connect];
    
    [_connection.remoteObjectProxy ping];
}

- (BOOL)installApplicationAtBundlePath:(NSString*)bundlePath
{
    [self connect];
    
    __block BOOL result = NO;
    PEArchiveHandle *archiveObject = [PEArchiveHandle objectForDirectoryAtPath:bundlePath];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [proxy installApplicationWithArchiveHandle:archiveObject withReply:^(BOOL replyResult){
            result = replyResult;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return result;
}

- (BOOL)installApplicationAtPackagePath:(NSString*)packagePath
{
    [self connect];
    
    __block BOOL result = NO;
    PEArchiveHandle *handle = [PEArchiveHandle handleForFileAtPath:packagePath];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [proxy installApplicationWithArchiveHandle:handle withReply:^(BOOL replyResult){
            result = replyResult;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return result;
}

- (BOOL)deleteApplicationWithBundleID:(NSString *)bundleID
{
    [self connect];
    
    __block BOOL result = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [proxy deleteApplicationWithBundleID:bundleID withReply:^(BOOL replyResult){
            result = replyResult;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    return result;
}

- (BOOL)applicationInstalledWithBundleID:(NSString *)bundleID
{
    [self connect];
    
    __block BOOL result = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [proxy applicationInstalledWithBundleID:bundleID withReply:^(BOOL replyResult){
            result = replyResult;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    return result;
}

- (LDEApplicationObject*)applicationObjectForBundleID:(NSString*)bundleID
{
    [self connect];
    
    __block LDEApplicationObject *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [_connection.remoteObjectProxy applicationObjectForBundleID:bundleID withReply:^(LDEApplicationObject *replyResult){
            result = replyResult;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    return result;
}

- (NSArray<LDEApplicationObject*>*)allApplicationObjects
{
    [self connect];
    
    BOOL done;
    @synchronized(self)
    {
        done = self.syncDone;
    }
    if(!done)
    {
        dispatch_semaphore_wait(self.syncSema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)));
    }
    
    @synchronized(self.applications) {
        return [_applications.allValues copy];
    }
}

- (BOOL)clearContainerForBundleID:(NSString *)bundleID
{
    [self connect];
    
    __block BOOL result = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [_connection.remoteObjectProxy clearContainerForBundleID:bundleID withReply:^(BOOL replyResult){
            result = replyResult;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    return result;
}

- (NSString*)fastpathUtility:(NSString*)utilityPath
{
    [self connect];
    
    __block NSString *fastpath = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [_connection.remoteObjectProxy fastpathUtility:[PEFileHandle handleForFileAtPath:utilityPath] withName:[utilityPath lastPathComponent] withReply:^(NSString *fastPathRet, BOOL fastSigned){
            fastpath = fastSigned ? fastPathRet : nil;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    return fastpath;
}

- (LDEApplicationObject*)applicationObjectForExecutablePath:(NSString*)executablePath
{
    [self connect];
    
    __block LDEApplicationObject *application = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [_connection.remoteObjectProxy applicationObjectForExecutablePath:executablePath withReply:^(LDEApplicationObject *applicationReply){
            application = applicationReply;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    return application;
}

- (NSString*)utilityHomePath
{
    [self connect];
    
    __block NSString *utilityHomePath = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [_connection.remoteObjectProxy utilityHomePathWithReply:^(NSString *reply){
            utilityHomePath = reply;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    return utilityHomePath;
}

- (void)applicationInitialPopulationDone
{
    @synchronized(self)
    {
        self.syncDone = YES;
    }
    dispatch_semaphore_signal(self.syncSema);
}

- (void)applicationWasInstalled:(LDEApplicationObject*)app
{
    @synchronized(self.applications)
    {
        [self.applications setObject:app forKey:app.bundleIdentifier];
    }
#if !LIVEPROCESS
    dispatch_async(dispatch_get_main_queue(), ^{
        [[ApplicationManagementViewController shared] applicationWasInstalled:app];
    });
#endif /* !LIVEPROCESS */
    
}

- (void)applicationWithBundleIdentifierWasUninstalled:(NSString*)bundleIdentifier
{
    @synchronized(self.applications)
    {
        [self.applications removeObjectForKey:bundleIdentifier];
    }
#if !LIVEPROCESS
    dispatch_async(dispatch_get_main_queue(), ^{
        [[ApplicationManagementViewController shared] applicationWithBundleIdentifierWasUninstalled:bundleIdentifier];
    });
#endif /* !LIVEPROCESS */
}

@end
