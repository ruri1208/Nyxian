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

import Foundation
import Combine
import MobileDevelopmentKit

class NXBuilder: NSObject, MDKDriverDelegate, MDKPhaseRunnerDelegate {
    private let project: NXProject
    
    private let database: DebugDatabase
    
    private var phaseRunner: NXPhaseRunner
    private let dependencyScanner: MDKDependencyScanner
    
    private let incrementalBuild: Bool = UserDefaults.standard.object(forKey: "LDEIncrementalBuild") as? Bool ?? true
    private let projectDirty: Bool
    
    private let argsString: String
    
    static var builds: Bool = false
    
    init?(project: NXProject) {
        self.project = project
        self.project.reload()
        
        if !self.project.syncFolderStructureToCache() {
            return nil
        }
        
        self.database = DebugDatabase.getDatabase(ofPath: "\(self.project.cacheURL.path)/debug.json")
        self.database.reuseDatabase()
        
        self.dependencyScanner = MDKDependencyScanner(arguments: self.project.projectConfig.compilerFlags)
        
        guard let swiftFiles = LDEFilesFinder(self.project.url.path, ["swift"], ["Resources","Config"]),
              let codeFiles = LDEFilesFinder(self.project.url.path, ["c","cpp","m","mm"], ["Resources","Config"]) else {
            self.database.addMessage(message: "A fatal error has happened finding code files.", severity: .error)
            self.database.saveDatabase(toPath: project.cacheURL.appendingPathComponent("debug.json").path)
            return nil
        }
        
        var driverFlags: [String] = []
        driverFlags.append(contentsOf: swiftFiles)
        driverFlags.append(contentsOf: codeFiles)
        driverFlags.append("-o")
        driverFlags.append(self.project.machoURL.path)
        
        let phaseEngine: MDKPhaseEngine
        if swiftFiles.isEmpty && codeFiles.isEmpty {
            self.database.addMessage(message: "Nothing to build. No code files were found, please create a code file.", severity: .error)
            self.database.saveDatabase(toPath: project.cacheURL.appendingPathComponent("debug.json").path)
            return nil
        } else if !swiftFiles.isEmpty {
            driverFlags.append(contentsOf: self.project.projectConfig.swiftFlags)
            driverFlags.append("-module-name")
            driverFlags.append(NXMakeContentCodeFriendly(self.project.projectConfig.displayName))
            
            phaseEngine = MDKPhaseEngine(swiftFlags: driverFlags, withOtherClangFlags: self.project.projectConfig.compilerFlags, withOtherLinkerFlags: self.project.projectConfig.linkerFlags)
        } else {
            driverFlags.append(contentsOf: self.project.projectConfig.compilerFlags)
            
            phaseEngine = MDKPhaseEngine(clangFlags: driverFlags, withOtherLinkerFlags: self.project.projectConfig.linkerFlags)
        }
        
        self.argsString = driverFlags.joined(separator: " ")
        
        // Check if the args string matches up
        if self.incrementalBuild,
           let args: String = (try? String(contentsOf: self.project.cacheURL.appendingPathComponent("args.txt"), encoding: .utf8)) {
            self.projectDirty = args != self.argsString
        } else {
            self.projectDirty = true
            self.database.clearDatabase() /* nothing valid anymore */
        }
        
        guard let phaseRunner = NXPhaseRunner(engine: phaseEngine) else {
            return nil
        }
        self.phaseRunner = phaseRunner
        
        super.init()
        
        phaseEngine.delegate = self
        self.phaseRunner.delegate = self
    }
    
    func driver(_ driver: MDKDriver,
                outputPathForInputFile file: MDKFile) -> String? {
        return "\(self.project.cacheURL.path)/\(NXExpectedObjectFileURLForFileURL(NXRelativeURLFromBaseURLToFullURL(self.project.url, file.fileURL)).path)"
    }
    
    func driver(_ driver: MDKDriver,
                skipCompileForInputFile file: MDKFile) -> Bool {
        if !CCFileTypeIsSwiftFile(file.type),
           !self.projectDirty {
            
            let path: String = file.fileURL.path
            let objectPath = "\(self.project.cacheURL.path)/\(NXExpectedObjectFileURLForFileURL(NXRelativeURLFromBaseURLToFullURL(self.project.url, file.fileURL)).path)"
            
            // Checking if the source file is newer than the compiled object file
            guard let sourceDate = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date,
                  let objectDate = try? FileManager.default.attributesOfItem(atPath: objectPath)[.modificationDate] as? Date,
                  objectDate > sourceDate else {
                return false
            }
            
            // Checking if the header files included by the source code are newer than the object file
            guard let headers = self.dependencyScanner.headerFiles(for: file) else {
                return false
            }
            
            for header in headers {
                guard let fileURL = header.fileURL,
                      let headerDate = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date,
                      objectDate > headerDate else {
                    return false
                }
            }
            
            return true
        } else {
            return false
        }
    }
    
    func runner(_ runner: MDKPhaseRunner,
                multithreadingThreadCountFor phase: MDKPhase) -> CFIndex {
        return CFIndex(LDEGetUserSetThreadCount())
    }
    
    func runner(_ runner: MDKPhaseRunner,
                phase: MDKPhase,
                finishedRunning job: MDKJob,
                withResultingDiagnostics diagnostics: [MDKDiagnostic]?,
                withMainSource mainSource: String?,
                wasSuccessful success: Bool) {
        if let diagnostics = diagnostics {
            if job.type == .linker {
                self.database.addDiagnosticMessages(title: "Linker", items: diagnostics, clearPrevious: true)
            } else if let mainSource = mainSource {
                self.database.setFileDebug(ofPath: mainSource, synItems: diagnostics)
            }
        }
    }
    
    func headsup(buildType: NXBuilder.BuildType) throws {
        let type = project.projectConfig.schemeKind
        if(type != .app && type != .utility) {
            throw NSError(domain: "com.cr4zy.nyxian.builder.headsup", code: 1, userInfo: [NSLocalizedDescriptionKey:"Project type \(type) is unknown."])
        }
        
        guard let osVersionNeeded: MDKOSVersion = MDKOSVersion(versionString: project.projectConfig.deploymentTarget) else {
            throw NSError(domain: "com.cr4zy.nyxian.builder.headsup", code: 1, userInfo: [NSLocalizedDescriptionKey:"Target \"\(self.project.projectConfig.displayName ?? "Unknown") (\(self.project.projectConfig.bundleid ?? "Unknown"))\" cannot be build, host version cannot be compared. Version \(project.projectConfig.deploymentTarget!) is not valid."])
        }
        
        
        
        // Nyxian requirement check
        let minimumOSVersion: MDKOSVersion = MDKOSVersion(versionString: NXOSVersion.NXOSVersionSupportedBuildVersions.first)!
        let maximumOSVersion: MDKOSVersion = MDKOSVersion(versionString: NXOSVersion.NXOSVersionSupportedBuildVersions.last)!
        if osVersionNeeded < minimumOSVersion || osVersionNeeded > maximumOSVersion {
            throw NSError(domain: "com.cr4zy.nyxian.builder.headsup", code: 1, userInfo: [NSLocalizedDescriptionKey:"Target \"\(self.project.projectConfig.displayName ?? "Unknown") (\(self.project.projectConfig.bundleid ?? "Unknown"))\" declares deployment target \(osVersionNeeded) which is not supported by this version of Nyxian. This version of Nyxian supports \(minimumOSVersion) up to \(maximumOSVersion)."])
        }
        
        // Project requirement check
        if osVersionNeeded > MDKOSVersion.host,
           buildType == .RunningApp {
            throw NSError(domain: "com.cr4zy.nyxian.builder.headsup", code: 1, userInfo: [NSLocalizedDescriptionKey:"Target \"\(self.project.projectConfig.displayName ?? "Unknown") (\(self.project.projectConfig.bundleid ?? "Unknown"))\" declares deployment target \(osVersionNeeded) which doesn't support the host version \(MDKOSVersion.host). Please update your idevice."])
        }
    }
    
    func clean() throws {
        // now remove what was find
        for file in LDEFilesFinder(
            self.project.url.path,
            ["o","tmp"],
            ["Resources","Config"]
        ) {
            try? FileManager.default.removeItem(atPath: file)
        }
        
        // if payload exists remove it
        if self.project.projectConfig.schemeKind == .app {
            try? FileManager.default.removeItem(atPath: self.project.payloadURL.path)
            try? FileManager.default.removeItem(atPath: self.project.packageURL.path)
        }
    }
    
    func prepare() throws {
        if project.projectConfig.schemeKind == .app {
            try FileManager.default.createDirectory(at: self.project.payloadURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: self.project.resourcesURL, to: self.project.bundleURL)
            
            let infoPlistDataSerialized = try PropertyListSerialization.data(fromPropertyList: self.project.projectConfig.infoDictionary ?? [:], format: .xml, options: 0)
            FileManager.default.createFile(atPath: self.project.bundleURL.appendingPathComponent("Info.plist").path, contents: infoPlistDataSerialized)
        }
    }
    
    func executeRunner() throws {
        if !self.phaseRunner.runPhases() {
            throw NSError(domain: "com.cr4zy.nyxian.builder.runner", code: 1, userInfo: [NSLocalizedDescriptionKey:"Failed to run project."])
        }
        
        do {
            try self.argsString.write(to: self.project.cacheURL.appendingPathComponent("args.txt"), atomically: false, encoding: .utf8)
        } catch {
            throw NSError(domain: "com.cr4zy.nyxian.builder.runner", code: 1, userInfo: [NSLocalizedDescriptionKey:error.localizedDescription])
        }
    }
    
    func install(buildType: NXBuilder.BuildType, executablePathCallback: @escaping (String?) -> Void) throws {
        let spinnerStart = DispatchWorkItem { XCButton.startSpinning() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: spinnerStart)
        defer {
            spinnerStart.cancel()
            XCButton.stopSpinning()
        }
        
        if(buildType == .RunningApp) {
            var success: Bool = false;
            let semaphore = DispatchSemaphore(value: 0)
            checkSigningSetup() { codeSigningSetup in
                success = codeSigningSetup
                semaphore.signal()
            }
            semaphore.wait()
            
            if !success {
                throw NSError(domain: "com.cr4zy.nyxian.builder.install", code: 1, userInfo: [NSLocalizedDescriptionKey:"Code signing is not properly set up. Cannot sign targets."])
            }
            
            if self.project.projectConfig.schemeKind == .app {
                let semaphore = DispatchSemaphore(value: 0)
                var nsError: NSError? = nil
                
                LCUtils.signAppBundle(withZSign: self.project.bundleURL) { [weak self] result, error in
                    guard let self = self else { return }
                    
                    if(self.project.projectConfig.signMachOWithNyxianEntitlements)
                    {
                        macho_after_sign(self.project.machoURL.path, self.project.entitlementsConfig.entitlement)
                    }
                    
                    guard result else {
                        nsError = NSError(domain: "com.cr4zy.nyxian.builder.install", code: 1, userInfo: [NSLocalizedDescriptionKey:error?.localizedDescription ?? "Unknown error happened signing application"])
                        semaphore.signal()
                        return
                    }
                    
                    guard LDEApplicationWorkspace.shared().installApplication(atBundlePath: project.bundleURL.path) else {
                        nsError = NSError(domain: "com.cr4zy.nyxian.builder.install", code: 1, userInfo: [NSLocalizedDescriptionKey:"Unknown error happened installing application"]) // TODO: implement NSError pipeline
                        semaphore.signal()
                        return
                    }
                    
                    semaphore.signal()
                }
                semaphore.wait()
                
                if let nsError = nsError {
                    throw nsError
                }
            } else if self.project.projectConfig.schemeKind == .utility {
                if LCUtils.certificateData == nil {
                    throw NSError(domain: "com.cr4zy.nyxian.builder.install", code: 1, userInfo: [NSLocalizedDescriptionKey:"No code signature present to perform signing, import code signature in Settings > Certificate. Note that the code signature must be the same code signature used to sign Nyxian."])
                }
                
                MachOObject.signBinary(atPath: self.project.machoURL.path)
                macho_after_sign(self.project.machoURL.path, self.project.entitlementsConfig.entitlement)
                
                let path: String? = LDEApplicationWorkspace.shared().fastpathUtility(self.project.machoURL.path)
                if path == nil {
                    throw NSError(domain: "com.cr4zy.nyxian.builder.install", code: 1, userInfo: [NSLocalizedDescriptionKey:"Failed to fastpath install utility"])
                }
                executablePathCallback(path)
            }
        } else {
            if(self.project.projectConfig.signMachOWithNyxianEntitlements)
            {
                macho_after_sign(self.project.machoURL.path, self.project.entitlementsConfig.entitlement)
            }
            if self.project.projectConfig.schemeKind == .app {
                try self.package()
            }
        }
    }
    
    func package() throws {
        zipDirectoryAtPath(project.payloadURL.path, project.packageURL.path, true)
    }
    
    ///
    /// Static function to build the project
    ///
    enum BuildType {
        case RunningApp
        case InstallPackagedApp
    }
    
    static func buildProject(withProject project: NXProject,
                             buildType: NXBuilder.BuildType,
                             completion: @escaping (Bool,String?) -> Void) {
        project.projectConfig.reloadData()
        
        XCButton.resetProgress()
        
        var execPath: String?
        
        DispatchQueue.global().async {
            NXBootstrap.shared().waitTillDone()
            
            var result: Bool = true
            guard let builder: NXBuilder = NXBuilder(
                project: project
            ) else {
                completion(false,nil)
                return
            }
            
            var resetNeeded: Bool = false
            func progressStage(systemName: String? = nil, increment: Double? = nil, handler: () throws -> Void) throws {
                let doReset: Bool = (increment == nil)
                if doReset, resetNeeded {
                    XCButton.resetProgress()
                    resetNeeded = false
                }
                if let systemName = systemName { XCButton.switchImage(withSystemName: systemName, animated: true) }
                try handler()
                if !doReset, let increment = increment {
                    XCButton.incrementProgress(withValue: increment)
                    resetNeeded = true
                }
            }
            
            func progressFlowBuilder(flow: [(String?,Double?,() throws -> Void)]) throws {
                for item in flow { try progressStage(systemName: item.0, increment: item.1, handler: item.2) }
            }
            
            do {
                // prepare
                
                let flow: [(String?,Double?,() throws -> Void)] = [
                    (nil,nil,{ try builder.headsup(buildType: buildType) }),
                    (nil,nil,{ try builder.clean() }),
                    (nil,nil,{ try builder.prepare() }),
                    (nil,nil,{ try builder.executeRunner() }),
                    ("arrow.down.app.fill",nil,{try builder.install(buildType: buildType, executablePathCallback: { path in
                        execPath = path
                    }) })
                ];
                
                // doit
                try progressFlowBuilder(flow: flow)
            } catch {
                try? builder.clean()
                result = false
                builder.database.addMessage(message: error.localizedDescription, severity: .error)
            }
            
            builder.database.saveDatabase(toPath: project.cacheURL.appendingPathComponent("debug.json").path)
            
            completion(result, execPath)
        }
    }
}

func buildProjectWithArgumentUI(targetViewController: UIViewController,
                                project: NXProject,
                                buildType: NXBuilder.BuildType,
                                completion: @escaping (Bool,String?) -> Void = { _,_ in }) {
    autoreleasepool {
        targetViewController.navigationItem.titleView?.isUserInteractionEnabled = false
        XCButton.switchImageSync(withSystemName: "hammer.fill", animated: false)
        guard let oldBarButtons: [UIBarButtonItem] = targetViewController.navigationItem.rightBarButtonItems else { return }
        
        let barButton: UIBarButtonItem = UIBarButtonItem(customView: XCButton.shared())
        
        NXBuilder.builds = true
        targetViewController.navigationItem.setRightBarButtonItems([barButton], animated: true)
        targetViewController.navigationItem.setHidesBackButton(true, animated: true)
        
        NXDocumentManager.shared().saveAll {
            NXDocumentManager.shared().changeAllLockState(toBoolean: true)
            NXBuilder.buildProject(withProject: project, buildType: buildType) { result, fastPath in
                NXDocumentManager.shared().changeAllLockState(toBoolean: false)
                DispatchQueue.main.async {
                    targetViewController.navigationItem.setRightBarButtonItems(oldBarButtons, animated: true)
                    targetViewController.navigationItem.setHidesBackButton(false, animated: true)
                    targetViewController.navigationController?.navigationBar.isUserInteractionEnabled = true
                    targetViewController.navigationItem.titleView?.isUserInteractionEnabled = true
                    
                    NXBuilder.builds = false
                    
                    if !result {
                        let loggerView = UINavigationController(rootViewController: UIDebugViewController(project: project))
                        loggerView.modalPresentationStyle = .formSheet
                        targetViewController.present(loggerView, animated: true)
                    } else if buildType == .InstallPackagedApp {
                        if project.projectConfig.schemeKind == .app {
                            share(url: project.packageURL, remove: true)
                        } else {
                            share(url: project.machoURL, remove: true)
                        }
                    }
                    
                    completion(result, fastPath)
                }
            }
        }
    }
}
