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

func checkSigningSetup(completionHandler: @escaping (Bool) -> Void = { _ in }, showAlert: Bool = true) {
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
        return .init(named: "IconPreviewDefaultOld")!
    }
    
    static func setUpFirstTitleLine() -> NSMutableAttributedString {
        .init(string: "Welcome to", attributes: [.foregroundColor: UIColor.label])
    }
    
    static func setUpSecondTitleLine() -> NSMutableAttributedString {
        .init(string: Bundle.main.displayName ?? "Nyxian", attributes: [
            .foregroundColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.85, green: 0.74, blue: 0.93, alpha: 1.0)
                : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0)
            }
        ])
    }
    
    static func setUpFeatures() -> Array<UIOnboardingFeature> {
        return .init([
            // I was lazy so I just wrapped them in like that
            .init(icon: UIImage(systemName: "hammer.fill")!,
                  iconTint: UIColor { trait in trait.userInterfaceStyle == .dark
                      ? UIColor(red: 0.55, green: 0.78, blue: 0.98, alpha: 1.0)
                      : UIColor(red: 0.30, green: 0.58, blue: 0.88, alpha: 1.0)
                  },
                  title: "Development",
                  description: "A full development environment supporting Swift, C, C++, Objective-C and Objective-C++ that runs on any iOS 18.4+ iPhone or iPad."),
            
                .init(icon: UIImage(systemName: "wrench.and.screwdriver.fill")!,
                      iconTint: UIColor { trait in
                          trait.userInterfaceStyle == .dark
                          ? UIColor(red: 0.78, green: 0.71, blue: 0.95, alpha: 1.0)
                          : UIColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1.0)
                      },
                      title: "MobileDevelopmentKit",
                      description: "A completely FOSS LLVM, Swift, Clang, and LLD toolchain running natively on iOS, powering compilation and linking completely on-device without any overpriced cloud services or subscriptions."),
            
                .init(icon: UIImage(systemName: "cpu.fill")!,
                      iconTint: UIColor { trait in
                          trait.userInterfaceStyle == .dark
                          ? UIColor(red: 0.60, green: 0.88, blue: 0.80, alpha: 1.0)
                          : UIColor(red: 0.30, green: 0.68, blue: 0.58, alpha: 1.0)
                      },
                      title: "Native Performance",
                      description: "A custom micro kernel called ksurface providing real process management, Mach IPC(task ports for example) and POSIX semantics directly on-device for your projects."),
            
                .init(icon: UIImage(systemName: "exclamationmark.triangle.fill")!,
                      iconTint: UIColor { trait in
                                trait.userInterfaceStyle == .dark
                                ? UIColor(red: 0.98, green: 0.82, blue: 0.45, alpha: 1.0)
                                : UIColor(red: 0.85, green: 0.60, blue: 0.12, alpha: 1.0)
                        },
                      title: "Warning",
                      description: "This is a beta version of Nyxian, so don't expect a product without bugs, please be kind and respectful, it is very hard to develop this kind of software. Please report any kinds of issues and ask any question over at our github we have a lot of time and passion answering your questions and making Nyxian better."),
        ])
    }
    
    static func setUpNotice() -> UIOnboardingTextViewConfiguration {
        return .init(icon: UIImage(systemName: "heart.fill")!,
                     text: "Contributions, feedback, and stars keep the project alive.",
                     linkTitle: "Contribute on GitHub",
                     link: "https://github.com/emexlab/Nyxian",
                     linkColor: UIColor { trait in
                         trait.userInterfaceStyle == .dark
                             ? UIColor(red: 0.85, green: 0.74, blue: 0.93, alpha: 1.0)
                             : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0)
                     })
    }
    
    static func setUpButton() -> UIOnboardingButtonConfiguration {
        let lightBackground = currentTheme!.backgroundColor.resolvedColor(with: .init(userInterfaceStyle: .light))
        
        return .init(title: "Continue", titleColor: lightBackground, backgroundColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.85, green: 0.74, blue: 0.93, alpha: 1.0)
            : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0)
        })
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate, UITabBarControllerDelegate, UIOnboardingViewControllerDelegate {
    var window: NXWindowServer?
    weak var themedTabViewController: UIThemedTabViewController?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        // swizzle swizzle swizzle :3
        UIViewController.swizzlePresentAndDismissOnce
        UIBarButtonItem.swizzleBarButtonitem
        RevertUI()
        
        self.window = NXWindowServer.shared(with: windowScene)
        if(self.window == nil)
        {
            return;
        }
        
        func errorFallback(title: String, message: String) {
            self.window?.rootViewController = UIViewController()
            self.window?.rootViewController?.view.backgroundColor = currentTheme!.backgroundColor

            let alert = UIAlertController(
                title: title,
                message: nil,
                preferredStyle: .alert
            )
            
            let textColor = UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(white: 0.75, alpha: 1.0)
                    : UIColor(white: 0.20, alpha: 1.0)
            }
            
            alert.setValue(
                NSAttributedString(
                    string: message,
                    attributes: [
                        .foregroundColor: textColor,
                        .font: UIFont.systemFont(ofSize: 13)
                    ]
                ),
                forKey: "attributedMessage"
            )

            self.window?.makeKeyAndVisible()

            DispatchQueue.main.async {
                self.window?.rootViewController?.present(
                    alert,
                    animated: true
                )
            }
        }
        
        if PEGetLiveProcessBundle() == nil
        {
            errorFallback(title: "Extension Not Found", message: """
            The required NSExtension could not be found.

            Make sure the app was installed with its extension intact and that it wasn't removed during signing or installation.
            """)
            return
        }
        
        if !PEExtensionHasGetTaskAllowed() {
            errorFallback(title: "Unsupported Provisioning Profile", message: """
            Extension doesn't have the "get-task-allow" entitlement.

            Distribution certificates are not supported. You must use a Developer certificate issued by Apple.

            The 7 day certificate is a Developer certificate.
            """)
            return
        }
        
        NXBootstrap.shared().bootstrap()
        
        //let themedTabViewController: UIThemedTabViewController = UIThemedTabViewController()
        let themedTabViewController = UIThemedTabViewController() 
        self.themedTabViewController = themedTabViewController
     
        let contentViewController: ContentViewController = ContentViewController()
        let settingsViewController: SettingsViewController = SettingsViewController()
        let appsViewController: ApplicationManagementViewController = ApplicationManagementViewController.shared
     
        let contentNavigationController: UINavigationController = UINavigationController(rootViewController: contentViewController)
        let settingsNavigationController: UINavigationController = UINavigationController(rootViewController: settingsViewController)
        let appsNavigationController: UINavigationController = UINavigationController(rootViewController: appsViewController)
     
        contentNavigationController.tabBarItem = UITabBarItem(title: "Projects", image: UIImage(systemName: "square.grid.2x2.fill"), tag: 0)
        settingsNavigationController.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gear"), tag: 1)
        appsNavigationController.tabBarItem = UITabBarItem(title: "Apps", image: UIImage(systemName: "app.badge"), tag: 2)
     
        var viewControllers: [UIViewController] = [contentNavigationController, settingsNavigationController, appsNavigationController]
        
        //if UIDevice.current.userInterfaceIdiom == .phone {
            //if #available(iOS 26.0, *) {
                //let fakeViewController: UIViewController = UIViewController()
                //fakeViewController.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 2)
                //fakeViewController.tabBarItem.title = "Switcher"
                //fakeViewController.tabBarItem.image = UIImage(systemName: "iphone.app.switcher")
                //viewControllers.append(fakeViewController)
            //}
        //}
        
        themedTabViewController.viewControllers = viewControllers
        themedTabViewController.delegate = self
        
        self.window?.rootViewController = themedTabViewController
        self.window?.makeKeyAndVisible()
        
        if let _: NSNumber = UserDefaults.standard.object(forKey: "NXOnboardingSentinel") as? NSNumber {
            checkSigningSetup()
            return
        }
        
        let onboardingConfiguration = UIOnboardingViewConfiguration(appIcon: UIOnboardingHelper.setUpIcon(), firstTitleLine: UIOnboardingHelper.setUpFirstTitleLine(), secondTitleLine: UIOnboardingHelper.setUpSecondTitleLine(), features: UIOnboardingHelper.setUpFeatures(), textViewConfiguration: UIOnboardingHelper.setUpNotice(), buttonConfiguration: UIOnboardingHelper.setUpButton())
        let onboardingController: UIOnboardingViewController = UIOnboardingViewController(withConfiguration: onboardingConfiguration)
        onboardingController.delegate = self
        onboardingController.backgroundColor = currentTheme!.backgroundColor
        
        self.window?.rootViewController?.present(onboardingController, animated: false)
    }
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if tabBarController.selectedViewController === viewController && NXBuilder.builds {
            return false
        }
        //if viewController.tabBarItem.tag == 2 {
            //self.window?.showAppSwitcherExternal()
            //return false
        //}
        return true
    }
    
    func didFinishOnboarding(onboardingViewController: UIOnboarding.UIOnboardingViewController) {
        onboardingViewController.modalTransitionStyle = .crossDissolve
        onboardingViewController.dismiss(animated: true, completion: nil)
        
        // storing sentinel so it will not appear again
        UserDefaults.standard.set(NSNumber(booleanLiteral: true), forKey: "NXOnboardingSentinel")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            checkSigningSetup()
        }
    }
}
