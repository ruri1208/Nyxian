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

#import <Foundation/Foundation.h>
#import <LindChain/Utils/Swizzle.h>
#import <LindChain/Private/UIKitPrivate.h>
#import <LindChain/Services/applicationmgmtd/LDEApplicationWorkspace.h>

/* WIP TO A HUGE EXTEND! */

@interface _LSDiskUsage : NSObject
@property (readonly, nullable, nonatomic) NSNumber *staticUsage;
@property (readonly, nullable, nonatomic) NSNumber *dynamicUsage;
@property (readonly, nullable, nonatomic) NSNumber *onDemandResourcesUsage;
@property (readonly, nullable, nonatomic) NSNumber *sharedUsage;
@end

@interface LSApplicationSpoofProxy : NSObject

@property (nonatomic, readonly) LDEApplicationObject *applicationObject;
@property (nonatomic, readonly) NSNumber *ODRDiskUsage;
@property (nonatomic, readonly) NSArray *UIBackgroundModes;
@property (nonatomic, readonly) NSArray *VPNPlugins;
@property (nonatomic, readonly) NSArray *activityTypes;
@property (getter=isAdHocCodeSigned, nonatomic, readonly) bool adHocCodeSigned;
@property (nonatomic, readonly) NSString *appIDPrefix;
@property (nonatomic, readonly) id appState;
@property (nonatomic, readonly) NSString *appStoreToolsBuildVersion;
@property (getter=isAppStoreVendable, nonatomic, readonly) bool appStoreVendable;
@property (nonatomic, readonly) NSArray *appTags;
@property (getter=isAppUpdate, nonatomic, readonly) bool appUpdate;
@property (nonatomic, readonly) NSString *applicationDSID;
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *applicationType;
@property (nonatomic, readonly) NSString *applicationVariant;
@property (getter=isArcadeApp, nonatomic, readonly) bool arcadeApp;
@property (nonatomic, readonly) NSArray *audioComponents;
@property (nonatomic, readonly) NSArray *backgroundTaskSchedulerPermittedIdentifiers;
@property (getter=isBetaApp, nonatomic, readonly) bool betaApp;
@property (nonatomic, readonly) NSNumber *betaExternalVersionIdentifier;
@property (nonatomic, readonly) int bundleModTime;
@property (nonatomic, readonly) bool canHandleWebAuthentication;
@property (nonatomic, readonly) NSArray *carPlayInstrumentClusterURLSchemes;
@property (nonatomic, readonly) NSSet *claimedDocumentContentTypes;
@property (nonatomic, readonly) NSSet *claimedURLSchemes;
@property (nonatomic, readonly) NSString *companionApplicationIdentifier;
@property (nonatomic, readonly) NSString *complicationPrincipalClass;
@property (nonatomic, readonly) id correspondingApplicationRecord;
@property (nonatomic, readonly) NSArray *counterpartIdentifiers;
@property (nonatomic, readonly) id cslprf_safeCorrespondingApplicationRecord;
@property (readonly, copy) NSString *debugDescription; /* unknown property attribute: ? */
@property (getter=isDeletable, nonatomic, readonly) bool deletable;
@property (readonly, copy) NSString *description;
@property (getter=isDeviceBasedVPP, nonatomic, readonly) bool deviceBasedVPP;
@property (nonatomic, readonly) NSArray *deviceFamily;
@property (nonatomic, readonly) NSUUID *deviceIdentifierForAdvertising;
@property (nonatomic, readonly) NSUUID *deviceIdentifierForVendor;
@property (nonatomic, readonly) long long deviceManagementPolicy;
@property (nonatomic, readonly) NSArray *directionsModes;
@property (nonatomic, readonly) id diskUsage;
@property (nonatomic, readonly) NSNumber *downloaderDSID;
@property (nonatomic, readonly) NSNumber *dynamicDiskUsage;
@property (nonatomic, readonly) NSArray *externalAccessoryProtocols;
@property (nonatomic, readonly) NSNumber *externalVersionIdentifier;
@property (nonatomic, readonly) NSNumber *familyID;
@property (nonatomic, readonly) bool fileSharingEnabled;
@property (getter=isGameCenterEnabled, nonatomic, readonly) bool gameCenterEnabled;
@property (nonatomic, readonly) bool gameCenterEverEnabled;
@property (nonatomic, readonly) NSString *genre;
@property (nonatomic, readonly) NSNumber *genreID;
@property (nonatomic, readonly) bool hasComplication;
@property (nonatomic, readonly) bool hasCustomNotification;
@property (nonatomic, readonly) bool hasGlance;
@property (nonatomic, readonly) bool hasMIDBasedSINF;
@property (nonatomic, readonly) bool hasParallelPlaceholder;
@property (nonatomic, readonly) bool hasSettingsBundle;
@property (readonly) unsigned long long hash;
@property (nonatomic, readonly) bool hf_isInstalledForLaunching;
@property (nonatomic, readonly) bool iconIsPrerendered;
@property (nonatomic, readonly) bool iconUsesAssetCatalog;
@property (readonly) NSArray *if_userActivityTypes;
@property (nonatomic, readonly) NSNumber *installFailureReason;
@property (nonatomic, readonly) NSProgress *installProgress;
@property (nonatomic, readonly) unsigned long long installType;
@property (getter=isInstalled, nonatomic, readonly) bool installed;
@property (nonatomic, readonly) NSNumber *itemID;
@property (nonatomic, readonly) NSString *itemName;
@property (getter=isLaunchProhibited, nonatomic, readonly) bool launchProhibited;
@property (nonatomic, readonly) NSArray *managedPersonas;
@property (nonatomic, readonly) NSString *maximumSystemVersion;
@property (nonatomic, readonly) NSString *minimumSystemVersion;
@property (nonatomic, readonly) bool missingRequiredSINF;
@property (getter=isNewsstandApp, nonatomic, readonly) bool newsstandApp;
@property (nonatomic, readonly) unsigned long long originalInstallType;
@property (getter=isPlaceholder, nonatomic, readonly) bool placeholder;
@property (nonatomic, readonly) NSNumber *platform;
@property (nonatomic, readonly) NSArray *plugInKitPlugins;
@property (nonatomic, readonly) NSString *preferredArchitecture;
@property (getter=isPurchasedReDownload, nonatomic, readonly) bool purchasedReDownload;
@property (nonatomic, readonly) NSNumber *purchaserDSID;
@property (nonatomic, readonly) NSString *ratingLabel;
@property (nonatomic, readonly) NSNumber *ratingRank;
@property (nonatomic, readonly) NSDate *registeredDate;
@property (getter=isRemoveableSystemApp, nonatomic, readonly) bool removeableSystemApp;
@property (getter=isRemovedSystemApp, nonatomic, readonly) bool removedSystemApp;
@property (nonatomic, readonly) NSArray *requiredDeviceCapabilities;
@property (getter=isRestricted, nonatomic, readonly) bool restricted;
@property (nonatomic, readonly) bool runsIndependentlyOfCompanionApp;
@property (nonatomic, readonly) NSString *shortVersionString;
@property (nonatomic, readonly) bool shouldSkipWatchAppInstall;
@property (nonatomic, readonly) NSDictionary *siriActionDefinitionURLs;
@property (nonatomic, readonly) NSString *sourceAppIdentifier;
@property (getter=isStandaloneWatchApp, nonatomic, readonly) bool standaloneWatchApp;
@property (nonatomic, readonly) NSNumber *staticDiskUsage;
@property (nonatomic, readonly) NSArray *staticShortcutItems;
@property (nonatomic, readonly) NSString *storeCohortMetadata;
@property (nonatomic, readonly) NSNumber *storeFront;
@property (nonatomic, readonly) NSArray *subgenres;
@property (nonatomic, readonly) NSArray *supportedComplicationFamilies;
@property (nonatomic, readonly) bool supportsAlternateIconNames;
@property (nonatomic, readonly) bool supportsAudiobooks;
@property (nonatomic, readonly) bool supportsExternallyPlayableContent;
@property (nonatomic, readonly) bool supportsMultiwindow;
@property (nonatomic, readonly) bool supportsODR;
@property (nonatomic, readonly) bool supportsOpenInPlace;
@property (nonatomic, readonly) bool supportsPurgeableLocalStorage;
@property (nonatomic, readonly) NSString *teamID;
@property (nonatomic) bool userInitiatedUninstall;
@property (nonatomic, readonly) NSString *vendorName;
@property (getter=isWatchKitApp, nonatomic, readonly) bool watchKitApp;
@property (nonatomic, readonly) NSString *watchKitVersion;
@property (getter=isWhitelisted, nonatomic, readonly) bool whitelisted;

+ (id)applicationProxyForLDEObject:(LDEApplicationObject*)object;
+ (bool)supportsSecureCoding;

- (id)ODRDiskUsage;
- (bool)UPPValidated;
- (id)_localizedNameWithPreferredLocalizations:(id)arg1 useShortNameOnly:(bool)arg2;
- (id)_managedPersonas;
- (id)_stringLocalizerForTable:(id)arg1;
- (bool)_usesSystemPersona;
- (id)activityTypes;
- (id)alternateIconName;
- (id)appIDPrefix;
- (id)appState;
- (id)applicationDSID;
- (id)applicationIdentifier;
- (id)applicationType;
- (id)applicationVariant;
- (id)betaExternalVersionIdentifier;
- (int)bundleModTime;
- (id)bundleType;
- (id)claimedDocumentContentTypes;
- (id)claimedURLSchemes;
- (void)clearAdvertisingIdentifier;
- (id)companionApplicationIdentifier;
- (id)complicationPrincipalClass;
- (id)correspondingApplicationRecord;
- (id)dataContainerURL;
- (id)description;
- (void)detach;
- (id)deviceFamily;
- (long long)deviceManagementPolicy;
- (id)downloaderDSID;
- (id)dynamicDiskUsage;
- (void)encodeWithCoder:(id)arg1;
- (id)environmentVariables;
- (id)externalVersionIdentifier;
- (id)familyID;
- (bool)fileSharingEnabled;
- (id)forwardingTargetForSelector:(SEL)arg1;
- (bool)freeProfileValidated;
- (bool)gameCenterEverEnabled;
- (id)genre;
- (id)genreID;
- (id)getBundleMetadata;
- (void)getDeviceManagementPolicyWithCompletionHandler:(id /* block */)arg1;
- (bool)getGenericTranslocationTargetURL:(id*)arg1 error:(id*)arg2;
- (id)groupContainerURLs;
- (id)handlerRankOfClaimForContentType:(id)arg1;
- (bool)hasMIDBasedSINF;
- (id)iconDataForVariant:(int)arg1;
- (id)iconDataForVariant:(int)arg1 withOptions:(int)arg2;
- (bool)iconIsPrerendered;
- (bool)iconUsesAssetCatalog;
- (id)initWithCoder:(id)arg1;
- (id)installFailureReason;
- (id)installProgress;
- (id)installProgressSync;
- (unsigned long long)installType;
- (bool)isAppUpdate;
- (bool)isBetaApp;
- (bool)isDeletableIgnoringRestrictions;
- (bool)isDeviceBasedVPP;
- (bool)isGameCenterEnabled;
- (bool)isInstalled;
- (bool)isNewsstandApp;
- (bool)isPlaceholder;
- (bool)isPurchasedReDownload;
- (bool)isRemoveableSystemApp;
- (bool)isRemovedSystemApp;
- (bool)isRestricted;
- (bool)isStandaloneWatchApp;
- (bool)isWatchKitApp;
- (bool)isWhitelisted;
- (id)itemID;
- (id)itemName;
- (id)localizedNameForContext:(id)arg1;
- (id)localizedNameForContext:(id)arg1 preferredLocalizations:(id)arg2;
- (id)localizedNameForContext:(id)arg1 preferredLocalizations:(id)arg2 useShortNameOnly:(bool)arg3;
- (id)managedPersonas;
- (id)methodSignatureForSelector:(SEL)arg1;
- (bool)missingRequiredSINF;
- (unsigned long long)originalInstallType;
- (id)platform;
- (id)plugInKitPlugins;
- (id)preferredArchitecture;
- (id)primaryIconDataForVariant:(int)arg1;
- (bool)profileValidated;
- (id)purchaserDSID;
- (id)ratingLabel;
- (id)ratingRank;
- (id)registeredDate;
- (id)requiredDeviceCapabilities;
- (bool)respondsToSelector:(SEL)arg1;
- (void)setAlternateIconName:(id)arg1 withResult:(id /* block */)arg2;
- (void)setUserInitiatedUninstall:(bool)arg1;
- (id)signerIdentity;
- (id)signerOrganization;
- (id)siriActionDefinitionURLs;
- (id)sourceAppIdentifier;
- (id)staticDiskUsage;
- (id)storeCohortMetadata;
- (id)storeFront;
- (id)subgenres;
- (bool)supportsODR;
- (id)teamID;
- (bool)userInitiatedUninstall;
- (id)valueForUndefinedKey:(id)arg1;
- (id)vendorName;

@end

@implementation LSApplicationSpoofProxy

/* inits */
+ (id)applicationProxyForLDEObject:(LDEApplicationObject*)object
{
    LSApplicationSpoofProxy *applicationProxy = [[LSApplicationSpoofProxy alloc] init];
    if(self)
    {
        applicationProxy->_applicationObject = object;
    }
    return applicationProxy;
}

- (id)ODRDiskUsage
{
    return nil;
}

- (bool)UPPValidated
{
    return YES;
}

- (id)_localizedNameWithPreferredLocalizations:(id)arg1
                              useShortNameOnly:(bool)arg2
{
    return _applicationObject.localizedName;
}

- (id)_managedPersonas
{
    return nil;
}

- (id)_stringLocalizerForTable:(id)arg1
{
    return nil;
}

- (NSString*)localizedName
{
    return _applicationObject.localizedName;
}

- (NSArray<NSURL*>*)groupContainerURLs
{
    /* this is a test, remove if not needed */
    return @[];
}

- (id)dataContainerURL
{
    return [NSURL fileURLWithPath:_applicationObject.containerPath];
}

- (bool)isInstalled
{
    return YES;
}

- (bool)_usesSystemPersona
{
    return NO;
}

- (id)activityTypes
{
    return nil;
}

- (id)alternateIconName
{
    return nil;
}

- (id)appIDPrefix
{
    return nil;
}

- (id)appState
{
    return nil;
}

- (id)applicationDSID
{
    return nil;
}


- (id)applicationIdentifier
{
    return _applicationObject.bundleIdentifier;
}

- (id)applicationType
{
    return @"User";
}

- (id)applicationVariant
{
    return nil;
}

- (id)betaExternalVersionIdentifier
{
    return nil;
}

- (int)bundleModTime
{
    return 0;
}

- (id)bundleType
{
    return nil;
}

- (id)claimedDocumentContentTypes
{
    return nil;
}

- (id)claimedURLSchemes
{
    return [NSSet set];
}

- (void)clearAdvertisingIdentifier
{
    return;
}

- (id)companionApplicationIdentifier
{
    return nil;
}

- (id)complicationPrincipalClass
{
    return nil;
}

- (id)correspondingApplicationRecord
{
    return nil;
}

- (id)description
{
    return nil;
}

- (void)detach
{
    return;
}

- (id)deviceFamily
{
    return nil;
}

- (long long)deviceManagementPolicy
{
    return 0;
}

- (id)downloaderDSID
{
    return nil;
}

- (id)dynamicDiskUsage
{
    return nil;
}

- (id)environmentVariables
{
    return @{};
}

- (id)externalVersionIdentifier
{
    return nil;
}

- (id)familyID
{
    return nil;
}

- (bool)fileSharingEnabled
{
    return false;
}

- (bool)freeProfileValidated
{
    return false;
}

- (bool)gameCenterEverEnabled
{
    return false;
}

- (id)genre
{
    return nil;
}

- (id)genreID
{
    return nil;
}

- (id)getBundleMetadata
{
    return nil;
}

- (void)getDeviceManagementPolicyWithCompletionHandler:(id)arg1
{
    
}

- (bool)getGenericTranslocationTargetURL:(id*)arg1 error:(id*)arg2
{
    return false;
}

- (bool)isBetaApp
{
    return false;
}

- (bool)isDeletable
{
    return true;
}

- (bool)isRestricted
{
    return true;
}

- (bool)isContainerized
{
    return true;
}

- (bool)isAdHocCodeSigned
{
    return false;
}

- (bool)isAppStoreVendable
{
    return false;
}

- (bool)isLaunchProhibited
{
    return !_applicationObject.isLaunchAllowed;
}

- (NSString*)teamID
{
    return @"nya";
}

- (NSString*)sdkVersion
{
    return @"nya";
}

- (NSDictionary<NSString*,id<NSCoding>>*)entitlements
{
    return @{};
}

- (NSURL*)bundleContainerURL
{
    return [NSURL fileURLWithPath:_applicationObject.bundlePath];
}

- (_LSDiskUsage*)diskUsage
{
    NSLog(@"wants diskUsage!\n");
    return nil;
}

- (NSDate*)registeredDate
{
    return [NSDate now];
}

- (NSString*)vendorName
{
    return @"";
}

- (NSString*)minimumSystemVersion
{
    return @"";
}

- (NSURL*)bundleURL
{
    return [NSURL fileURLWithPath:_applicationObject.bundlePath];
}

- (NSURL*)containerURL
{
    return [NSURL fileURLWithPath:_applicationObject.containerPath];
}

/*- (id)handlerRankOfClaimForContentType:(id)arg1;
- (bool)hasMIDBasedSINF;
- (id)iconDataForVariant:(int)arg1;
- (id)iconDataForVariant:(int)arg1 withOptions:(int)arg2;
- (bool)iconIsPrerendered;
- (bool)iconUsesAssetCatalog;
- (id)initWithCoder:(id)arg1;
- (id)installFailureReason;
- (id)installProgress;
- (id)installProgressSync;
- (unsigned long long)installType;
- (bool)isAppUpdate;
- (bool)isDeletableIgnoringRestrictions;
- (bool)isDeviceBasedVPP;
- (bool)isGameCenterEnabled;
- (bool)isNewsstandApp;
- (bool)isPlaceholder;
- (bool)isPurchasedReDownload;
- (bool)isRemoveableSystemApp;
- (bool)isRemovedSystemApp;
- (bool)isRestricted;
- (bool)isStandaloneWatchApp;
- (bool)isWatchKitApp;
- (bool)isWhitelisted;
- (id)itemID;
- (id)itemName;
- (id)localizedNameForContext:(id)arg1;
- (id)localizedNameForContext:(id)arg1 preferredLocalizations:(id)arg2;
- (id)localizedNameForContext:(id)arg1 preferredLocalizations:(id)arg2 useShortNameOnly:(bool)arg3;
- (id)managedPersonas;
- (id)methodSignatureForSelector:(SEL)arg1;
- (bool)missingRequiredSINF;
- (unsigned long long)originalInstallType;
- (id)platform;
- (id)plugInKitPlugins;
- (id)preferredArchitecture;
- (id)primaryIconDataForVariant:(int)arg1;
- (bool)profileValidated;
- (id)purchaserDSID;
- (id)ratingLabel;
- (id)ratingRank;
- (id)registeredDate;
- (id)requiredDeviceCapabilities;
- (bool)respondsToSelector:(SEL)arg1;
- (void)setAlternateIconName:(id)arg1 withResult:(id)arg2;
- (void)setUserInitiatedUninstall:(bool)arg1;
- (id)signerIdentity;
- (id)signerOrganization;
- (id)siriActionDefinitionURLs;
- (id)sourceAppIdentifier;
- (id)staticDiskUsage;
- (id)storeCohortMetadata;
- (id)storeFront;
- (id)subgenres;
- (bool)supportsODR;
- (bool)userInitiatedUninstall;
- (id)valueForUndefinedKey:(id)arg1;
- (id)vendorName;
 */

- (BOOL)isKindOfClass:(Class)cls
{
   if(cls == PrivClass(LSApplicationProxy))
   {
       return YES;
   }
   return [super isKindOfClass:cls];
}

- (Class)class
{
    return PrivClass(LSApplicationProxy);
}

@end

@interface LSApplicationWorkspaceHooks: NSObject
@end

@implementation LSApplicationWorkspaceHooks {
    
}

+ (void)load
{
    [super load];
    
    SwizzleObjCMethod(@selector(allApplications), PrivClass(LSApplicationWorkspace), @selector(hook_allApplications), [LSApplicationWorkspaceHooks class], kSwizzleMethodTypeInstance);
    SwizzleObjCMethod(@selector(uninstallApplication:withOptions:error:usingBlock:), PrivClass(LSApplicationWorkspace), @selector(hook_uninstallApplication:withOptions:error:usingBlock:), [LSApplicationWorkspaceHooks class], kSwizzleMethodTypeInstance);
}

- (NSArray<LSApplicationSpoofProxy*>*)hook_allApplications
{
    LDEApplicationWorkspace *workspace = [LDEApplicationWorkspace shared];
    [workspace ping];
    
    NSArray<LDEApplicationObject*> *allApplicationObjects = [workspace allApplicationObjects];
    NSMutableArray<LSApplicationSpoofProxy*> *apps = [NSMutableArray array];
    for(LDEApplicationObject *object in allApplicationObjects)
    {
        LSApplicationSpoofProxy *proxy = [LSApplicationSpoofProxy applicationProxyForLDEObject:object];
        [apps addObject:proxy];
    }
    
    return apps;
}

- (BOOL)openApplicationWithBundleID:(NSString*)bundleIdentifier
{
    return NO;  /* no call path to do that externally yet */
}

- (BOOL)hook_uninstallApplication:(NSString *)bundleID
                      withOptions:(NSDictionary<NSString *, id> *_Nullable)arg1
                            error:(NSError **)arg2
                       usingBlock:(_Nullable id)arg3 __attribute__((swift_error(nonnull_error)))
{
    return [[LDEApplicationWorkspace shared] deleteApplicationWithBundleID:bundleID];
}

@end
