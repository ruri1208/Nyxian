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

#import "LDEApplicationObject.h"
#import "LDEApplicationWorkspaceInternal.h"
#import "ISIcon.h"
#import <LindChain/Private/UIKitPrivate.h>
#import <LindChain/ProcEnvironment/Surface/trust/signing.h>

#import <UIKit/UIKit.h>

@implementation LDEApplicationObject

- (instancetype)initWithNSBundle:(NSBundle*)bundle
{
#if HOST_ENV
    return nil;
#else
    self = [super init];
    
    ksurface_nxt2_t result;
    kern_return_t kr = trust_nxt2_read([[bundle executablePath] UTF8String], &result);
    if(kr == KERN_SUCCESS)
    {
        self.entitlements = (__bridge_transfer NSDictionary*)result.entitlements;
    }
    else
    {
        self.entitlements = @{};
    }
    
    self.iconDictionary = [bundle objectForInfoDictionaryKey:@"CFBundleIcons"];
    self.bundleVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    self.shortVersionString = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?: self.bundleVersion;
    self.sdkVersion = [bundle objectForInfoDictionaryKey:@"DTPlatformVersion"];
    self.minimumSystemVersion = [bundle objectForInfoDictionaryKey:@"MinimumOSVersion"];
    
    self.bundleIdentifier = bundle.bundleIdentifier;
    
    id fullScreen = [bundle objectForInfoDictionaryKey:@"UIRequiresFullScreen"];
    if([fullScreen isKindOfClass:[NSNumber class]])
    {
        self.isFullscreenRequired = [fullScreen boolValue];
    }
    else
    {
        self.isFullscreenRequired = NO;
    }
    
    NSString *localizedDisplayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if(!localizedDisplayName)
    {
        localizedDisplayName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    }
    self.localizedName = NSLocalizedStringFromTableInBundle(localizedDisplayName, @"InfoPlist", bundle, localizedDisplayName);
    self.isLaunchAllowed = [[LDEApplicationWorkspaceInternal shared] doWeTrustThatBundle:bundle];
    if(self.isLaunchAllowed)
    {
        self.bundlePath = [[bundle bundleURL] path];
        self.executablePath = [[bundle executableURL] path];
        self.containerPath = [[[LDEApplicationWorkspaceInternal shared] applicationContainerForBundleID:bundle.bundleIdentifier] path];
    }
    
    ISBundleIcon *bundleIcon = [[PrivClass(ISBundleIcon) alloc] initWithBundleURL:bundle.bundleURL type:nil];
    if(bundleIcon)
    {
        ISResourceProvider *provider = [bundleIcon _makeAppResourceProvider];
        if(provider.isGenericProvider) return self;
        
        ISAssetCatalogResource *resources = [provider iconResource];
        if([resources isKindOfClass:NSClassFromString(@"IFImageBag")])
        {
            IFImageBag *imageBag = (IFImageBag*)resources;
            IFImage *image = [imageBag imageForSize:CGSizeMake(1024, 1024) scale:3.0];
            self.icon = [UIImage imageWithCGImage:image.CGImage scale:3.0 orientation:UIImageOrientationUp];
            return self;
        }
        
        IFImage *image = [resources imageForSize:CGSizeMake(1024, 1024) scale:3.0];
        self.icon = [UIImage imageWithCGImage:image.CGImage scale:3.0 orientation:UIImageOrientationUp];
    }

    return self;
#endif /* HOST_ENV */
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder
{
    [coder encodeObject:self.bundleIdentifier forKey:@"bundleIdentifier"];
    [coder encodeObject:self.bundlePath forKey:@"bundlePath"];
    [coder encodeObject:self.executablePath forKey:@"executablePath"];
    [coder encodeObject:self.localizedName forKey:@"localizedName"];
    [coder encodeObject:self.containerPath forKey:@"containerPath"];
    [coder encodeObject:self.icon forKey:@"icon"];
    [coder encodeObject:self.iconDictionary forKey:@"iconDictionary"];
    [coder encodeObject:self.bundleVersion forKey:@"bundleVersion"];
    [coder encodeObject:self.shortVersionString forKey:@"shortVersionString"];
    [coder encodeObject:self.sdkVersion forKey:@"sdkVersion"];
    [coder encodeObject:self.minimumSystemVersion forKey:@"minimumSystemVersion"];
    [coder encodeObject:self.entitlements forKey:@"entitlements"];
    [coder encodeObject:@(self.isLaunchAllowed) forKey:@"isLaunchAllowed"];
    [coder encodeObject:@(self.isFullscreenRequired) forKey:@"isFullscreenRequired"];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder
{
    if(self = [super init])
    {
        _bundleIdentifier = [coder decodeObjectOfClass:[NSString class] forKey:@"bundleIdentifier"];
        _bundlePath = [coder decodeObjectOfClass:[NSString class] forKey:@"bundlePath"];
        _executablePath = [coder decodeObjectOfClass:[NSString class] forKey:@"executablePath"];
        _localizedName = [coder decodeObjectOfClass:[NSString class] forKey:@"localizedName"];
        _containerPath = [coder decodeObjectOfClass:[NSString class] forKey:@"containerPath"];
        _icon = [coder decodeObjectOfClass:[UIImage class] forKey:@"icon"];
        _iconDictionary = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSDictionary class], [NSArray class], [NSString class], [NSNumber class], [NSData class]]] forKey:@"iconDictionary"];
        _bundleVersion = [coder decodeObjectOfClass:[NSString class] forKey:@"bundleVersion"];
        _shortVersionString = [coder decodeObjectOfClass:[NSString class] forKey:@"shortVersionString"];
        _sdkVersion = [coder decodeObjectOfClass:[NSString class] forKey:@"sdkVersion"];
        _minimumSystemVersion = [coder decodeObjectOfClass:[NSString class] forKey:@"minimumSystemVersion"];
        _entitlements = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSDictionary class], [NSArray class], [NSString class], [NSNumber class], [NSData class]]] forKey:@"entitlements"];
        _isLaunchAllowed = [[coder decodeObjectOfClass:[NSNumber class] forKey:@"isLaunchAllowed"] boolValue];
        _isFullscreenRequired = [[coder decodeObjectOfClass:[NSNumber class] forKey:@"isFullscreenRequired"] boolValue];
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (![object isKindOfClass:[LDEApplicationObject class]]) return NO;
    LDEApplicationObject *other = (LDEApplicationObject *)object;
    return [self.bundleIdentifier isEqualToString:other.bundleIdentifier];
}

- (NSUInteger)hash
{
    return self.bundleIdentifier.hash;
}

@end
