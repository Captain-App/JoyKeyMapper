//
//  JoyConManager.swift
//  JoyConSwift
//
//  Created by magicien on 2019/06/16.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import Foundation
import IOKit
import IOKit.hid

let controllerTypeOutputReport: [UInt8] = [
    JoyCon.OutputType.subcommand.rawValue, // type
    0x0f, // packet counter
    0x00, 0x01, 0x00, 0x40, 0x00, 0x01, 0x00, 0x40, // rumble data
    Subcommand.CommandType.getSPIFlash.rawValue, // subcommand type
    0x12, 0x60, 0x00, 0x00, // address
    0x01, // data length
]

/// The manager class to handle controller connection/disconnection events
public class JoyConManager {
    static let vendorID: Int32 = 0x057E
    static let joyConLID: Int32 = 0x2006 // Joy-Con (L)
    static let joyConRID: Int32 = 0x2007 // Joy-Con (R), Famicom Controller 1&2
    static let proConID: Int32 = 0x2009 // Pro Controller
    static let snesConID: Int32 = 0x2017 // SNES Controller
    
    static let joyConLType: UInt8 = 0x01
    static let joyConRType: UInt8 = 0x02
    static let proConType: UInt8 = 0x03
    static let famicomCon1Type: UInt8 = 0x07
    static let famicomCon2Type: UInt8 = 0x08
    static let snesConType: UInt8 = 0x0B

    private let manager: IOHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var matchingControllers: [IOHIDDevice] = []
    private var matchingTimer: [IOHIDDevice: Timer] = [:]
    private var controllers: [IOHIDDevice: Controller] = [:]
    private var runLoop: RunLoop? = nil
    private let stateQueue = DispatchQueue(label: "jp.0spec.JoyKeyMapper.JoyConManager")
        
    /// Handler for a controller connection event
    public var connectHandler: ((_ controller: Controller) -> Void)? = nil
    /// Handler for a controller disconnection event
    public var disconnectHandler: ((_ controller: Controller) -> Void)? = nil
    
    /// Initialize a manager
    public init() {}
    
    let handleMatchCallback: IOHIDDeviceCallback = { (context, result, sender, device) in
        let manager: JoyConManager = unsafeBitCast(context, to: JoyConManager.self)
        manager.handleMatch(result: result, sender: sender, device: device)
    }
    
    let handleInputCallback: IOHIDValueCallback = { (context, result, sender, value) in
        let manager: JoyConManager = unsafeBitCast(context, to: JoyConManager.self)
        manager.handleInput(result: result, sender: sender, value: value)
    }
    
    let handleRemoveCallback: IOHIDDeviceCallback = { (context, result, sender, device) in
        let manager: JoyConManager = unsafeBitCast(context, to: JoyConManager.self)
        manager.handleRemove(result: result, sender: sender, device: device)
    }
    
    func handleMatch(result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? "unknown"
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int32 ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int32 ?? 0
        
        NSLog("Device matched candidate: %@ (Vendor: 0x%04X, Product: 0x%04X)", serial, vendor, product)
        
        var alreadyMatching = false
        self.stateQueue.sync {
            if (self.controllers.contains { (dev, ctrl) in dev == device }) {
                NSLog("Device %@ already in controllers list", serial)
                alreadyMatching = true
                return
            }
            
            if (self.matchingControllers.contains { $0 == device }) {
                NSLog("Device %@ already in matching list", serial)
                alreadyMatching = true
                return
            }

            self.matchingControllers.append(device)
        }
        
        if alreadyMatching { return }
        
        // Add a safety timeout for matching
        DispatchQueue.main.async { [weak self] in
            let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.stateQueue.sync {
                    if self.matchingControllers.contains(device) {
                        NSLog("Matching TIMED OUT for %@. Removing from matching list.", serial)
                        self.matchingControllers.removeAll { $0 == device }
                        self.matchingTimer.removeValue(forKey: device)
                    }
                }
            }
            self?.stateQueue.sync {
                self?.matchingTimer[device] = timer
            }
        }

        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(0x01), controllerTypeOutputReport, controllerTypeOutputReport.count);
        if (result != kIOReturnSuccess) {
            NSLog("IOHIDDeviceSetReport error: %d during match for %@", result, serial)
            self.stateQueue.sync {
                self.matchingControllers.removeAll { $0 == device }
            }
            return
        }
        NSLog("Sent controller type request to %@", serial)
    }
    
    func handleControllerType(device: IOHIDDevice, result: IOReturn, value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let reportID = IOHIDElementGetReportID(element)
        
        // We only care about Report ID 0x21 (Subcommand response) during matching
        if reportID != 0x21 {
            return
        }

        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? "unknown"
        let ptr = IOHIDValueGetBytePtr(value)
        
        // Byte 13 is the subcommand ID. 0x10 is SPI Flash read.
        let subcommand = (ptr+13).pointee
        if subcommand != Subcommand.CommandType.getSPIFlash.rawValue {
            return
        }

        var isMatching = false
        self.stateQueue.sync {
            isMatching = self.matchingControllers.contains(device)
        }
        guard isMatching else { return }
        
        let address = ReadUInt32(from: ptr+14)
        let length = Int((ptr+18).pointee)
        
        // We are looking for the controller type read at 0x6012
        if address != 0x6012 {
            return
        }
        
        NSLog("Received controller type SPI read for %@", serial)
        
        // Cleanup matching timer
        self.stateQueue.sync {
            self.matchingTimer[device]?.invalidate()
            self.matchingTimer.removeValue(forKey: device)
        }

        guard length == 1 else { return }
        let buffer = UnsafeBufferPointer(start: ptr+19, count: length)
        let data = Array(buffer)
        
        NSLog("Controller type for %@: %d", serial, data[0])
        var _controller: Controller? = nil
        switch data[0] {
        case JoyConManager.joyConLType:
            _controller = JoyConL(device: device)
            break
        case JoyConManager.joyConRType:
            _controller = JoyConR(device: device)
            break
        case JoyConManager.proConType:
            _controller = ProController(device: device)
            break
        case JoyConManager.famicomCon1Type:
            _controller = FamicomController1(device: device)
            break
        case JoyConManager.famicomCon2Type:
            _controller = FamicomController2(device: device)
            break
        case JoyConManager.snesConType:
            _controller = SNESController(device: device)
            break
        default:
            break
        }
        
        guard let controller = _controller else { return }
        self.stateQueue.sync {
            self.matchingControllers.removeAll { $0 == device }
            self.controllers[device] = controller
        }
        controller.isConnected = true
        controller.readInitializeData { [weak self] in
            NSLog("Initialize data read finished for %@, calling connectHandler", serial)
            self?.connectHandler?(controller)
        }
    }
    
    func handleInput(result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
        guard let sender = sender else { return }
        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue();
        
        var controller: Controller?
        var isMatching = false
        
        self.stateQueue.sync {
            isMatching = self.matchingControllers.contains(device)
            controller = self.controllers[device]
        }
        
        if isMatching {
            self.handleControllerType(device: device, result: result, value: value)
            return
        }
        
        guard let ctrl = controller else { return }
        if (result == kIOReturnSuccess) {
            ctrl.handleInput(value: value)
        } else {
            ctrl.handleError(result: result, value: value)
        }
    }
    
    func handleRemove(result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? "unknown"
        NSLog("Device removed: %@ (Matching list size: %d)", serial, self.matchingControllers.count)
        
        var controller: Controller?
        self.stateQueue.sync {
            self.matchingControllers.removeAll { $0 == device }
            controller = self.controllers[device]
            self.controllers.removeValue(forKey: device)
        }
        
        guard let ctrl = controller else { 
            NSLog("Device %@ was not in controllers list", serial)
            return 
        }
        ctrl.isConnected = false
        ctrl.cleanUp()
        
        NSLog("Calling disconnectHandler for %@", serial)
        self.disconnectHandler?(ctrl)
    }
    
    private func registerDeviceCallback() {
        IOHIDManagerRegisterDeviceMatchingCallback(self.manager, self.handleMatchCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        IOHIDManagerRegisterDeviceRemovalCallback(self.manager, self.handleRemoveCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        IOHIDManagerRegisterInputValueCallback(self.manager, self.handleInputCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
    }
    
    private func unregisterDeviceCallback() {
        IOHIDManagerRegisterDeviceMatchingCallback(self.manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(self.manager, nil, nil)
        IOHIDManagerRegisterInputValueCallback(self.manager, nil, nil)
    }
    
    private func cleanUp() {
        self.stateQueue.sync {
            self.controllers.values.forEach { controller in
                controller.cleanUp()
            }
            self.controllers.removeAll()
            
            self.matchingTimer.values.forEach { $0.invalidate() }
            self.matchingTimer.removeAll()
            self.matchingControllers.removeAll()
        }
    }
        
    /// Start waiting for controller connection/disconnection events in the current thread.
    /// If you don't want to stop the current thread, use `runAsync()` instead.
    /// - Returns: kIOReturnSuccess if succeeded. IOReturn error value if failed.
    public func run() -> IOReturn {
        let joyConLCriteria: [String: Any] = [
            kIOHIDVendorIDKey: JoyConManager.vendorID,
            kIOHIDProductIDKey: JoyConManager.joyConLID,
        ]
        let joyConRCriteria: [String: Any] = [
            kIOHIDVendorIDKey: JoyConManager.vendorID,
            kIOHIDProductIDKey: JoyConManager.joyConRID,
        ]
        let proConCriteria: [String: Any] = [
            kIOHIDVendorIDKey: JoyConManager.vendorID,
            kIOHIDProductIDKey: JoyConManager.proConID,
        ]
        let snesConCriteria: [String: Any] = [
            kIOHIDVendorIDKey: JoyConManager.vendorID,
            kIOHIDProductIDKey: JoyConManager.snesConID,
        ]
        let criteria = [joyConLCriteria, joyConRCriteria, proConCriteria, snesConCriteria]
        
        let runLoop = RunLoop.current
        
        IOHIDManagerSetDeviceMatchingMultiple(self.manager, criteria as CFArray)
        IOHIDManagerScheduleWithRunLoop(self.manager, runLoop.getCFRunLoop(), CFRunLoopMode.defaultMode.rawValue)
        
        self.registerDeviceCallback()
        
        let ret = IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if (ret != kIOReturnSuccess) {
            NSLog("Failed to seize HID manager: %d. Falling back to shared mode.", ret)
            IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
        } else {
            NSLog("HID manager seized successfully")
        }
        
        self.runLoop = runLoop
        self.runLoop?.run()
 
        IOHIDManagerClose(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(self.manager, runLoop.getCFRunLoop(), CFRunLoopMode.defaultMode.rawValue)

        return kIOReturnSuccess
    }
    
    /// Start waiting for controller connection/disconnection events in a new thread.
    /// If you want to wait for the events synchronously, use `run()` instead.
    /// - Returns: kIOReturnSuccess if succeeded. IOReturn error value if failed.
    public func runAsync() -> IOReturn {
        DispatchQueue.global().async { [weak self] in
            _ = self?.run()
        }
        return kIOReturnSuccess
    }
    
    /// Stop waiting for controller connection/disconnection events
    public func stop() {
        if let currentLoop = self.runLoop?.getCFRunLoop() {
            CFRunLoopStop(currentLoop)
        }

        self.unregisterDeviceCallback()
        self.cleanUp()
    }
}
