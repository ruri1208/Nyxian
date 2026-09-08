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

#import <UIKit/UIKit.h>
#import <LindChain/Services/applicationmgmtd/ISIcon.h>
#import <LindChain/Utils/IconUtils.h>
#import <LindChain/Private/UIKitPrivate.h>

static ISImageDescriptor *ISIDescriptorFor(CGSize size, CGFloat scale)
{
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary new]; });

    NSString *key = [NSString stringWithFormat:@"%.1fx%.1f@%.1f", size.width, size.height, scale];
    @synchronized(cache)
    {
        ISImageDescriptor *descriptor = cache[key];
        if(!descriptor)
        {
            descriptor = [[PrivClass(ISImageDescriptor) alloc] initWithSize:size scale:scale];
            descriptor.shape = 1;
            descriptor.appearance = 0;
            descriptor.appearanceVariant = 0;
            descriptor.shouldApplyMask = YES;
            descriptor.drawBorder = YES;
            cache[key] = descriptor;
        }
        return descriptor;
    }
}

UIImage *Gib26Icon(UIImage *rawIcon,
                   CGSize size,
                   CGFloat scale)
{
    if(!rawIcon.CGImage)
    {
        return nil;
    }
    
    IFImage *source = [[PrivClass(IFImage) alloc] initWithCGImage:rawIcon.CGImage scale:rawIcon.scale];
    if(!source)
    {
        return nil;
    }
    
    ISIcon *icon = [[PrivClass(ISIcon) alloc] initWithImages:@[source]];
    if(!icon)
    {
        return nil;
    }
    
    /* more research is needed on how apple applies the format :c */
    ISImageDescriptor *descriptor = ISIDescriptorFor(size, scale);
    
    /* apperently what apple uses */
    IFImage *rendered = [icon prepareImageForDescriptor:descriptor];
    if(!rendered || !rendered.CGImage)
    {
        return nil;
    }
    
    return [UIImage imageWithCGImage:rendered.CGImage scale:scale orientation:UIImageOrientationUp];
}

UIImage *Gib26FallbackIcon(CGSize size, CGFloat scale)
{
    ISIcon *icon = [PrivClass(ISIcon) transparentIcon];
    if(!icon)
    {
        return nil;
    }
    
    ISImageDescriptor *descriptor = ISIDescriptorFor(size, scale);
    
    IFImage *rendered = [icon prepareImageForDescriptor:descriptor];
    if(!rendered || !rendered.CGImage)
    {
        return nil;
    }
    
    return [UIImage imageWithCGImage:rendered.CGImage scale:scale orientation:UIImageOrientationUp];
}
