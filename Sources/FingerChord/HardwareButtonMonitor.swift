import Foundation
import IOKit.hid
import TouchBridge

/// Public HID input values expose the physical switch; tap-to-click and three-finger
/// dragging only generate translated mouse events and do not change this switch.
final class HardwareButtonMonitor {
    private var manager: IOHIDManager?
    private var down: [UInt: Bool] = [:]
    var onButton: ((UInt, Bool) -> Void)?

    @discardableResult func start() -> Bool {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDPrimaryUsagePageKey: 1, kIOHIDPrimaryUsageKey: 2] as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, [kIOHIDElementUsagePageKey: 9, kIOHIDElementUsageKey: 1] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            Unmanaged<HardwareButtonMonitor>.fromOpaque(context).takeUnretainedValue().receive(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        DiagnosticTrace.record("hidManager", ["open": result])
        if result != kIOReturnSuccess { stop(); return false }
        return true
    }

    func stop() {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil; down = [:]
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == 9, IOHIDElementGetUsage(element) == 1 else { return }
        let hidDevice = IOHIDElementGetDevice(element)
        let device = FCDeviceForHIDService(IOHIDDeviceGetService(hidDevice))
        guard device != 0 else { return } // Never combine an external mouse with resting fingers.
        let isDown = IOHIDValueGetIntegerValue(value) != 0
        guard isDown != (down[device] ?? false) else { return }
        down[device] = isDown
        DiagnosticTrace.record("hardwareButton", ["device": device, "down": isDown])
        onButton?(device, isDown)
    }
}
