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

#import <Nyxian-Swift.h>
#import <UIKit/UIKit.h>
#import <UI/UIInit/NXUITableViewController.h>

@implementation NXUITableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = LDETheme.currentTheme.appTableView;
    self.tableView.backgroundColor = LDETheme.currentTheme.appTableView;
    self.tableView.separatorColor = LDETheme.currentTheme.gutterHairlineColor;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.view.backgroundColor = LDETheme.currentTheme.appTableView;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.view.backgroundColor = LDETheme.currentTheme.appTableView;
    self.tableView.separatorColor = LDETheme.currentTheme.gutterHairlineColor;
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleRethemeNotification:) name:@"uiColorChangeNotif" object:nil];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)handleRethemeNotification:(NSNotification*)notification
{
    self.view.backgroundColor = LDETheme.currentTheme.appTableView;
    self.tableView.backgroundColor = LDETheme.currentTheme.appTableView;
    self.tableView.separatorColor = LDETheme.currentTheme.gutterHairlineColor;
    
    for(UITableViewCell *cell in self.tableView.visibleCells)
    {
        cell.backgroundColor = LDETheme.currentTheme.appTableCell;
    }
}

@end
