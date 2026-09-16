// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import GestureCore
import Testing

@testable import FingerChord

private final class RecordingPerformer: NSObject, NSHapticFeedbackPerformer {
    var requests: [(NSHapticFeedbackManager.FeedbackPattern, NSHapticFeedbackManager.PerformanceTime)] = []

    func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern,
        performanceTime: NSHapticFeedbackManager.PerformanceTime
    ) {
        requests.append((pattern, performanceTime))
    }
}

@Test @MainActor func physicalPressesDoNotRequestAnAdditionalHaptic() {
    let performer = RecordingPerformer()
    var acquisitions = 0
    for action in [GestureAction.closeWindow, .quitApplication, .closeWindow, .quitApplication] {
        HapticFeedback.perform(for: action) {
            acquisitions += 1
            return performer
        }
    }
    #expect(acquisitions == 0)
    #expect(performer.requests.isEmpty)
}

@Test @MainActor func repeatedMiddleTapsEachRequestOneImmediateHaptic() {
    let performer = RecordingPerformer()
    for _ in 0..<5 { HapticFeedback.perform(for: .commandClick) { performer } }
    #expect(performer.requests.count == 5)
    #expect(performer.requests.allSatisfy { $0.0 == .generic && $0.1 == .now })
}
