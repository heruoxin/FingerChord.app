// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import GestureCore

enum EventEmitter {
    static func send(_ action: GestureAction) -> Bool {
        guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .privateState) else {
            return false
        }
        source.userData = InputMonitor.eventMarker
        let events: [CGEvent?]
        if action == .commandClick {
            guard let location = CGEvent(source: nil)?.location else { return false }
            events = [
                CGEvent(
                    mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: location,
                    mouseButton: .left),
                CGEvent(
                    mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: location,
                    mouseButton: .left),
            ]
        } else {
            let key: CGKeyCode = action == .closeWindow ? 13 : 12  // ANSI W / Q on this Mac's keyboard.
            events = [
                CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false),
            ]
        }
        guard events.allSatisfy({ $0 != nil }) else { return false }
        for event in events.compactMap({ $0 }) {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: InputMonitor.eventMarker)
            if action == .commandClick { event.setIntegerValueField(.mouseEventClickState, value: 1) }
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
