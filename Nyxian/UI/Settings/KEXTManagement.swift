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

class KextToggleTableCell: UITableViewCell {
    static let reuseIdentifier = "KextToggleTableCell"
    
    var callback: (Bool) -> Void = { _ in }
    
    private(set) var toggle: UISwitch = {
        let toggle = UISwitch()
        return toggle
    }()
    
    private var defaultValue: Bool = false
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        accessoryView = toggle
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: Notification.Name("uiColorChangeNotif"), object: nil)
        
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            self.applyTheme()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func configure(title: String, defaultValue: Bool, callback: @escaping (Bool) -> Void = { _ in }) {
        self.defaultValue = defaultValue
        self.callback = callback
        textLabel?.text = title
        toggle.isOn = defaultValue
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        defaultValue = false
        callback = { _ in }
        textLabel?.text = nil
        toggle.isOn = false
    }
    
    private func applyTheme() {
        toggle.onTintColor = currentTheme?.appLabel
        toggle.thumbTintColor = currentTheme?.appTableCell
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        applyTheme()
    }
    
    @objc private func toggleChanged(_ sender: UISwitch) {
        callback(sender.isOn)
    }
    
    @objc private func handleThemeChange() {
        applyTheme()
    }
}

class KEXTManagementViewController: UIThemedTableViewController, UITextFieldDelegate, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    
    var kexts: [PEKext] = []
    
    override init(style: UITableView.Style) {
        super.init(style: style)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.register(ProjectTableCell.self, forCellReuseIdentifier: ProjectTableCell.reuseIdentifier)
        LDEApplicationWorkspace.shared().ping()
        self.title = "KEXTs"
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: nil, image: UIImage(systemName: "square.and.arrow.down.fill"), target: self, action: #selector(plusButtonPressed))

        do {
            let kextURLs: [URL] = try FileManager.default.contentsOfDirectory(at: NXBootstrap.shared().rootURL.appendingPathComponent("/mntfs/kextfs"), includingPropertiesForKeys: [])
            for kextURL in kextURLs {
                if let kext: PEKext = PEKext(path: kextURL.path) {
                    self.kexts.append(kext)
                    self.tableView.reloadData()
                }
            }
        } catch {
                
        }
        
        self.tableView.register(KextToggleTableCell.self, forCellReuseIdentifier: KextToggleTableCell.reuseIdentifier)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.kexts.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let kext: PEKext = self.kexts[indexPath.row]
        let cell: KextToggleTableCell = self.tableView.dequeueReusableCell(withIdentifier: KextToggleTableCell.reuseIdentifier, for: indexPath) as! KextToggleTableCell
        cell.configure(title: kext.bundleID, defaultValue: kext.isEnabled) { newValue in
            kext.isEnabled = newValue
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let kext: PEKext = self.kexts[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak kext] _ in
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash.fill"), attributes: .destructive) { _ in
            }
            
            return UIMenu(title: "", children: [deleteAction])
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
    }
    
    @objc func plusButtonPressed() {
        let documentPicker: UIDocumentPickerViewController = UIDocumentPickerViewController(forOpeningContentTypes: [.ipa,.tipa,.nipa], asCopy: true)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        self.present(documentPicker, animated: true)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let alert = UIAlertController(title: nil, message: "Validating", preferredStyle: .alert)
        
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        
        alert.view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -20)
        ])
        
        self.present(alert, animated: true)
        
        DispatchQueue.global().async {
            do {
                guard let selectedURL = urls.first else { return }
                
                let fileManager = FileManager.default
                let tempRoot = NSTemporaryDirectory()
                let workRoot = (tempRoot as NSString).appendingPathComponent(UUID().uuidString)
                let unzipRoot = (workRoot as NSString).appendingPathComponent("unzipped")
                let payloadDir = (unzipRoot as NSString).appendingPathComponent("Payload")
                
                guard ((try? fileManager.createDirectory(atPath: unzipRoot, withIntermediateDirectories: true)) != nil) else { return }
                guard unzipArchiveAtPath(selectedURL.path, unzipRoot) else { return }
                let contents: [String] = try FileManager.default.contentsOfDirectory(atPath: payloadDir)
                
                guard let appBundlePathComponent = contents.first(where: { ($0 as NSString).pathExtension == "kext" }) else {
                    alert.dismiss(animated: true) {
                        NotificationServer.NotifyUser(level: .error, notification: "Failed to install kext: no .kext bundle found")
                    }
                    return
                }
                
                let appBundleFullPath = payloadDir.appending("/\(appBundlePathComponent)")
                
                guard let bundle = Bundle(path: appBundleFullPath) else {
                    alert.dismiss(animated: true) {
                        NotificationServer.NotifyUser(level: .error, notification: "Failed to install kext: invalid bundle path")
                    }
                    return
                }
                
                guard let executablePath = bundle.executablePath else {
                    alert.dismiss(animated: true) {
                        NotificationServer.NotifyUser(level: .error, notification: "Failed to install kext: invalid executable path")
                    }
                    return
                }
                
                var final: [String: Any] = [:]
                var isRootCATrusted: Bool = false;
                var trust_nxt2 = ksurface_nxt2()
                let kr: kern_return_t = trust_nxt2_read(executablePath, &trust_nxt2)
                if(kr != 0) {
                    if trust_nxt2.entitlements != nil {
                        trust_nxt2.entitlements.release()
                    }
                } else {
                    let unmanagedDict: Unmanaged<CFDictionary>? = trust_nxt2.entitlements
                    if let cfDict = unmanagedDict?.takeRetainedValue() {
                        let nsDict = cfDict as NSDictionary
                        if let swiftDict = nsDict as? [String: Any] {
                            final = swiftDict
                            withUnsafeBytes(of: trust_nxt2.cdhash) { rawBuffer in
                                let uint8Pointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
                                if let meowsomeBoolean: Bool = final["org.emexlabs.nyxian.ksurface.kernelextension.loading"] as? Bool {
                                    if trust_nxt2.isValid && trust_nxt2.isCdHashValid && meowsomeBoolean && CDHashMatchesCodeDirectoryOfPath(executablePath, uint8Pointer) == KERN_SUCCESS {
                                        isRootCATrusted = trust_nxt2.isSigned || trust_nxt2.needsResign
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Gated >:3
                let proceedWithInstall: () -> Void = {
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: nil, message: "Installing", preferredStyle: .alert)
                        
                        let activityIndicator = UIActivityIndicatorView(style: .medium)
                        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
                        activityIndicator.startAnimating()
                        
                        alert.view.addSubview(activityIndicator)
                        
                        NSLayoutConstraint.activate([
                            activityIndicator.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor),
                            activityIndicator.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -20)
                        ])
                        
                        self.present(alert, animated: true)
                        
                        checkSigningSetup() { codeSignigSetup in
                            if !codeSignigSetup {
                                alert.dismiss(animated: true)
                                return
                            }
                            
                            DispatchQueue.global().async {
                                if LCUtils.signMachOWithoutPatch(at: URL(fileURLWithPath: executablePath)) {
                                    trust_nxt2_sign((executablePath as NSString).utf8String, [
                                        "org.emexlabs.nyxian.ksurface.kernelextension.loading" : true
                                    ] as CFDictionary, true, nil)
                                    vnode_refresh_with_path(executablePath)
                                    
                                    var ret: kern_return_t = ksurface_fs_install_kext_at_path(bundle.bundlePath);
                                    if ret != 0 {
                                        DispatchQueue.main.async {
                                            alert.dismiss(animated: true) {
                                                NotificationServer.NotifyUser(level: .error, notification: "Failed to install kext: \(String(cString: mach_error_string(ret)))")
                                            }
                                        }
                                    }
                                    
                                    ret = ksurface_fs_load_kext_with_bundleid(bundle.bundleIdentifier, nil)
                                    if ret != 0 {
                                        DispatchQueue.main.async {
                                            alert.dismiss(animated: true) {
                                                NotificationServer.NotifyUser(level: .error, notification: "Failed to inject kext: \(String(cString: mach_error_string(ret)))")
                                            }
                                        }
                                    }
                                    
                                    DispatchQueue.main.async {
                                        self.kexts.removeAll()
                                        do {
                                            let kextURLs: [URL] = try FileManager.default.contentsOfDirectory(at: NXBootstrap.shared().rootURL.appendingPathComponent("/mntfs/kextfs"), includingPropertiesForKeys: [])
                                            for kextURL in kextURLs {
                                                if let kext: PEKext = PEKext(path: kextURL.path) {
                                                    self.kexts.append(kext)
                                                    self.tableView.reloadData()
                                                }
                                            }
                                        } catch {
                                            
                                        }
                                    }
                                    
                                    DispatchQueue.main.async {
                                        alert.dismiss(animated: true)
                                    }
                                } else {
                                    DispatchQueue.main.async {
                                        alert.dismiss(animated: true) {
                                            NotificationServer.NotifyUser(level: .error, notification: "Failed to install kext.")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // The app indeed wants something bruh
                DispatchQueue.main.async {
                    alert.dismiss(animated: true) {
                        if final.isEmpty || !isRootCATrusted {
                            let displayName = bundle.bundleIdentifier ?? "Unknown"
                            let alert = UIAlertController(
                                title: "Install \"\(displayName)\"?",
                                message: nil,
                                preferredStyle: .alert
                            )
                            
                            let fullMessage = NSMutableAttributedString()
                            fullMessage.append(KSurfaceNXT2CreateEntitlementSummary(["org.emexlabs.nyxian.ksurface.kernelextension.loading" : true]))
                            alert.setValue(fullMessage, forKey: "attributedMessage")
                            
                            alert.addAction(UIAlertAction(title: "Install", style: .default) { _ in
                                DispatchQueue.global().async {
                                    _ = proceedWithInstall()
                                }
                            })
                            
                            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                            
                            self.present(alert, animated: true)
                        } else {
                            DispatchQueue.global().async {
                                _ = proceedWithInstall()
                            }
                        }
                    }
                }
                
            } catch {
                NotificationServer.NotifyUser(level: .error, notification: "Failed to install application: \(error.localizedDescription)")
            }
        }
    }
}
