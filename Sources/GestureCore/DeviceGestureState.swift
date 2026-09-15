// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Physical HID switch values and contact frames arrive independently.
/// Resolve a pending press against the next frame, with a timed fallback for stationary fingers.
public struct DeviceGestureState {
    public private(set) var recognizer = GestureRecognizer()
    private var pendingButton: Bool?
    public var options: GestureOptions {
        get { recognizer.options }
        set {
            if recognizer.options != newValue { pendingButton = nil }
            recognizer.options = newValue
        }
    }
    public init() {}
    public mutating func buttonHeader(isDown: Bool) {
        if !isDown {
            // Releases may be the final header, with no following contact frame.
            // Clear the latch now so a later press cannot overwrite the pending release.
            _ = recognizer.buttonChanged(isDown: false, at: recognizer.lastFrameTime)
        }
        // HID and legacy callbacks can report the same edge. Do not erase an action
        // already queued for the corresponding click when a duplicate arrives.
        if isDown && (pendingButton == true || recognizer.buttonIsDown) { return }
        pendingButton = isDown
    }
    public var hasPendingPress: Bool { pendingButton == true }

    /// Hardware values arrive separately from contacts. If no new contact frame follows,
    /// resolve against the latest fresh frame without inventing a touch update.
    public mutating func resolvePendingButton(at time: Double) -> (
        action: GestureAction?, physicalPress: Bool
    ) {
        guard let down = pendingButton else { return (nil, false) }
        pendingButton = nil
        return (recognizer.buttonChanged(isDown: down, at: time), down)
    }

    public mutating func frame(_ contacts: [Contact], at time: Double) -> (
        action: GestureAction?, physicalPress: Bool
    ) {
        let pending = pendingButton
        pendingButton = nil
        if pending != nil { recognizer.cancelTap() }
        var action = recognizer.update(contacts, at: time)
        if let down = pending { action = recognizer.buttonChanged(isDown: down, at: time) ?? action }
        return (action, pending == true)
    }
    public mutating func cancelTap() { recognizer.cancelTap() }
    public mutating func reset() {
        recognizer.reset()
        pendingButton = nil
    }
}
