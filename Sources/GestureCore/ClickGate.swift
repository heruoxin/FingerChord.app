// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Matches a physical trackpad press to its system mouse event. Keeps down/up suppression paired.
/// A press whose system click already reached an app stays a plain click, never also a shortcut.
public struct ClickGate {
    private var pending: (action: GestureAction, time: Double)?
    private var deliveredDown = -Double.infinity
    private var swallowedButtons: Set<Int64> = []
    public init() {}

    /// Returns the action the press may still perform.
    @discardableResult
    public mutating func physicalPress(_ action: GestureAction?, at time: Double) -> GestureAction? {
        pending = time - deliveredDown < 0.15 ? nil : action.map { ($0, time) }
        deliveredDown = -.infinity
        return pending?.action
    }

    public mutating func delivered(at time: Double) { deliveredDown = time }

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
