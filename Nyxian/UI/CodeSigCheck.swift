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
