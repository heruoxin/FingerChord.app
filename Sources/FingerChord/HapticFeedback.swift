// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import GestureCore

enum HapticFeedback {
    /// A physical press already has a native click. Adding feedback after the HID
    /// callback produces a second, delayed bump. Only light taps need an app pulse.
    static func perform(
        for action: GestureAction,
        using performer: () -> NSHapticFeedbackPerformer = { NSHapticFeedbackManager.defaultPerformer }
    ) {
        guard action == .commandClick else {
            DiagnosticTrace.record("hapticNativePress", ["action": action.rawValue])
            return
        }
        performer().perform(.generic, performanceTime: .now)
        DiagnosticTrace.record("hapticRequested", ["action": action.rawValue, "active": NSApp.isActive])
    }
}
