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

#import <UI/Settings/NXSettingsTableViewController.h>
#import <Nyxian-Swift.h>

@implementation NXSettingsTableViewController

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title = @"Settings";
}

- (CFIndex)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return NXApplicationState.extensionLessMode ? 3 : 4;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    if(NXApplicationState.extensionLessMode && indexPath.row > 0)
    {
        indexPath = [NSIndexPath indexPathForRow:indexPath.row + 1 inSection:indexPath.section];
    }
    
    switch(indexPath.row)
    {
        case 0:
            cell.imageView.image = [UIImage systemImageNamed:@"wrench.adjustable.fill"];
            cell.textLabel.text = @"Toolchain";
            break;
        case 1:
            cell.imageView.image = [UIImage systemImageNamed:@"bolt.shield.fill"];
            cell.textLabel.text = @"Management";
            break;
        case 2:
            cell.imageView.image = [UIImage systemImageNamed:@"paintbrush.fill"];
            cell.textLabel.text = @"Customization";
            break;
        case 3:
            cell.imageView.image = [UIImage systemImageNamed:@"person.3.fill"];
            cell.textLabel.text = @"Credits";
            break;
        default:
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if(NXApplicationState.extensionLessMode && indexPath.row > 0)
    {
        indexPath = [NSIndexPath indexPathForRow:indexPath.row + 1 inSection:indexPath.section];
    }
    
    [self navigateToControllerForIndex:indexPath.row animated:YES];
}

- (void)navigateToControllerForIndex:(CFIndex)index
                            animated:(BOOL)animated
{
    UIViewController *viewController = nil;
    switch(index)
    {
        case 0:
            viewController = [[ToolChainViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            break;
        case 1:
            viewController = [[ManagementViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            break;
        case 2:
            viewController = [[CustomizationViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            break;
        case 3:
            viewController = [[CreditsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            break;
        default:
            break;
    }
    if(viewController != nil)
    {
        [self.navigationController pushViewController:viewController animated:YES];
    }
}

- (NSString*)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if([self numberOfSectionsInTableView:self.tableView] == (section + 1))
    {
        NSBundle *bundle = [NSBundle mainBundle];
        return [NSString stringWithFormat:@"%@ %@ \"Scriptura\" Beta (%@)", [bundle objectForInfoDictionaryKey:@"CFBundleName"]?: @"Nyxian", [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?: @"Unknown", [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]?: @"Unknown"];
    }
    return nil;
}

@end
