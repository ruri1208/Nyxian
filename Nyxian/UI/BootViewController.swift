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

final class ROMImporter: NSObject, UIDocumentPickerDelegate {
    private var completion: ((URL?) -> Void)?
    
    func present(from viewController: UIViewController, completion: @escaping (URL?) -> Void) {
        self.completion = completion
        
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: true
        )
        
        picker.delegate = self
        picker.allowsMultipleSelection = false
        
        viewController.present(picker, animated: true)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
    ) {
        let url = urls.first
        
        completion?(url)
        completion = nil
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(nil)
        completion = nil
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
}

private typealias NXSlotMainFn = @convention(c) () -> UnsafeMutableRawPointer?
private typealias NXSlotDidAppearFn = @convention(c) () -> Void
private typealias NXSlotCreateWindowFn = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?

private enum SlotLoadResult {
    case loaded(name: String, main: NXSlotMainFn, didAppear: NXSlotDidAppearFn?, createWindow: NXSlotCreateWindowFn?)
    case failed(String)
}

private typealias RestartSelfFn = @convention(c) () -> Void

private func restartSelf() {
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let sym = dlsym(RTLD_DEFAULT, "PERestartSelf") else {
        exit(0)
    }
    unsafeBitCast(sym, to: RestartSelfFn.self)()
}

private func refreshVnode(atPath path: String) -> Bool {
    let fd = open(path, O_RDWR)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    guard unlink(path) == 0 else { return false }
    if fclonefileat(fd, AT_FDCWD, path, 0) == 0 {
        return true
    }
    let copyfd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0o777)
    guard copyfd >= 0 else { return false }
    defer { close(copyfd) }
    lseek(fd, 0, SEEK_SET)
    return fcopyfile(fd, copyfd, nil, copyfile_flags_t(COPYFILE_DATA)) == 0
}

private func flashedSlotURL() -> URL {
    URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Boot/Slot/A")
}

private func lastDlError() -> String {
    if let err = dlerror() { return String(cString: err) }
    return "unknown dyld error"
}

private func loadSlot() -> SlotLoadResult {
    let fm = FileManager.default
    let flashed = flashedSlotURL().appendingPathComponent("main")
    let bundled = Bundle.main.privateFrameworksURL?.appendingPathComponent("SuperSlot.dylib")
    
    let image: URL
    if fm.fileExists(atPath: flashed.path) {
        image = flashed
    } else if let bundled, fm.fileExists(atPath: bundled.path) {
        image = bundled
    } else {
        return .failed("No slot found (no flashed ROM and no bundled SuperSlot.dylib)")
    }
    
    let name = image.path.hasPrefix(Bundle.main.bundlePath) ? "SuperSlot.dylib" : "Slot A"
    
    guard let handle = dlopen(image.path, RTLD_NOW | RTLD_NODELETE | RTLD_GLOBAL) else {
        return .failed("Couldnt load \(name): \(lastDlError())")
    }
    
    guard let mainSym = dlsym(handle, "NXSlotMain") else {
        return .failed("\(name) has no NXSlotMain entry point")
    }
    
    let main = unsafeBitCast(mainSym, to: NXSlotMainFn.self)
    let didAppear = dlsym(handle, "NXSlotDidAppear").map { unsafeBitCast($0, to: NXSlotDidAppearFn.self) }
    let createWindow = dlsym(handle, "NXSlotCreateWindow").map { unsafeBitCast($0, to: NXSlotCreateWindowFn.self) }
    return .loaded(name: name, main: main, didAppear: didAppear, createWindow: createWindow)
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
        let savedData = UserDefaults.standard.object(forKey: "LCCertificateData")
        let savedPassword = UserDefaults.standard.object(forKey: "LCCertificatePassword")
        
        let before = UserDefaults.standard.persistentDomain(forName: id)?.count ?? 0
        c.recoveryLog("Clearing preferences (\(before) keys)...")
        
        UserDefaults.standard.removePersistentDomain(forName: id)
        
        if let savedData = savedData {
            UserDefaults.standard.set(savedData, forKey: "LCCertificateData")
        }
        if let savedPassword = savedPassword {
            UserDefaults.standard.set(savedPassword, forKey: "LCCertificatePassword")
        }
        
        let after = UserDefaults.standard.persistentDomain(forName: id)?.count ?? 0
        if after != 2 {
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
        withHeader: "Wipe all user data?\nTHIS CAN NOT BE UNDONE!",
        instructions: nil,
        footer: nil,
        items: [
            NXRecoveryItem(title: "Cancel") { c in
                if let c = c { recoveryShowMenu(recoveryController: c) }
            },
            NXRecoveryItem(title: "Factory data reset") { c in
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
                restartSelf()
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
                                let slot: URL = flashedSlotURL()
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
                                    if !NXBootSignMachOWithoutPatch(slot.appendingPathComponent(String(file))) {
                                        c.recoveryLogError("ERROR: failed to sign \(file)")
                                        try? FileManager.default.removeItem(at: slot)
                                        return
                                    } else {
                                        c.recoveryLog("signed \(file)")
                                    }
                                }
                                
                                for file in signFiles {
                                    if !refreshVnode(atPath: slot.appendingPathComponent(String(file)).path) {
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
            NXRecoveryItem(title: "Remove flashed ROM (boot SuperSlot)") { c in
                guard let c = c else { return }
                do {
                    try FileManager.default.removeItem(at: flashedSlotURL())
                    c.recoveryLog("flashed ROM removed, next boot uses SuperSlot.dylib")
                } catch {
                    c.recoveryLogError("ERROR: \(errnoDescription(error))")
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

class BootViewController: UIViewController {
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
            
            if mode == 2 {
                DispatchQueue.main.async { self.enterRecovery(error: nil) }
                return
            }
            
            let slot = loadSlot()
            
            DispatchQueue.main.async {
                guard case let .loaded(name, slotMain, slotDidAppear, slotCreateWindow) = slot else {
                    if case let .failed(message) = slot {
                        self.enterRecovery(error: "ERROR: \(message)")
                    }
                    return
                }
                
                guard let raw = slotMain() else {
                    self.enterRecovery(error: "ERROR: \(name) NXSlotMain returned no view controller")
                    return
                }
                let slotRoot = Unmanaged<UIViewController>.fromOpaque(raw).takeRetainedValue()
                
                self.changableStatusBarHidden = false
                UIView.animate(withDuration: 0.3) {
                    self.setNeedsStatusBarAppearanceUpdate()
                }
                
                if let slotCreateWindow, let slotWindow = self.makeSlotWindow(slotCreateWindow) {
                    self.transition(into: slotWindow, root: slotRoot) {
                        slotDidAppear?()
                    }
                } else {
                    self.transition(to: slotRoot) {
                        slotDidAppear?()
                    }
                }
            }
        }
    }
    
    private func makeSlotWindow(_ create: NXSlotCreateWindowFn) -> UIWindow? {
        guard let scene = view.window?.windowScene else { return nil }
        guard let raw = create(Unmanaged.passUnretained(scene).toOpaque()) else { return nil }
        return Unmanaged<UIWindow>.fromOpaque(raw).takeRetainedValue()
    }
    
    private func transition(into slotWindow: UIWindow,
                            root: UIViewController,
                            completion: (() -> Void)? = nil) {
        let hostWindow = view.window
        
        slotWindow.rootViewController = root
        slotWindow.alpha = 0
        slotWindow.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        
        if let presentation = logoView.layer.presentation() {
            logoView.layer.transform = presentation.transform
        }
        logoView.layer.removeAnimation(forKey: "breathe")
        
        let finish = {
            hostWindow?.isHidden = true
            hostWindow?.rootViewController = nil
            if let scene = slotWindow.windowScene {
                (scene.delegate as? SceneDelegate)?.window = slotWindow
            }
            completion?()
        }
        
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.3, animations: {
                slotWindow.alpha = 1
            }, completion: { _ in
                finish()
            })
            return
        }
        
        root.view.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        
        let splashOut = UIViewPropertyAnimator(duration: 0.4, curve: .easeOut) {
            self.logoView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            self.splashView.alpha = 0
            slotWindow.alpha = 1
        }
        
        let appIn = UIViewPropertyAnimator(duration: 0.55, dampingRatio: 1.0) {
            root.view.transform = .identity
        }
        
        appIn.addCompletion { _ in
            finish()
        }
        
        splashOut.startAnimation()
        appIn.startAnimation()
    }
    
    private func enterRecovery(error: String?) {
        let recoveryController = NXRecoveryViewController()
        if let error {
            recoveryController.recoveryLogError(error)
        }
        recoveryShowMenu(recoveryController: recoveryController)
        self.transition(to: recoveryController, style: .crossfade)
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
    
    override var childForStatusBarStyle: UIViewController? {
        splashView.superview == nil ? children.last : nil
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = BootViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
