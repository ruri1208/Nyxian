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

import UIKit

class SettingsViewController: UIThemedTableViewController {
    init() {
        super.init(style: .insetGrouped)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Settings"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
#if DEBUG
        return NXApplicationState.extensionLessMode ? 2 : 5
#else
        return NXApplicationState.extensionLessMode ? 2 : 4
#endif // DEBUG
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.accessoryType = .disclosureIndicator

        switch indexPath.row {
        case 0:
            cell.imageView?.image = UIImage(systemName: "wrench.adjustable.fill")
            cell.textLabel?.text = "Toolchain"
            break
        case 1:
            if NXApplicationState.extensionLessMode {
                cell.imageView?.image = UIImage(systemName: "paintbrush.fill")
                cell.textLabel?.text = "Customization"
            } else {
                cell.imageView?.image = UIImage(systemName: "bolt.shield.fill")
                cell.textLabel?.text = "Management"
            }
            break
        //case 2:
            //if NXApplicationState.extensionLessMode {
                //cell.imageView?.image = UIImage(systemName: "person.3.fill")
                //cell.textLabel?.text = "Credits"
            //} else {
                //cell.imageView?.image = UIImage(systemName: "app.badge.fill")
                /cell.textLabel?.text = "Applications"
            //}
            //break
        case 2:
            cell.imageView?.image = UIImage(systemName: "paintbrush.fill")
            cell.textLabel?.text = "Customization"
            break
#if DEBUG
        case 3:
            cell.imageView?.image = UIImage(systemName: "ant.fill")
            cell.textLabel?.text = "Kernel Log"
            break
        case 4:
            cell.imageView?.image = UIImage(systemName: "person.3.fill")
            cell.textLabel?.text = "Credits"
            break
#else
        case 3:
            cell.imageView?.image = UIImage(systemName: "person.3.fill")
            cell.textLabel?.text = "Credits"
            break
#endif // DEBUG
        default:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigateToController(for: indexPath.row, animated: true)
    }

    private func navigateToController(for index: Int, animated: Bool) {
        guard let viewController: UIViewController = {
            switch index {
            case 0:
                return ToolChainViewController(style: .insetGrouped)
            case 1:
                if NXApplicationState.extensionLessMode {
                    return CustomizationViewController(style: .insetGrouped)
                } else {
                    return ManagementViewController(style: .insetGrouped)
                }
            //case 2:
                //if NXApplicationState.extensionLessMode {
                    //return CreditsViewController(style: .insetGrouped)
                //} else {
                    //return ApplicationManagementViewController.shared
                //}
            case 2:
                return CustomizationViewController(style: .insetGrouped)
#if DEBUG
            case 3:
                return KernelLogViewController()
            case 4:
                return CreditsViewController(style: .insetGrouped)
#else
            case 3:
                return CreditsViewController(style: .insetGrouped)
#endif // DEBUG
            default:
                return nil
            }
        }() else { return }

        navigationController?.pushViewController(viewController, animated: animated)
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "\(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Nyxian") \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") \"Scriptura\" Beta (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))"
    }
}
