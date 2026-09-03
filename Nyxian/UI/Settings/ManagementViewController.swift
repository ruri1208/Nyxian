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

class ManagementViewController: UIThemedTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Management"
        view.backgroundColor = .systemBackground
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch(section) {
            case 0:
                return 1
            case 1:
                return 2
            case 2:
                return 2
            default:
                return 4
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let tableViewCell: UITableViewCell = UITableViewCell()
        
        switch(indexPath.section) {
            case 0:
                tableViewCell.textLabel?.text = "Browse Virtual File System"
                tableViewCell.accessoryType = .disclosureIndicator
            case 1:
                if indexPath.row == 0 {
                    tableViewCell.textLabel?.text = "Generate Root Trust Key Pair"
                } else if indexPath.row == 1 {
                    tableViewCell.textLabel?.text = "Installed public root trust keys"
                    tableViewCell.accessoryType = .disclosureIndicator
                }
            case 2:
                if indexPath.row == 0 {
                    tableViewCell.textLabel?.text = "Installed Applications"
                    tableViewCell.accessoryType = .disclosureIndicator
                } else if indexPath.row == 1 {
                    tableViewCell.textLabel?.text = "Installed KEXTs"
                    tableViewCell.accessoryType = .disclosureIndicator
                }
            default:
                if indexPath.row == 0 {
                    tableViewCell.textLabel?.text = "Userspace Reboot"
                } else if indexPath.row == 1 {
                    tableViewCell.textLabel?.text = "Reload Daemons"
                } else if indexPath.row == 2 {
                    tableViewCell.textLabel?.text = "Clear Application Caches"
                    tableViewCell.textLabel?.textColor = .systemRed
                } else if indexPath.row == 3 {
                    tableViewCell.textLabel?.text = "Restore"
                    tableViewCell.textLabel?.textColor = .systemRed
                }
        }
        
        return tableViewCell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch(indexPath.section) {
            case 0:
                navigationController?.pushViewController(FileListViewController(isSublink: true, path: NXBootstrap.shared().rootfsURL.path), animated: true)
            case 1:
                if indexPath.row == 0 {
                    do {
                        try FileManager.default.createDirectory(atPath: "\(NSHomeDirectory())/Library/RootCAGen", withIntermediateDirectories: true)
                        trust_nxt2_generate_rootca_keypair(UserDefaults.standard.string(forKey: "LDEOrganizationPrefix") ?? NXUser.shared().username,"\(NSHomeDirectory())/Library/RootCAGen/pub.nxt2c", "\(NSHomeDirectory())/Library/RootCAGen/priv.der")
                        if !zipDirectoryAtPath("\(NSHomeDirectory())/Library/RootCAGen", "\(NSHomeDirectory())/Library/RootCAGen.zip", false) {
                            try FileManager.default.removeItem(atPath: "\(NSHomeDirectory())/Library/RootCAGen")
                            throw NSError(domain: "org.emexlabs.nyxian.rootca.zip", code: -1, userInfo: [NSLocalizedDescriptionKey:"Failed to zip RootCA"])
                        }
                        try FileManager.default.removeItem(atPath: "\(NSHomeDirectory())/Library/RootCAGen")
                        share(url: URL(fileURLWithPath: "\(NSHomeDirectory())/Library/RootCAGen.zip"), remove: true)
                    } catch {
                        NotificationServer.NotifyUser(level: .error, notification: "Failed to generate new RootCA: \(error.localizedDescription)")
                    }
                } else {
                    print("pressed on list rootca")
                }
            case 2:
                if indexPath.row == 0 {
                    navigationController?.pushViewController(ApplicationManagementViewController(style: .insetGrouped), animated: true)
                } else {
                    navigationController?.pushViewController(KEXTManagementViewController(style: .insetGrouped), animated: true)
                }
            default:
                if indexPath.row == 0 {
                    PEUserspaceManager.shared().rebootUserspace()
                } else if indexPath.row == 1 {
                    PEUserspaceManager.shared().reloadDaemons()
                } else if indexPath.row == 2 {
                    let alert = UIAlertController(
                        title: "Clear Application Caches",
                        message: "All application caches will be wiped, this can have consequences, but it will result in less data being in use. (Some people like that for performance reasons)",
                        preferredStyle: .alert
                    )
                
                    alert.addAction(UIAlertAction(title: "Proceed", style: .destructive) { [weak self] _ in
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: nil, message: "Clearing Application Caches", preferredStyle: .alert)
                        
                            let activityIndicator = UIActivityIndicatorView(style: .medium)
                            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
                            activityIndicator.startAnimating()
                        
                            alert.view.addSubview(activityIndicator)
                        
                            NSLayoutConstraint.activate([
                                activityIndicator.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor),
                                activityIndicator.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -20)
                            ])
                        
                            guard let self = self else {
                                return
                            }
                            self.present(alert, animated: true) { [weak self] in
                                guard let self = self else {
                                    return
                                }
                                DispatchQueue.global().async { [weak self] in
                                    guard let self = self else {
                                        return
                                    }
                                    let success = PEUserspaceManager.shared().clearApplicationCaches()
                                    DispatchQueue.main.async { [weak self] in
                                        guard let self = self else {
                                            return
                                        }
                                        alert.dismiss(animated: true)
                                        if !success {
                                            let alert = UIAlertController(
                                                title: "Error",
                                                message: "Clearing Application Caches failed",
                                                preferredStyle: .alert
                                            )
                                            
                                            alert.addAction(UIAlertAction(title: "Close", style: .cancel))
                                            
                                            self.present(alert, animated: true)
                                        }
                                    }
                                }
                            }
                        }
                    })
                
                    alert.addAction(UIAlertAction(title: "Keep Caches", style: .cancel))
                
                    self.present(alert, animated: true)
                } else if indexPath.row == 3 {
                    let alert = UIAlertController(
                        title: "Restore",
                        message: "All apps, binaries and data containers in the virtual environment will be wiped.",
                        preferredStyle: .alert
                    )
                
                    alert.addAction(UIAlertAction(title: "Proceed", style: .destructive) { [weak self] _ in
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: nil, message: "Restoring", preferredStyle: .alert)
                        
                            let activityIndicator = UIActivityIndicatorView(style: .medium)
                            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
                            activityIndicator.startAnimating()
                        
                            alert.view.addSubview(activityIndicator)
                        
                            NSLayoutConstraint.activate([
                                activityIndicator.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor),
                                activityIndicator.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -20)
                            ])
                        
                            guard let self = self else {
                                return
                            }
                            self.present(alert, animated: true) { [weak self] in
                                guard let self = self else {
                                    return
                                }
                                DispatchQueue.global().async { [weak self] in
                                    guard let self = self else {
                                        return
                                    }
                                    let success = PEUserspaceManager.shared().restore()
                                    DispatchQueue.main.async { [weak self] in
                                        guard let self = self else {
                                            return
                                        }
                                        alert.dismiss(animated: true)
                                        if !success {
                                            let alert = UIAlertController(
                                                title: "Error",
                                                message: "Restore failed",
                                                preferredStyle: .alert
                                            )
                                            
                                            alert.addAction(UIAlertAction(title: "Close", style: .cancel))
                                            
                                            self.present(alert, animated: true)
                                        }
                                    }
                                }
                            }
                        }
                    })
                
                    alert.addAction(UIAlertAction(title: "Keep Data", style: .cancel))
                
                    self.present(alert, animated: true)
                }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
