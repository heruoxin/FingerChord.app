// SPDX-License-Identifier: GPL-3.0-only
import AppKit

enum HapticFeedback {
    /// Request immediately while the fingers are still touching the Force Touch surface.
    static func perform() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        DiagnosticTrace.record("hapticRequested", ["active": NSApp.isActive])
    }
}
