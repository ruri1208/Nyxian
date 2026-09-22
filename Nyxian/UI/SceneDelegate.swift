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
import UIOnboarding
import UniformTypeIdentifiers

final class ROMImporter: NSObject, UIDocumentPickerDelegate {

    private var completion: ((URL?) -> Void)?

    func present(
        from viewController: UIViewController,
        completion: @escaping (URL?) -> Void
    ) {
        self.completion = completion

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: true
        )

        picker.delegate = self
        picker.allowsMultipleSelection = false

        viewController.present(picker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        let url = urls.first

        completion?(url)
        completion = nil
    }

    func documentPickerWasCancelled(
        _ controller: UIDocumentPickerViewController
    ) {
        completion?(nil)
        completion = nil
    }
}

func getTopViewController(base: UIViewController? = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .flatMap { $0.windows }
    .first(where: { $0.isKeyWindow })?.rootViewController) -> UIViewController? {
    
    if let nav = base as? UINavigationController {
        return getTopViewController(base: nav.visibleViewController)
    }
    
    if let tab = base as? UITabBarController {
        return getTopViewController(base: tab.selectedViewController)
    }
    
    if let presented = base?.presentedViewController {
        return getTopViewController(base: presented)
    }
    
    return base
}

fileprivate func errorFallback(title: String, message: String) {
    let alert = UIAlertController(
        title: title,
        message: message,
        preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "Close", style: .default))

    DispatchQueue.main.async {
        NXWindowServer.shared().rootViewController?.present(
            alert,
            animated: true
        )
    }
}

@objc class NXApplicationState: NSObject {
    @objc static var extensionExists: Bool = {
        return PEGetLiveProcessBundle() != nil
    }()
    
    @objc static var extensionCorrectlyEntitled: Bool = {
        return PEExtensionHasGetTaskAllowed()
    }()
    
    @objc static var extensionLessMode: Bool = {
        return !extensionExists || !extensionCorrectlyEntitled;
    }()
    
    private static var actualLoadKernelExtensions: Bool = false
    @objc static var loadKernelExtensions: Bool {
        get {
            if UserDefaults.standard.bool(forKey: "LDEDisableKernelExtensionsForce") {
                UserDefaults.standard.removeObject(forKey: "LDEDisableKernelExtensionsForce")
                return false
            }
            return self.actualLoadKernelExtensions;
        }
        set {
            if UserDefaults.standard.bool(forKey: "LDEDisableKernelExtensionsForce") {
                return
            }
            actualLoadKernelExtensions = newValue
        }
    }
    
    @objc static var fileListRequiresToSendRequests: Bool = false
    
    @objc static func restartAppWithoutKEXTLoadingEnabled() {
        UserDefaults.standard.set(true, forKey: "LDEDisableKernelExtensionsForce")
        PERestartSelf()
    }
}

func checkSigningSetup(completionHandler: @escaping (Bool) -> Void = { _ in }, showAlert: Bool = true) {
    if !NXApplicationState.extensionExists {
        if showAlert {
            errorFallback(title: "Extension Not Found", message: """
The required NSExtension could not be found.

Make sure the app was installed with its extension intact and that it wasn't removed during signing or installation.

App is now in extension-less mode, meaning apps cannot run within Nyxian until the problem has been resolved.
""")
        }
        completionHandler(false)
        return
    }
    
    if !NXApplicationState.extensionCorrectlyEntitled {
        if showAlert {
            errorFallback(title: "Unsupported Provisioning Profile", message: """
Extension doesn't have the "get-task-allow" entitlement.

Distribution certificates are not supported. You must use a Developer certificate issued by Apple.

The 7 day certificate is a Developer certificate.

App is now in extension-less mode, meaning apps cannot run within Nyxian until the problem has been resolved.
""")
        }
        completionHandler(false)
        return
    }
    
    LCUtils.validateCertificate { status, someWords in
        completionHandler(status == 0)
        if status == 0 || !showAlert {
            return
        }
        
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: {
                    switch status {
                    default:
                        return "Signing Isn't Set Up"
                    }
                }(),
                message: {
                    switch status {
                    default:
                        return "Nyxian needs a signing certificate to install and launch the apps you build. Without one you can still write and compile code, but you won't be able to run it on this device."
                    }
                }(), preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
            alert.addAction(UIAlertAction(title: "Set Up Signing", style: .default) { _ in
                let importPopup: CertificateImporter = CertificateImporter(style: .insetGrouped)
                let importSettings: UINavigationController = UINavigationController(rootViewController: importPopup)
                importSettings.modalPresentationStyle = .formSheet
                
                // dynamic size
                if UIDevice.current.userInterfaceIdiom == .phone {
                    if let sheet = importSettings.sheetPresentationController {
                        sheet.animateChanges {
                            sheet.detents = [
                                .custom { _ in
                                    return 200
                                }
                            ]
                        }
                        
                        sheet.prefersGrabberVisible = true
                    }
                }
                
                getTopViewController()?.present(importSettings, animated: true)
            })
            
            getTopViewController()?.present(alert, animated: true)
        }
    }
}

struct UIOnboardingHelper {
    static func setUpIcon() -> UIImage {
        if #unavailable(iOS 26.0) {
            return .init(named: "IconPreviewDefaultOld")!
        } else {
            let object = LDEApplicationObject(nsBundle: Bundle.main)!
            return Gib26Icon(object.icon, object.darkIcon, CGSize(width: 1024, height: 1024), UIScreen.main.scale)
        }
    }
    
    static func setUpFirstTitleLine() -> NSMutableAttributedString {
        .init(string: "Welcome to", attributes: [.foregroundColor: UIColor.label])
    }
    
    static func setUpSecondTitleLine() -> NSMutableAttributedString {
        .init(string: Bundle.main.displayName ?? "Nyxian", attributes: [
            .foregroundColor: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.79, green: 0.66, blue: 0.89, alpha: 1.0) : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0) }
        ])
    }
    
    static func setUpFeatures() -> Array<UIOnboardingFeature> {
        return .init([
            .init(icon: UIImage(systemName: "hammer.fill")!,
                iconTint: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.55, green: 0.78, blue: 0.98, alpha: 1.0) : UIColor(red: 0.30, green: 0.58, blue: 0.88, alpha: 1.0) },
                title: "Development",
                description: "A full development environment supporting Swift, C, C++, Objective-C and Objective-C++ that runs on any iOS 18.0+ iPhone or iPad."),
            .init(icon: UIImage(systemName: "wrench.and.screwdriver.fill")!,
                iconTint: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.78, green: 0.71, blue: 0.95, alpha: 1.0) : UIColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1.0) },
                title: "MobileDevelopmentKit",
                description: "A completely FOSS LLVM, Swift, Clang, and LLD toolchain running natively on iOS, powering compilation and linkage completely on-device without any overpriced cloud services or subscriptions."),
            .init(icon: UIImage(systemName: "cpu.fill")!,
                iconTint: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.60, green: 0.88, blue: 0.80, alpha: 1.0) : UIColor(red: 0.30, green: 0.68, blue: 0.58, alpha: 1.0) },
                title: "Native Performance",
                description: "A custom micro kernel called ksurface providing real process management, mach IPC(task ports through task_for_pid() for example), POSIX semantics, custom kernel extensions so you can extend ksurface your self and even a shimcache so you can add more rebinds in the userspace to syscalls you or someone else fixed and that directly on your restricted iOS device for your projects."),
            .init(icon: UIImage(systemName: "exclamationmark.triangle.fill")!,
                iconTint: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.98, green: 0.82, blue: 0.45, alpha: 1.0) : UIColor(red: 0.85, green: 0.60, blue: 0.12, alpha: 1.0) },
                title: "Warning",
                description: "This is a beta version of Nyxian, so don't expect a product without bugs, please be kind and respectful, it is very hard to develop this kind of software. Please report any kinds of issues and ask any question over at our github we have a lot of time and passion answering your questions and making Nyxian better."),
        ])
    }
    
    static func setUpNotice() -> UIOnboardingTextViewConfiguration {
        return .init(icon: UIImage(systemName: "heart.fill")!,
                     text: "Contributions, feedback, and stars keep the project alive.",
                     linkTitle: "Contribute on GitHub",
                     link: "https://github.com/emexlab/Nyxian",
                     linkColor: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.79, green: 0.66, blue: 0.89, alpha: 1.0) : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0) })
    }
    
    static func setUpButton() -> UIOnboardingButtonConfiguration {
        let lightBackground = LDETheme.currentTheme!.backgroundColor.resolvedColor(with: .init(userInterfaceStyle: .light))
        
        return .init(title: "Continue", titleColor: lightBackground, backgroundColor: UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor(red: 0.79, green: 0.66, blue: 0.89, alpha: 1.0) : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0) })
    }
}

enum BootFlag: String, CaseIterable {
    case kextLoading = "nyxian.boot.kextLoading"
    case logObfucation = "nyxian.boot.log.obfuscated"
    case sandboxFilesystem = "nyxian.boot.sandbox.filesystems"
    
    var title: String {
        switch self {
            case .kextLoading: return "Load kexts at boot"
            case .logObfucation: return "Obfuscate Log"
            case .sandboxFilesystem: return "Filesystem Sandbox"
        }
    }
    
    var defaultValue: Bool {
        switch self {
            case .kextLoading: return true
            case .logObfucation: return true
            case .sandboxFilesystem: return true
        }
    }
}

enum BootConfig {
    fileprivate static let entitlementModeKey = "nyxian.boot.entitlements.mode"
    
    static func registerDefaults() {
        var defaults: [String: Any] = Dictionary(uniqueKeysWithValues: BootFlag.allCases.map { ($0.rawValue, $0.defaultValue) })
        defaults[entitlementModeKey] = EnforcementMode.enforcing.rawValue
        
        UserDefaults.standard.register(defaults: defaults)
    }
    
    static var entitlementMode: EnforcementMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: entitlementModeKey),
                  let mode = EnforcementMode(rawValue: raw) else {
                return .enforcing
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: entitlementModeKey)
        }
    }
    
    static func isEnabled(_ flag: BootFlag) -> Bool {
        UserDefaults.standard.bool(forKey: flag.rawValue)
    }
    
    static func toggle(_ flag: BootFlag) {
        UserDefaults.standard.set(!isEnabled(flag), forKey: flag.rawValue)
    }
}

enum EnforcementMode: String, CaseIterable {
    case enforcing
    case permissive
    case disabled
    
    var badge: String {
        switch self {
            case .enforcing: return "E"
            case .permissive: return "P"
            case .disabled: return "-"
        }
    }
    
    var next: EnforcementMode {
        let all = EnforcementMode.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
    
    var kernelMode: PEEnforcementMode {
        switch self {
            case .enforcing: return .enforcing
            case .permissive: return .permissive
            case .disabled: return .disabled
        }
    }
}

private func bootConfigItems(returningTo parent: @escaping (NXRecoveryViewController) -> Void) -> [NXRecoveryItem] {
    func label(_ flag: BootFlag) -> String {
        "[\(BootConfig.isEnabled(flag) ? "X" : " ")] \(flag.title)"
    }
    
    func reload(_ c: NXRecoveryViewController) {
        let keep = c.recoveryIndex
        c.recoveryItems = bootConfigItems(returningTo: parent)
        c.recoveryIndex = keep
    }
    
    var items: [NXRecoveryItem] = [
        NXRecoveryItem(title: "../") { c in
            if let c = c {
                parent(c)
            }
        }
    ]
    
    for flag in BootFlag.allCases {
        items.append(NXRecoveryItem(title: label(flag)) { c in
            guard let c = c else { return }
            
            BootConfig.toggle(flag)
            reload(c)
            
            let state = BootConfig.isEnabled(flag) ? "enabled" : "disabled"
            c.recoveryLog("\(flag.title): \(state)")
        })
    }
    
    let mode = BootConfig.entitlementMode
    items.append(NXRecoveryItem(title: "[\(mode.badge)] Entitlements: \(mode.rawValue)") { c in
        guard let c = c else { return }
        
        BootConfig.entitlementMode = BootConfig.entitlementMode.next
        reload(c)
        
        switch BootConfig.entitlementMode {
            case .enforcing: c.recoveryLog("entitlements: enforcing")
            case .permissive: c.recoveryLogError("entitlements: permissive, denials logged, not blocked")
            case .disabled: c.recoveryLogError("entitlements: DISABLED, no checks will run")
        }
    })
    
    return items
}

func recoveryShowBootConfig(recoveryController c: NXRecoveryViewController) {
    c.enterRecovery(
        withHeader: "Boot Configuration",
        instructions: nil,
        footer: nil,
        items: bootConfigItems(returningTo: { parent in
            recoveryShowMenu(recoveryController: parent)
        }),
        onSelect: nil,
        onMove: nil
    )
}

private struct WipeFailure {
    let path: String
    let reason: String
}

private struct WipeStats {
    var removedFiles = 0
    var removedDirectories = 0
    var bytes: Int64 = 0
    var failures: [WipeFailure] = []
}

private let maxFailuresShown = 3

private let wipeResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .totalFileAllocatedSizeKey,
]

private func errnoDescription(_ error: Error) -> String {
    let ns = error as NSError
    if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain {
        return String(cString: strerror(Int32(u.code)))
    }
    return ns.localizedDescription
}

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func relativePath(_ url: URL, home: String) -> String {
    let path = url.standardizedFileURL.path
    return path.hasPrefix(home) ? String(path.dropFirst(home.count)) : path
}

private func recordFailure(_ url: URL, _ error: Error, home: String, stats: inout WipeStats) {
    stats.failures.append(WipeFailure(path: relativePath(url, home: home), reason: errnoDescription(error)))
}

private func removeTree(_ url: URL,
                        keeping keep: Set<String>,
                        isRoot: Bool,
                        home: String,
                        stats: inout WipeStats) -> Bool {
    let fm = FileManager.default
    let values = try? url.resourceValues(forKeys: Set(wipeResourceKeys))
    let isSymlink = values?.isSymbolicLink ?? false
    let isRealDirectory = (values?.isDirectory ?? false) && !isSymlink
    
    var ok = true
    if isRealDirectory {
        let children: [URL]
        do {
            children = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: wipeResourceKeys, options: [])
        } catch {
            recordFailure(url, error, home: home, stats: &stats)
            return false
        }
        
        for child in children {
            let childOK = removeTree(child, keeping: keep, isRoot: false, home: home, stats: &stats)
            ok = ok && childOK
        }
    }
    
    if isRoot || keep.contains(url.standardizedFileURL.path) || !ok {
        return ok
    }
    
    let size = Int64(values?.totalFileAllocatedSize ?? 0)
    do {
        try fm.removeItem(at: url)
    } catch {
        recordFailure(url, error, home: home, stats: &stats)
        return false
    }
    
    if isRealDirectory {
        stats.removedDirectories += 1
    } else {
        stats.removedFiles += 1
        stats.bytes += size
    }
    
    return true
}

func recoveryWipeData(_ c: NXRecoveryViewController) {
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
    let homePath = home.path
    
    let targets = ["Documents", "Library", "tmp"].map {
        home.appendingPathComponent($0, isDirectory: true)
    }
    
    let keep: Set<String> = [
        home.appendingPathComponent("Library/Caches").standardizedFileURL.path,
        home.appendingPathComponent("Library/Preferences").standardizedFileURL.path,
    ]
    
    c.recoveryLogMax = max(c.recoveryLogMax, 16)
    
    let started = CFAbsoluteTimeGetCurrent()
    c.recoveryLog("\n-- Wiping data...")
    
    var prefsOK = true
    if let id = Bundle.main.bundleIdentifier {
        let before = UserDefaults.standard.persistentDomain(forName: id)?.count ?? 0
        c.recoveryLog("Clearing preferences (\(before) keys)...")
        
        UserDefaults.standard.removePersistentDomain(forName: id)
        
        let after = UserDefaults.standard.persistentDomain(forName: id)?.count ?? 0
        if after != 0 {
            c.recoveryLogError("  failed: \(after) keys remain")
            prefsOK = false
        }
    } else {
        c.recoveryLogError("  failed: no bundle identifier")
        prefsOK = false
    }
    
    DispatchQueue.global(qos: .userInitiated).async {
        var success = prefsOK
        var totalBytes: Int64 = 0
        
        for dir in targets {
            let name = dir.lastPathComponent
            DispatchQueue.main.async { c.recoveryLog("Formatting /\(name)...") }
            
            var stats = WipeStats()
            let ok = removeTree(dir, keeping: keep, isRoot: true, home: homePath, stats: &stats)
            success = success && ok
            totalBytes += stats.bytes
            
            let summary = "  \(stats.removedFiles) files, \(stats.removedDirectories) dirs, \(formatBytes(stats.bytes))"
            let shown = Array(stats.failures.prefix(maxFailuresShown))
            let hidden = stats.failures.count - shown.count
            
            DispatchQueue.main.async {
                c.recoveryLog(summary)
                for f in shown {
                    c.recoveryLogError("  failed: \(f.path): \(f.reason)")
                }
                if hidden > 0 {
                    c.recoveryLogError("  ... and \(hidden) more (see system log)")
                }
            }
        }
        
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started)
        let tail = "(\(formatBytes(totalBytes)) in \(elapsed)s)"
        
        DispatchQueue.main.async {
            if success {
                c.recoveryLog("Data wipe complete. \(tail)")
            } else {
                c.recoveryLogError("Data wipe failed. \(tail)")
            }
        }
    }
}

func recoveryWipeCache(_ c: NXRecoveryViewController) {
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
    let homePath = home.path
    
    let targets = ["Library/Caches", "tmp"].map {
        home.appendingPathComponent($0, isDirectory: true)
    }
    
    let keep: Set<String> = [
        home.appendingPathComponent("Library/Caches").standardizedFileURL.path,
        home.appendingPathComponent("Library/Preferences").standardizedFileURL.path,
    ]
    
    c.recoveryLogMax = max(c.recoveryLogMax, 16)
    
    let started = CFAbsoluteTimeGetCurrent()
    c.recoveryLog("\n-- Wiping cache...")
    
    DispatchQueue.global(qos: .userInitiated).async {
        var success = true
        var totalBytes: Int64 = 0
        
        for dir in targets {
            let name = dir.lastPathComponent
            DispatchQueue.main.async { c.recoveryLog("Formatting /\(name)...") }
            
            var stats = WipeStats()
            let ok = removeTree(dir, keeping: keep, isRoot: true, home: homePath, stats: &stats)
            success = success && ok
            totalBytes += stats.bytes
            
            let summary = "  \(stats.removedFiles) files, \(stats.removedDirectories) dirs, \(formatBytes(stats.bytes))"
            let shown = Array(stats.failures.prefix(maxFailuresShown))
            let hidden = stats.failures.count - shown.count
            
            DispatchQueue.main.async {
                c.recoveryLog(summary)
                for f in shown {
                    c.recoveryLogError("  failed: \(f.path): \(f.reason)")
                }
                if hidden > 0 {
                    c.recoveryLogError("  ... and \(hidden) more (see system log)")
                }
            }
        }
        
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started)
        let tail = "(\(formatBytes(totalBytes)) in \(elapsed)s)"
        
        DispatchQueue.main.async {
            if success {
                c.recoveryLog("Cache wipe complete. \(tail)")
            } else {
                c.recoveryLogError("Cache wipe failed. \(tail)")
            }
        }
    }
}

func recoveryConfirmWipe(recoveryController c: NXRecoveryViewController) {
    c.enterRecovery(
        withHeader: "Wipe all user data?\n THIS CAN NOT BE UNDONE!",
        instructions: nil,
        footer: nil,
        items: [
            NXRecoveryItem(title: " Cancel") { c in
                if let c = c { recoveryShowMenu(recoveryController: c) }
            },
            NXRecoveryItem(title: " Factory data reset") { c in
                guard let c = c else { return }
                recoveryShowMenu(recoveryController: c)
                recoveryWipeData(c)
            },
        ],
        onSelect: nil,
        onMove: nil
    )
}

// Cuz it is weak
let romImporter: ROMImporter = ROMImporter()

func recoveryShowMenu(recoveryController: NXRecoveryViewController) {
    recoveryController.enterRecovery(
        withHeader: "Nyxian Recovery\n\(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") ?? "UNKNOWN") \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "0.0.0") \"Scriptura\" Beta (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "UNKNOWN"))",
        instructions: nil,
        footer: nil,
        items: [
            NXRecoveryItem(title: "Reboot system now") { c in
                PERestartSelf()
            },
            NXRecoveryItem(title: "Boot Configuration") { c in
                if let c = c {
                    recoveryShowBootConfig(recoveryController: c)
                }
            },
            NXRecoveryItem(title: "Wipe data / factory reset") { c in
                if let c = c {
                    recoveryConfirmWipe(recoveryController: c)
                }
            },
            NXRecoveryItem(title: "Wipe cache") { c in
                if let c = c {
                    recoveryWipeCache(c)
                }
            },
            NXRecoveryItem(title: "Flash ROM") { c in
                if let c = c {
                    romImporter.present(from: c) { url in
                        if let url = url {
                            do {
                                let slot: URL = URL(fileURLWithPath: "\(NSHomeDirectory())").appendingPathComponent("/Library/Boot/Slot/A")
                                c.recoveryLog("\n-- Flashing rom...")
                                c.recoveryLog("selected rom: \(url.lastPathComponent)")
                                try? FileManager.default.removeItem(at: slot)
                                try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true, attributes: [:])
                                
                                if !unzipArchiveAtPathWithoutParentDirectory(url.path, slot.path) {
                                    c.recoveryLogError("ERROR: failed to extract ROM")
                                    try? FileManager.default.removeItem(at: slot)
                                    return
                                }
                                
                                c.recoveryLog("extracted rom")
                                
                                let contents = try String(contentsOfFile: slot.appendingPathComponent("manifest.sign").path, encoding: .utf8)
                                let signFiles = contents.split(separator: "\n")
                                
                                for file in signFiles {
                                    if !LCUtils.signMachOWithoutPatch(at: slot.appendingPathComponent(String(file))) {
                                        c.recoveryLogError("ERROR: failed to sign \(file)")
                                        try? FileManager.default.removeItem(at: slot)
                                        return
                                    } else {
                                        c.recoveryLog("signed \(file)")
                                    }
                                }
                                
                                for file in signFiles {
                                    if !vnode_refresh_with_path(slot.appendingPathComponent(String(file)).path) {
                                        c.recoveryLogError("ERROR: failed to refresh \(file)")
                                        try? FileManager.default.removeItem(at: slot)
                                        return
                                    } else {
                                        c.recoveryLog("refreshed \(file)")
                                    }
                                }
                            } catch {
                                c.recoveryLogError("ERROR: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            },
            NXRecoveryItem(title: "Nyxian Files") { c in
                c?.enterFileBrowser(atPath: NSHomeDirectory(), root: NSHomeDirectory(), header: "Nyxian Files", onBack: { recovery in
                    if let recovery = recovery {
                        recoveryShowMenu(recoveryController: recovery)
                    }
                }, onFile: { path,name,controller in
                })
            },
            NXRecoveryItem(title: "System Files") { c in
                c?.enterFileBrowser(atPath: "/", root: "/", header: "System Files", onBack: { recovery in
                    if let recovery = recovery {
                        recoveryShowMenu(recoveryController: recovery)
                    }
                }, onFile: { path,name,controller in
                })
            },
            NXRecoveryItem(title: "Power Off") { c in
                UIApplication.shared.perform(Selector("suspend"))
                exit(0)
            },
        ],
        onSelect: nil,
        onMove: nil
    )
}

class BootViewController: UIViewController, UITabBarControllerDelegate, UIOnboardingViewControllerDelegate {
    private let splashView = UIView()
    private let logoView = UIImageView()
    
    private enum BootTransition {
        case zoomThrough
        case crossfade
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        BootConfig.registerDefaults()
        
        self.view.backgroundColor = .systemBackground
        
        splashView.backgroundColor = self.view.backgroundColor
        splashView.frame = self.view.bounds
        splashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(splashView)
        
        logoView.image = UIImage(named: "EmexLogo")
        logoView.contentMode = .scaleAspectFit
        logoView.translatesAutoresizingMaskIntoConstraints = false
        
        splashView.addSubview(logoView)
        
        NSLayoutConstraint.activate([
            logoView.centerYAnchor.constraint(equalTo: splashView.centerYAnchor),
            logoView.centerXAnchor.constraint(equalTo: splashView.centerXAnchor),
            logoView.heightAnchor.constraint(equalToConstant: 125),
            logoView.widthAnchor.constraint(equalToConstant: 125),
        ])
        
        DispatchQueue.global(qos: .utility).async {
            let mode = NXVolumeButtonMonitor.scan(for: 1.0)
            NXVolumeButtonMonitor.disarm()
            
            NXApplicationState.loadKernelExtensions = BootConfig.isEnabled(.kextLoading)
            
            DispatchQueue.main.async {
                if mode == 2 {
                    let recoveryController = NXRecoveryViewController()
                    recoveryShowMenu(recoveryController: recoveryController)
                    self.transition(to: recoveryController, style: .crossfade)
                    return
                }
                
                let slot: URL = URL(fileURLWithPath: "\(NSHomeDirectory())").appendingPathComponent("/Library/Boot/Slot/A")
                if FileManager.default.fileExists(atPath: slot.path) {
                    let handle = dlopen(slot.appendingPathComponent("main").path, RTLD_NOW | RTLD_NODELETE | RTLD_GLOBAL)
                    
                    if handle == nil {
                        let recoveryController = NXRecoveryViewController()
                        recoveryController.recoveryLogError("ERROR: Couldnt load ROM: \(String(cString: dlerror()))")
                        recoveryShowMenu(recoveryController: recoveryController)
                        self.transition(to: recoveryController, style: .crossfade)
                        return
                    } else {
                        return
                    }
                }
                
                self.changableStatusBarHidden = false
                UIView.animate(withDuration: 0.3) {
                    self.setNeedsStatusBarAppearanceUpdate()
                }
                
                if !trust_enforcement_set_mode(BootConfig.entitlementMode.kernelMode) {
                    assertionFailure("trust_enforcement_mode() was read before trust_enforcement_set_mode()")
                }
                
                if !klog_set_obfuscation(BootConfig.isEnabled(.logObfucation)) {
                    assertionFailure("klog_obfuscation_enabled() was read before klog_set_obfuscation()")
                }
                
                PEUserspaceManager.shared().boot(withKextLoadingEnabled: NXApplicationState.loadKernelExtensions)
                NXBootstrap.shared().bootstrap()
                
                // swizzle swizzle swizzle :3
                UIViewController.swizzlePresentAndDismissOnce
                UIBarButtonItem.swizzleBarButtonitem
                RevertUI()
                
                let themedTabViewController: NXUITabBarController = NXUITabBarController()
                
                let contentViewController: ContentViewController = ContentViewController()
                let settingsViewController: NXSettingsTableViewController = NXSettingsTableViewController()
                
                let contentNavigationController: UINavigationController = UINavigationController(rootViewController: contentViewController)
                let settingsNavigationController: UINavigationController = UINavigationController(rootViewController: settingsViewController)
                
                contentNavigationController.tabBarItem = UITabBarItem(title: "Projects", image: UIImage(systemName: "square.grid.2x2.fill"), tag: 0)
                settingsNavigationController.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gear"), tag: 1)
                
                var viewControllers: [UIViewController] = [contentNavigationController, settingsNavigationController]
                
                if UIDevice.current.userInterfaceIdiom == .phone {
                    if #available(iOS 26.0, *) {
                        if !NXApplicationState.extensionLessMode {
                            let fakeViewController: UIViewController = UIViewController()
                            fakeViewController.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 2)
                            fakeViewController.tabBarItem.title = "Switcher"
                            fakeViewController.tabBarItem.image = UIImage(systemName: "iphone.app.switcher")
                            viewControllers.append(fakeViewController)
                        }
                    }
                }
                
                themedTabViewController.viewControllers = viewControllers
                themedTabViewController.delegate = self
                
                self.transition(to: themedTabViewController) {
                    if let _: NSNumber = UserDefaults.standard.object(forKey: "NXOnboardingSentinel") as? NSNumber {
                        checkSigningSetup()
                        return
                    }
                    
                    let onboardingConfiguration = UIOnboardingViewConfiguration(appIcon: UIOnboardingHelper.setUpIcon(), firstTitleLine: UIOnboardingHelper.setUpFirstTitleLine(), secondTitleLine: UIOnboardingHelper.setUpSecondTitleLine(), features: UIOnboardingHelper.setUpFeatures(), textViewConfiguration: UIOnboardingHelper.setUpNotice(), buttonConfiguration: UIOnboardingHelper.setUpButton())
                    let onboardingController: UIOnboardingViewController = UIOnboardingViewController(withConfiguration: onboardingConfiguration)
                    onboardingController.delegate = self
                    onboardingController.backgroundColor = LDETheme.currentTheme!.backgroundColor
                    onboardingController.modalTransitionStyle = .crossDissolve
                    
                    themedTabViewController.present(onboardingController, animated: true)
                }
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startBreathing()
    }
    
    private func startBreathing() {
        guard !UIAccessibility.isReduceMotionEnabled,
              splashView.superview != nil,
              logoView.layer.animation(forKey: "breathe") == nil else { return }
        
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 0.94
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        logoView.layer.add(pulse, forKey: "breathe")
    }
    
    private func transition(to child: UIViewController,
                            style: BootTransition = .zoomThrough,
                            completion: (() -> Void)? = nil) {
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(child.view, belowSubview: splashView)
        child.view.layoutIfNeeded()
        
        if let presentation = logoView.layer.presentation() {
            logoView.layer.transform = presentation.transform
        }
        logoView.layer.removeAnimation(forKey: "breathe")
        
        let finish = {
            self.splashView.removeFromSuperview()
            child.didMove(toParent: self)
            completion?()
        }
        
        if style == .crossfade || UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.3, animations: {
                self.splashView.alpha = 0
            }, completion: { _ in
                finish()
            })
            return
        }
        
        child.view.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        
        let splashOut = UIViewPropertyAnimator(duration: 0.4, curve: .easeOut) {
            self.logoView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            self.splashView.alpha = 0
        }
        
        let appIn = UIViewPropertyAnimator(duration: 0.55, dampingRatio: 1.0) {
            child.view.transform = .identity
        }
        
        appIn.addCompletion { _ in
            finish()
        }
        
        splashOut.startAnimation()
        appIn.startAnimation()
    }
    
    var changableStatusBarHidden = true
    override var prefersStatusBarHidden: Bool {
        return self.changableStatusBarHidden
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if tabBarController.selectedViewController === viewController && NXBuilder.builds {
            return false
        }
        if viewController.tabBarItem.tag == 2 {
            NXWindowServer.shared().showAppSwitcherExternal()
            return false
        }
        return true
    }
    
    func didFinishOnboarding(onboardingViewController: UIOnboarding.UIOnboardingViewController) {
        onboardingViewController.modalTransitionStyle = .crossDissolve
        onboardingViewController.dismiss(animated: true, completion: nil)
        
        UserDefaults.standard.set(NSNumber(booleanLiteral: true), forKey: "NXOnboardingSentinel")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            checkSigningSetup()
        }
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: NXWindowServer?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        self.window = NXWindowServer.shared(with: windowScene)
        if self.window == nil {
            return;
        }
        
        self.window?.rootViewController = BootViewController()
        
        self.window?.makeKeyAndVisible()
        
        return
    }
}
