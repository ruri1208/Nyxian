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

#if DEBUG

import UIKit

class ProcessViewController: UIThemedTableViewController {
    let process: PESurfaceProcDescriptor
    
    init(process: PESurfaceProcDescriptor) {
        self.process = process
        super.init(style: .insetGrouped)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "\(self.process.rawProc, default: "0x0")"
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
            case 0:
                return 2
            case 1:
                return 6
            case 2:
                return 1
            default:
                return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)

        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "PID: \(self.process.pid)"
            case 1:
                cell.textLabel?.text = "PPID: \(self.process.ppid)"
            default:
                break
            }
        case 1:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "EUID: \(self.process.euid)"
            case 1:
                cell.textLabel?.text = "RUID: \(self.process.ruid)"
            case 2:
                cell.textLabel?.text = "SVUID: \(self.process.svuid)"
            case 3:
                cell.textLabel?.text = "EGID: \(self.process.egid)"
            case 4:
                cell.textLabel?.text = "RGID: \(self.process.rgid)"
            case 5:
                cell.textLabel?.text = "SVGID: \(self.process.svgid)"
            default:
                break
            }
        case 2:
            switch indexPath.row {
            case 0:
                let hexString = String(format: "0x%016llx", self.process.entitlement.rawValue)
                cell.textLabel?.text = "Entitlements: \(hexString)"
            default:
                break
            }
        default:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

class ProcessTableViewController: UIThemedTableViewController {
    var allProcesses: [PESurfaceProcDescriptor] = PESurfaceStatic.allProcesses
    
    init() {
        super.init(style: .insetGrouped)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Process Table"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.allProcesses.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.accessoryType = .disclosureIndicator

        switch indexPath.row {
        default:
            cell.textLabel?.text = "\(self.allProcesses[indexPath.row].rawProc, default: "0x0")"
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(ProcessViewController(process: self.allProcesses[indexPath.row]), animated: true)
    }
}

#endif // DEBUG
