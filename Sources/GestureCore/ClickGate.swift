// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Matches a physical trackpad press to its system mouse event. Keeps down/up suppression paired.
public struct ClickGate {
    private var pending: (action: GestureAction, time: Double)?
    private var swallowedButtons: Set<Int64> = []
    public init() {}

    public mutating func physicalPress(_ action: GestureAction?, at time: Double) {
        pending = action.map { ($0, time) }
    }

    public mutating func mouseDown(button: Int64, at time: Double) -> (
        swallow: Bool, action: GestureAction?
    ) {
        // A new down is a new cycle even if the last up was lost while the event tap was disabled.
        swallowedButtons.remove(button)
        guard let pending, time >= pending.time, time - pending.time < 0.15 else {
            self.pending = nil
            return (false, nil)
        }
        self.pending = nil
        swallowedButtons.insert(button)
        return (true, pending.action)
    }

    public func shouldSwallowDrag(button: Int64) -> Bool { swallowedButtons.contains(button) }
    public mutating func mouseUp(button: Int64) -> Bool { swallowedButtons.remove(button) != nil }
    public mutating func cancelPending() { pending = nil }
    public mutating func reset() {
        pending = nil
        swallowedButtons = []
    }
}
