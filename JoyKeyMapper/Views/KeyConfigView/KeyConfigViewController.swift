//
//  KeyConfigViewController.swift
//  JoyKeyMapper
//
//  Created by magicien on 2019/07/29.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit
import InputMethodKit

protocol KeyConfigSetDelegate {
    func setKeyConfig(controller: KeyConfigViewController)
}

class KeyConfigViewController: NSViewController, NSComboBoxDelegate, KeyConfigComboBoxDelegate {
    var delegate: KeyConfigSetDelegate?
    var keyMap: KeyMap?
    var controllerData: ControllerData?
    var keyCode: Int16 = -1
    
    @IBOutlet weak var titleLabel: NSTextField!
    
    @IBOutlet weak var shiftKey: NSButton!
    @IBOutlet weak var optionKey: NSButton!
    @IBOutlet weak var controlKey: NSButton!
    @IBOutlet weak var commandKey: NSButton!

    @IBOutlet weak var keyRadioButton: NSButton!
    @IBOutlet weak var mouseRadioButton: NSButton!
    
    @IBOutlet weak var keyAction: KeyConfigComboBox!
    @IBOutlet weak var mouseAction: NSPopUpButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let keyMap = self.keyMap else { return }

        let title = NSLocalizedString("%@ Button Key Config", comment: "%@ Button Key Config")
        let buttonName = NSLocalizedString((keyMap.button ?? ""), comment: "Button Name")
        self.titleLabel.stringValue = String.localizedStringWithFormat(title, buttonName)

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(keyMap.modifiers))
        self.shiftKey.state = modifiers.contains(.shift) ? .on : .off
        self.optionKey.state = modifiers.contains(.option) ? .on : .off
        self.controlKey.state = modifiers.contains(.control) ? .on : .off
        self.commandKey.state = modifiers.contains(.command) ? .on : .off
        
        self.updateMouseActionPopup()
        
        if keyMap.keyCode >= 0 {
            self.keyRadioButton.state = .on
            self.keyAction.stringValue = getKeyName(keyCode: UInt16(keyMap.keyCode))
        } else {
            self.mouseRadioButton.state = .on
            self.mouseAction.selectItem(withTag: Int(keyMap.mouseButton))
        }
        self.keyCode = keyMap.keyCode
        self.keyAction.configDelegate = self
        self.keyAction.delegate = self
    }

    func updateMouseActionPopup() {
        self.mouseAction.removeAllItems()
        
        // Add profiles first so they are more visible
        self.mouseAction.addItem(withTitle: NSLocalizedString("Switch to Default Profile", comment: ""))
        self.mouseAction.lastItem?.tag = Int(SpecialMouse_DefaultProfile)
        
        self.mouseAction.addItem(withTitle: NSLocalizedString("Enable Auto-Switch", comment: ""))
        self.mouseAction.lastItem?.tag = Int(SpecialMouse_AutoSwitch)
        
        if let appConfigs = self.controllerData?.appConfigs {
            for i in 0..<appConfigs.count {
                let appConfig = appConfigs[i] as! AppConfig
                let appName = appConfig.app?.displayName ?? NSLocalizedString("Generic Profile", comment: "")
                let title = String.localizedStringWithFormat(NSLocalizedString("Switch to Profile %@", comment: ""), appName)
                self.mouseAction.addItem(withTitle: title)
                self.mouseAction.lastItem?.tag = Int(SpecialMouse_AppProfileBase) + i
            }
        }
        
        self.mouseAction.menu?.addItem(NSMenuItem.separator())
        
        // Add standard mouse clicks
        for i in 0..<mouseButtonNames.count {
            self.mouseAction.addItem(withTitle: localizedMouseButtonNames[i])
            self.mouseAction.lastItem?.tag = i
        }
        
        self.mouseAction.synchronizeTitleAndSelectedItem()
    }
    
    func updateKeyMap() {
        guard let keyMap = self.keyMap else { return }
        
        var flags = NSEvent.ModifierFlags(rawValue: 0)

        if self.shiftKey.state == .on {
            flags.formUnion(.shift)
        } else {
            flags.remove(.shift)
        }
        
        if self.optionKey.state == .on {
            flags.formUnion(.option)
        } else {
            flags.remove(.option)
        }
        
        if self.controlKey.state == .on {
            flags.formUnion(.control)
        } else {
            flags.remove(.control)
        }

        
        if self.commandKey.state == .on {
            flags.formUnion(.command)
        } else {
            flags.remove(.command)
        }
        
        keyMap.modifiers = Int32(flags.rawValue)

        if self.keyRadioButton.state == .on {
            keyMap.keyCode = self.keyCode
            keyMap.mouseButton = -1
        } else {
            let tag = Int16(self.mouseAction.selectedTag())
            if tag >= SpecialMouse_DefaultProfile {
                keyMap.keyCode = SpecialKeyCode
                keyMap.mouseButton = tag
            } else {
                keyMap.keyCode = -1
                keyMap.mouseButton = tag
            }
        }
        
        keyMap.isEnabled = true
        
        self.delegate?.setKeyConfig(controller: self)
    }
    
    func comboBoxSelectionDidChange(_ notification: Notification) {
        let index = self.keyAction.indexOfSelectedItem
        if index >= 0 {
            let keyCode = keyCodeList[index]
            self.setKeyCode(UInt16(keyCode))
        }
    }
    
    func setKeyCode(_ keyCode: UInt16) {
        self.keyCode = Int16(keyCode)
        self.keyAction.stringValue = getKeyName(keyCode: keyCode)
        self.keyRadioButton.state = .on
    }
    
    @IBAction func didPushRadioButton(_ sender: NSButton) {}
    
    @IBAction func didPushOK(_ sender: NSButton) {
        guard let window = self.view.window else { return }
        self.updateKeyMap()
        window.sheetParent?.endSheet(window, returnCode: .OK)
    }
    
    @IBAction func didPushCancel(_ sender: NSButton) {
        guard let window = self.view.window else { return }
        window.sheetParent?.endSheet(window, returnCode: .cancel)
    }
}
