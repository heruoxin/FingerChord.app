import Foundation

/// MultitouchSupport reports button state in the frame header, before delivering contacts.
/// Delay interpretation until those contacts arrive to count the fingers in the pressed frame.
public struct DeviceGestureState {
    public private(set) var recognizer = GestureRecognizer()
    private var pendingButton: Bool?
    public var options: GestureOptions {
        get { recognizer.options }
        set { recognizer.options = newValue }
    }
    public init() {}
    public mutating func buttonHeader(isDown: Bool) {
        if !isDown {
            // Releases may be the final header, with no following contact frame.
            // Clear the latch now so a later press cannot overwrite the pending release.
            _ = recognizer.buttonChanged(isDown: false, at: recognizer.lastFrameTime)
        }
        pendingButton = isDown
    }
    public var hasPendingPress: Bool { pendingButton == true }

    /// Hardware values arrive separately from contacts. If no new contact frame follows,
    /// resolve against the latest fresh frame without inventing a touch update.
    public mutating func resolvePendingButton(at time: Double) -> (action: GestureAction?, physicalPress: Bool) {
        guard let down = pendingButton else { return (nil, false) }
        pendingButton = nil
        return (recognizer.buttonChanged(isDown: down, at: time), down)
    }

    public mutating func frame(_ contacts: [Contact], at time: Double) -> (action: GestureAction?, physicalPress: Bool) {
        let pending = pendingButton
        pendingButton = nil
        if pending != nil { recognizer.cancelTap() }
        var action = recognizer.update(contacts, at: time)
        if let down = pending { action = recognizer.buttonChanged(isDown: down, at: time) ?? action }
        return (action, pending == true)
    }
    public mutating func cancelTap() { recognizer.cancelTap() }
    public mutating func reset() { recognizer.reset(); pendingButton = nil }
}
