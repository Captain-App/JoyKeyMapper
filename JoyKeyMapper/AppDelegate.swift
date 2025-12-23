//
//  AppDelegate.swift
//  JoyKeyMapper
//
//  Created by magicien on 2019/07/14.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit
import ServiceManagement
import UserNotifications
import JoyConSwift

let helperAppID: CFString = "jp.0spec.JoyKeyMapperLauncher" as CFString

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    @IBOutlet weak var menu: NSMenu?
    @IBOutlet weak var controllersMenu: NSMenuItem?
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var windowController: NSWindowController?
    
    let manager: JoyConManager = JoyConManager()
    var dataManager: DataManager?
    var controllers: [GameController] = []
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Accessibility check
        self.checkAccessibility()

        // Insert code here to initialize your application
        
        // Window initialization
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        self.windowController = storyboard.instantiateController(withIdentifier: "JoyKeyMapperWindowController") as? NSWindowController
        
        // Menu settings
        let icon = NSImage(named: "menu_icon")
        icon?.size = NSSize(width: 24, height: 24)
        self.statusItem.button?.image = icon
        self.statusItem.menu = self.menu

        // Set controller handlers
        self.manager.connectHandler = { [weak self] controller in
            self?.connectController(controller)
        }
        self.manager.disconnectHandler = { [weak self] controller in
            self?.disconnectController(controller)
        }
        
        self.dataManager = DataManager() { [weak self] manager in
            guard let strongSelf = self else { return }
            guard let dataManager = manager else { return }

            dataManager.controllers.forEach { data in
                // Fix missing bundleIDs for generic profiles
                data.appConfigs?.forEach { obj in
                    if let appConfig = obj as? AppConfig, appConfig.app?.bundleID == nil {
                        appConfig.app?.bundleID = "generic.profile.\(UUID().uuidString)"
                    }
                }
                _ = dataManager.save()

                let gameController = GameController(data: data)
                strongSelf.controllers.append(gameController)
            }
            _ = strongSelf.manager.runAsync()
            
            // Check frontmost app immediately
            if let frontmostApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontmostApp.bundleIdentifier {
                strongSelf.controllers.forEach { controller in
                    controller.switchApp(bundleID: bundleID)
                }
            }
            
            NSWorkspace.shared.notificationCenter.addObserver(strongSelf, selector: #selector(strongSelf.didActivateApp), name: NSWorkspace.didActivateApplicationNotification, object: nil)
            
            NotificationCenter.default.post(name: .controllerAdded, object: nil)
        }
        
        self.updateControllersMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(controllerIconChanged), name: .controllerIconChanged, object: nil)
        
        // Notification settings
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }
    
    // MARK: - Menu
    
    @IBAction func openAbout(_ sender: Any) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(NSApplication.shared)
    }
    
    @IBAction func openSettings(_ sender: Any) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.windowController?.showWindow(self)
        self.windowController?.window?.orderFrontRegardless()
        self.windowController?.window?.delegate = self
    }
    
    @IBAction func quit(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

    func updateControllersMenu() {
        self.controllersMenu?.submenu?.removeAllItems()

        self.controllers.forEach { controller in
            guard controller.controller?.isConnected ?? false else { return }
            let item = NSMenuItem()

            item.title = ""
            item.image = controller.icon
            item.image?.size = NSSize(width: 32, height: 32)
            
            item.submenu = NSMenu()
            
            // Enable key mappings menu
            let enabled = NSMenuItem()
            enabled.title = NSLocalizedString("Enable key mappings", comment: "Enable key mappings")
            enabled.action = Selector(("toggleEnableKeyMappings"))
            enabled.state = controller.isEnabled ? .on : .off
            enabled.target = controller
            item.submenu?.addItem(enabled)

            // Disconnect menu
            let disconnect = NSMenuItem()
            disconnect.title = NSLocalizedString("Disconnect", comment: "Disconnect")
            disconnect.action = Selector(("disconnect"))
            disconnect.target = controller
            item.submenu?.addItem(disconnect)
            
            // Profiles menu
            let profiles = NSMenuItem()
            profiles.title = NSLocalizedString("Profiles", comment: "Profiles")
            profiles.submenu = NSMenu()
            
            let defaultProfile = NSMenuItem()
            defaultProfile.title = NSLocalizedString("Default", comment: "Default")
            defaultProfile.action = #selector(GameController.switchToDefaultProfile)
            defaultProfile.target = controller
            defaultProfile.state = (controller.currentConfigData === controller.data.defaultConfig) ? .on : .off
            profiles.submenu?.addItem(defaultProfile)
            
            if let appConfigs = controller.data.appConfigs {
                for i in 0..<appConfigs.count {
                    let appConfig = appConfigs[i] as! AppConfig
                    let appName = appConfig.app?.displayName ?? NSLocalizedString("Generic Profile", comment: "")
                    
                    let profileItem = NSMenuItem()
                    profileItem.title = appName
                    profileItem.tag = i
                    profileItem.action = #selector(GameController.switchToProfile(sender:))
                    profileItem.target = controller
                    profileItem.state = (controller.currentConfigData === appConfig.config) ? .on : .off
                    profiles.submenu?.addItem(profileItem)
                }
            }
            
            item.submenu?.addItem(profiles)
            
            // Separator
            item.submenu?.addItem(NSMenuItem.separator())

            // Battery info
            let battery = NSMenuItem()
            if controller.controller?.battery ?? .unknown != .unknown {
                var chargeString = ""
                if controller.controller?.isCharging ?? false {
                    let charging = NSLocalizedString("charging", comment: "charging")
                    chargeString = " (\(charging))"
                }
                let batteryString = NSLocalizedString("Battery", comment: "Battery")
                battery.title = "\(batteryString): \(controller.localizedBatteryString)\(chargeString)"
            }
            battery.isEnabled = false
            item.submenu?.addItem(battery)
            
            self.controllersMenu?.submenu?.addItem(item)
        }
        
        if let itemCount = self.controllersMenu?.submenu?.items.count, itemCount <= 0 {
            let item = NSMenuItem()
            let noControllers = NSLocalizedString("No controllers connected", comment: "No controllers connected")
            item.title = "(\(noControllers))"
            item.isEnabled = false
            self.controllersMenu?.submenu?.addItem(item)
        }
    }
    
    // MARK: - Helper app settings
    
    func setLoginItem(enabled: Bool) {
        let succeeded = SMLoginItemSetEnabled(helperAppID, enabled)
        if (!succeeded) {
            
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        _ = self.dataManager?.save()
    }
    
    // MARK: - Notifications
    
    @objc func controllerIconChanged(_ notification: NSNotification) {
        self.updateControllersMenu()
    }
    
    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .badge, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: - Controller event handlers

    func applicationWillTerminate(_ aNotification: Notification) {
        self.controllers.forEach { controller in
            controller.controller?.setHCIState(state: .disconnect)
        }
    }
    
    func connectController(_ controller: JoyConSwift.Controller) {
        if let gameController = self.controllers.first(where: {
            $0.data.serialID == controller.serialID
        }) {
            gameController.controller = controller
            gameController.startTimer()
            NotificationCenter.default.post(name: .controllerConnected, object: gameController)

            AppNotifications.notifyControllerConnected(gameController)
        } else {
            self.addController(controller)
        }
        self.updateControllersMenu()
    }

    @objc func disconnectController(sender: Any) {
        guard let item = sender as? NSMenuItem else { return }
        guard let gameController = item.representedObject as? GameController else { return }
        
        gameController.disconnect()
        self.updateControllersMenu()
    }
    
    func disconnectController(_ controller: JoyConSwift.Controller) {
        if let gameController = self.controllers.first(where: {
            $0.data.serialID == controller.serialID
        }) {
            gameController.controller = nil
            gameController.updateControllerIcon()
            NotificationCenter.default.post(name: .controllerDisconnected, object: gameController)
            
            AppNotifications.notifyControllerDisconnected(gameController)
        }
        self.updateControllersMenu()
    }

    func addController(_ controller: JoyConSwift.Controller) {
        guard let dataManager = self.dataManager else { return }
        let controllerData = dataManager.getControllerData(controller: controller)
        let gameController = GameController(data: controllerData)
        gameController.controller = controller
        gameController.startTimer()
        self.controllers.append(gameController)
        
        NotificationCenter.default.post(name: .controllerAdded, object: gameController)
        
        AppNotifications.notifyControllerConnected(gameController)
    }
    
    func removeController(_ controller: JoyConSwift.Controller) {
        guard let gameController = self.controllers.first(where: {
            $0.data.serialID == controller.serialID
        }) else { return }
        self.removeController(gameController: gameController)
    }
    
    func removeController(gameController controller: GameController) {
        controller.controller?.setHCIState(state: .disconnect)

        self.dataManager?.delete(controller.data)
        self.controllers.removeAll(where: { $0 === controller })
        NotificationCenter.default.post(name: .controllerRemoved, object: controller)
    }

    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(_ sender: AnyObject?) {
        _ = self.dataManager?.save()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        return self.dataManager?.undoManager
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let isSucceeded = self.dataManager?.save() ?? false
        
        if !isSucceeded {
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButton(withTitle: quitButton)
            alert.addButton(withTitle: cancelButton)
            
            let answer = alert.runModal()
            if answer == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }
        
        return .terminateNow
    }
    
    // MARK: - Context switch handling
    
    @objc func didActivateApp(notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let bundleID = app.bundleIdentifier else { return }
        
        resetMetaKeyState()
        
        self.controllers.forEach { controller in
            controller.switchApp(bundleID: bundleID)
        }
    }

    // MARK: - Accessibility
    
    func checkAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String : true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Accessibility Permissions Required", comment: "")
            alert.informativeText = NSLocalizedString("JoyKeyMapper needs accessibility permissions to simulate keyboard and mouse events. Please enable it in System Settings > Privacy & Security > Accessibility.", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Open System Settings", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
