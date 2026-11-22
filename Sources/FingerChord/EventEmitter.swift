// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import GestureCore

enum EventEmitter {
    static func send(_ gesture: Gesture) {
        for event in events(for: gesture) {
            event.setIntegerValueField(.eventSourceUserData, value: InputMonitor.eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    // ANSI key codes: [ 33, ] 30, W 13, Q 12.
    private static func events(for gesture: Gesture) -> [CGEvent] {
        switch gesture {
        case .middleTap: click(.left, flags: .maskCommand)
        case .leftTap: key(33, flags: [.maskShift, .maskCommand])
        case .rightTap: key(30, flags: [.maskShift, .maskCommand])
        case .threeTap: click(.center, flags: [])
        case .threePress: key(13, flags: .maskCommand)
        case .fourPress: key(12, flags: .maskCommand)
        }
    }

    private static let source = CGEventSource(stateID: .privateState)

    private static func key(_ code: CGKeyCode, flags: CGEventFlags) -> [CGEvent] {
        [true, false].compactMap { down in
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            return event
        }
    }

    private static func click(_ button: CGMouseButton, flags: CGEventFlags) -> [CGEvent] {
        let location = CGEvent(source: nil)!.location
        let types: [CGEventType] = button == .left ? [.leftMouseDown, .leftMouseUp] : [.otherMouseDown, .otherMouseUp]
        return types.compactMap { type in
            let event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button)
            event?.flags = flags
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            return event
        }
    }
}
