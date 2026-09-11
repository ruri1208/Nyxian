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
import UniformTypeIdentifiers

class CertificateImporter: NXUITableViewController, UITextFieldDelegate {
    var textField: NXTextFieldTableCell?
    
    var cert: ComplexImportTableCell?
    
    let importButton: UIBarButtonItem = UIBarButtonItem()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.isModalInPresentation = true
        self.navigationController?.isModalInPresentation = true
        self.title = "Set Up Signing"
        
        importButton.title = "Import"
        importButton.target = self
        importButton.action = #selector(importButtonTapped)
        if #available(iOS 26.0, *) {
            importButton.style = .prominent
        }
        
        let cancelButton: UIBarButtonItem = UIBarButtonItem()
        cancelButton.title = "Cancel"
        cancelButton.target = self
        cancelButton.action = #selector(closeButtonTapped)
        
        navigationItem.rightBarButtonItem = importButton
        navigationItem.leftBarButtonItem = cancelButton
        
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.isScrollEnabled = false
        self.tableView.rowHeight = UITableView.automaticDimension
        
        if UIDevice.current.userInterfaceIdiom == .phone {
            if let sheet = self.navigationController?.sheetPresentationController {
                DispatchQueue.main.async {
                    sheet.animateChanges {
                        sheet.detents = [
                            .custom { context in
                                let contentHeight = self.tableView.contentSize.height + 50
                                return contentHeight
                            }
                        ]
                    }
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        
        switch indexPath.section {
        case 0:
            cert = ComplexImportTableCell(parent: self)
            cell = cert!
            break
        case 1:
            textField = NXTextFieldTableCell(title: "Password", hint: "Enter certificate password", key: nil, defaultValue: "")
            textField!.textField.isSecureTextEntry = true
            textField!.textField.textContentType = .password
            cell = textField!
            break
        default:
            cell = UITableViewCell()
            break
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
            case 1:
                return "The password and certificate is only used to sign apps on your behave, they stay entirely on your device."
            default:
                return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    @objc func importButtonTapped() {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        navigationItem.setRightBarButton(UIBarButtonItem(customView: spinner), animated: true)
        
        let cert = self.cert
        let password = self.textField?.text ?? ""
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            do {
                if let cert = cert,
                   let url = cert.url {
                    let p12Data: Data = try Data(contentsOf: url)
                    
                    LCUtils.validateCertificate(withCertificateData: p12Data, withPassword: password) { [weak self] status, someWords in
                        guard let self = self else { return }
                        if status == 0 {
                            LCUtils.certificateData = p12Data
                            LCUtils.certificatePassword = password
                            DispatchQueue.main.async {
                                self.dismiss(animated: true)
                            }
                            return
                        }
                        NotificationServer.NotifyUser(level: .error, notification: someWords ?? "A Unknown issue has happened importing the certificate, please report this issue. (error = \(status))")
                        DispatchQueue.main.async {
                            self.navigationItem.setRightBarButton(self.importButton, animated: true)
                        }
                    }
                } else {
                    guard let self = self else { return }
                    NotificationServer.NotifyUser(level: .error, notification: "Select a certificate first.")
                    DispatchQueue.main.async {
                        self.navigationItem.setRightBarButton(self.importButton, animated: true)
                    }
                }
            } catch {
                NotificationServer.NotifyUser(level: .error, notification: "Something went wrong importing the certificate! (\(error.localizedDescription))")
            }
        }
    }
    
    @objc func closeButtonTapped() {
        self.dismiss(animated: true)
    }
}
