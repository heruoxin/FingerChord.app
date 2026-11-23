// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import GestureCore

enum EventEmitter {
    private static let source = CGEventSource(stateID: .privateState)

    static func send(_ gesture: Gesture) {
        for event in events(for: gesture) {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: InputMonitor.eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    // ANSI key codes: W 13, Q 12.
    private static func events(for gesture: Gesture) -> [CGEvent] {
        switch gesture {
        case .middleTap:
            let location = CGEvent(source: nil)!.location
            return [CGEventType.leftMouseDown, .leftMouseUp].compactMap {
                let click = CGEvent(
                    mouseEventSource: source, mouseType: $0, mouseCursorPosition: location, mouseButton: .left)
                click?.setIntegerValueField(.mouseEventClickState, value: 1)
                return click
            }
        case .threePress, .fourPress:
            return [true, false].compactMap {
                CGEvent(keyboardEventSource: source, virtualKey: gesture == .threePress ? 13 : 12, keyDown: $0)
            }
        }
    }
}
