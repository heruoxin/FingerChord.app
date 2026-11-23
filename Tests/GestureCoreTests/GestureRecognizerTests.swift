// SPDX-License-Identifier: GPL-3.0-only
import Testing

@testable import GestureCore

private let left = Contact(id: 1, x: 0.30, y: 0.40)
private let right = Contact(id: 2, x: 0.64, y: 0.40)
private let middle = Contact(id: 3, x: 0.47, y: 0.57)
private let fourth = Contact(id: 4, x: 0.80, y: 0.38)
private func prepared() -> GestureRecognizer {
    var r = GestureRecognizer()
    r.update([left, right], at: 1.0)
    r.update([left, right], at: 1.1)
    r.update([left, right, middle], at: 1.12)
    return r
}

@Test func middleTapCompletesOnLift() {
    var r = prepared()
    #expect(r.update([left, right, middle], at: 1.17) == nil)
    #expect(r.update([left, right], at: 1.21) == .middleTap)
    #expect(r.update([left, right], at: 1.23) == nil)
}
@Test func repeatedMiddleTapsWithRestingAnchors() {
    var r = prepared()
    #expect(r.update([left, right], at: 1.20) == .middleTap)
    r.update([left, right, middle], at: 1.32)
    #expect(r.update([left, right], at: 1.42) == .middleTap)
}
@Test func simultaneousThreeFingerTapDoesNotMatch() {
    var r = GestureRecognizer()
    r.update([left, right, middle], at: 1.0)
    #expect(r.update([], at: 1.1) == nil)
}
@Test func anchorsMustSettle() {
    var r = GestureRecognizer()
    r.update([left, right], at: 1.0)
    r.update([left, right, middle], at: 1.03)
    #expect(r.update([left, right], at: 1.1) == nil)
}
@Test func outerFingerTapDoesNotMatch() {
    var r = GestureRecognizer()
    r.update([left, right], at: 1)
    r.update([left, right, fourth], at: 1.1)
    #expect(r.update([left, right], at: 1.2) == nil)
}
@Test func longHoldDoesNotTap() {
    var r = prepared()
    r.update([left, right, middle], at: 1.3)
    #expect(r.update([left, right], at: 1.45) == nil)
}
@Test func oneFrameNoiseDoesNotTap() {
    var r = prepared()
    #expect(r.update([left, right], at: 1.128) == nil)
}
@Test func swipeCancelsTap() {
    var r = prepared()
    let moved = Contact(id: 3, x: 0.60, y: 0.60)
    r.update([left, right, moved], at: 1.18)
    #expect(r.update([left, right], at: 1.22) == nil)
}
@Test func anchorMovementCancelsTap() {
    var r = prepared()
    let moved = Contact(id: 1, x: 0.4, y: 0.4)
    r.update([moved, right, middle], at: 1.16)
    #expect(r.update([moved, right], at: 1.20) == nil)
}
@Test func liftingAnchorDoesNotTap() {
    var r = prepared()
    #expect(r.update([left, middle], at: 1.2) == nil)
}
@Test func fourthContactCancelsTap() {
    var r = prepared()
    r.update([left, right, middle, fourth], at: 1.16)
    r.update([left, right, middle], at: 1.18)
    #expect(r.update([left, right], at: 1.2) == nil)
}
@Test func threeFingerPhysicalPress() {
    var r = prepared()
    #expect(r.buttonChanged(isDown: true, at: 1.14) == .threePress)
    #expect(r.buttonChanged(isDown: true, at: 1.15) == nil)
    #expect(r.buttonChanged(isDown: false, at: 1.16) == nil)
    #expect(r.update([left, right], at: 1.2) == nil)
}
@Test func fourFingerPhysicalPress() {
    var r = GestureRecognizer()
    r.update([left, right, middle, fourth], at: 1)
    #expect(r.buttonChanged(isDown: true, at: 1.01) == .fourPress)
}
@Test func fiveFingerPressDoesNothing() {
    var r = GestureRecognizer()
    r.update([left, right, middle, fourth, Contact(id: 5, x: 0.9, y: 0.3)], at: 1)
    #expect(r.buttonChanged(isDown: true, at: 1.01) == nil)
}
@Test func staleFramesNeverCloseWindows() {
    var r = prepared()
    #expect(r.buttonChanged(isDown: true, at: 2) == nil)
}
@Test func allSwitchesAreIndependent() {
    var r = GestureRecognizer()
    r.enabled = [.fourPress]
    r.update([left, right, middle], at: 1)
    #expect(r.buttonChanged(isDown: true, at: 1.01) == nil)
    _ = r.buttonChanged(isDown: false, at: 1.02)
    r.update([left, right, middle, fourth], at: 1.03)
    #expect(r.buttonChanged(isDown: true, at: 1.04) == .fourPress)
    r.enabled = []
    r.update([left, right, middle, fourth], at: 1.1)
    #expect(r.buttonChanged(isDown: true, at: 1.11) == nil)
}
@Test func disablingTapCancelsInFlightGesture() {
    var r = prepared()
    r.enabled.remove(.middleTap)
    #expect(r.update([left, right], at: 1.2) == nil)
}
@Test func frameGapCancelsGesture() {
    var r = prepared()
    #expect(r.update([left, right], at: 2) == nil)
}
@Test func canceledChordRecoversAfterAllFingersLift() {
    var r = prepared()
    r.cancelTap()
    #expect(r.update([left, right], at: 1.2) == nil)
    r.update([], at: 1.25)
    r.update([left, right], at: 1.3)
    r.update([left, right, middle], at: 1.4)
    #expect(r.update([left, right], at: 1.5) == .middleTap)
}
@Test func reversedContactOrderWorks() {
    var r = GestureRecognizer()
    r.update([right, left], at: 1)
    r.update([middle, right, left], at: 1.1)
    #expect(r.update([right, left], at: 1.2) == .middleTap)
}
@Test func resettingDropsPressedState() {
    var r = prepared()
    _ = r.buttonChanged(isDown: true, at: 1.13)
    r.reset()
    #expect(!r.buttonIsDown)
    #expect(r.contacts.isEmpty)
    #expect(r.pressAction(at: 1.14) == nil)
}

@Test func cancelledTapRearmsWithRestingPairWithoutLiftingEveryFinger() {
    var r = prepared()
    r.cancelTap()
    #expect(r.update([left, right], at: 1.2) == nil)
    #expect(r.update([left, right], at: 1.32) == nil)
    r.update([left, right, middle], at: 1.34)
    #expect(r.update([left, right], at: 1.44) == .middleTap)
    r.update([left, right, middle], at: 1.56)
    #expect(r.update([left, right], at: 1.66) == .middleTap)
}

@Test func longMiddleHoldDoesNotDisableLaterTaps() {
    var r = prepared()
    r.update([left, right, middle], at: 1.30)
    r.update([left, right, middle], at: 1.40)
    #expect(r.update([left, right], at: 1.45) == nil)
    r.update([left, right], at: 1.57)
    r.update([left, right, middle], at: 1.60)
    #expect(r.update([left, right], at: 1.70) == .middleTap)
}

@Test func movingPairAndHeldButtonCannotRearmMiddleTap() {
    var r = prepared()
    r.cancelTap()
    r.update([left, right], at: 1.20)
    let moved = Contact(id: 1, x: 0.36, y: 0.40)
    r.update([moved, right], at: 1.29)
    r.update([moved, right, middle], at: 1.33)
    #expect(r.update([moved, right], at: 1.43) == nil)
    _ = r.buttonChanged(isDown: true, at: 1.44)
    r.update([left, right], at: 1.50)
    r.update([left, right], at: 1.65)
    r.update([left, right, middle], at: 1.7)
    #expect(r.update([left, right], at: 1.8) == nil)
}

@Test func scrollingPairNeverArmsAChord() {
    var r = GestureRecognizer()
    func scrolled(_ step: Int, _ contacts: [Contact]) -> [Contact] {
        contacts.map { Contact(id: $0.id, x: $0.x, y: $0.y + Double(step) * 0.004) }
    }
    for step in 0..<30 { r.update(scrolled(step, [left, right]), at: 1 + Double(step) * 0.008) }
    r.update(scrolled(30, [left, right, middle]), at: 1.24)
    #expect(r.update(scrolled(31, [left, right]), at: 1.33) == nil)
}

@Test func oneAndTwoFingerClicksAreNeverHeld() {
    var r = GestureRecognizer()
    r.update([left], at: 1)
    #expect(!r.mayOwnClick(at: 1.01))
    r.update([left, right], at: 1.02)
    #expect(!r.mayOwnClick(at: 1.03))
}

@Test func onlyFreshChordsMayOwnAClick() {
    var r = prepared()
    #expect(r.mayOwnClick(at: 1.13))
    #expect(!r.mayOwnClick(at: 1.4))
    r.update([left, right, middle, fourth], at: 1.41)
    #expect(r.mayOwnClick(at: 1.42))
    r.update([], at: 1.43)
    #expect(!r.mayOwnClick(at: 1.44))
}

@Test func disabledGesturesNeverHoldClicks() {
    var r = GestureRecognizer()
    r.enabled = []
    r.update([left, right, middle], at: 1)
    #expect(!r.mayOwnClick(at: 1.01))
}
