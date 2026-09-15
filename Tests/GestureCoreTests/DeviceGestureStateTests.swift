// SPDX-License-Identifier: GPL-3.0-only
import Testing

@testable import GestureCore

private let three = [
    Contact(id: 1, x: 0.2, y: 0.4), Contact(id: 2, x: 0.4, y: 0.4), Contact(id: 3, x: 0.6, y: 0.4),
]
private let four = three + [Contact(id: 4, x: 0.8, y: 0.4)]

@Test func fourthFingerInPressedFrameWinsOverPreviousThreeFingerFrame() {
    var device = DeviceGestureState()
    _ = device.frame(three, at: 1)
    device.buttonHeader(isDown: true)
    #expect(device.hasPendingPress)
    let result = device.frame(four, at: 1.008)
    #expect(result.action == .quitApplication)
    #expect(result.physicalPress)
    #expect(!device.hasPendingPress)
}
@Test func pressUsesCurrentFrameAfterLongIdle() {
    var device = DeviceGestureState()
    _ = device.frame([], at: 1)
    device.buttonHeader(isDown: true)
    #expect(device.frame(three, at: 5).action == .closeWindow)
}
@Test func physicalReleaseDoesNotCreateMiddleTap() {
    var device = DeviceGestureState()
    _ = device.frame([three[0], three[2]], at: 1)
    _ = device.frame(three, at: 1.1)
    device.buttonHeader(isDown: true)
    #expect(device.frame(three, at: 1.15).action == .closeWindow)
    device.buttonHeader(isDown: false)
    #expect(device.frame([three[0], three[2]], at: 1.2).action == nil)
}
@Test func aHeldButtonCannotRepeatWhenFingerCountChanges() {
    var device = DeviceGestureState()
    device.buttonHeader(isDown: true)
    #expect(device.frame(three, at: 1).action == .closeWindow)
    #expect(device.frame(four, at: 1.01).action == nil)
    device.buttonHeader(isDown: true)
    #expect(device.frame(four, at: 1.02).action == nil)
}
@Test func resetDiscardsUndeliveredButtonHeader() {
    var device = DeviceGestureState()
    device.buttonHeader(isDown: true)
    device.reset()
    #expect(device.frame(four, at: 1).action == nil)
}
@Test func separateTrackpadsNeverCombineFingers() {
    var first = DeviceGestureState()
    var second = DeviceGestureState()
    _ = first.frame([three[0], three[1]], at: 1)
    _ = second.frame([three[2]], at: 1)
    first.buttonHeader(isDown: true)
    #expect(first.frame([three[0], three[1]], at: 1.01).action == nil)
}

@Test func releaseWithoutContactFrameRearmsNextPhysicalPress() {
    var device = DeviceGestureState()
    device.buttonHeader(isDown: true)
    #expect(device.frame(three, at: 1).action == .closeWindow)
    // A release-only header can be the last event of an interaction.
    device.buttonHeader(isDown: false)
    #expect(device.recognizer.buttonIsDown == false)
    // The next interaction starts with another button header, before any contacts.
    device.buttonHeader(isDown: true)
    #expect(device.frame(three, at: 2).action == .closeWindow)
    device.buttonHeader(isDown: false)
    device.buttonHeader(isDown: true)
    #expect(device.frame(four, at: 3).action == .quitApplication)
}

@Test func hardwarePressWithoutNextFrameUsesFreshContactsAndReleasesImmediately() {
    var device = DeviceGestureState()
    _ = device.frame(three, at: 1)
    device.buttonHeader(isDown: true)
    #expect(device.resolvePendingButton(at: 1.03).action == .closeWindow)
    #expect(device.resolvePendingButton(at: 1.04).action == nil)
    device.buttonHeader(isDown: false)
    #expect(!device.recognizer.buttonIsDown)
    _ = device.frame(four, at: 1.5)
    device.buttonHeader(isDown: true)
    #expect(device.resolvePendingButton(at: 1.53).action == .quitApplication)
}

@Test func hardwarePressWithoutFreshContactsNeverUsesOldFingerCount() {
    var device = DeviceGestureState()
    _ = device.frame(four, at: 1)
    device.buttonHeader(isDown: true)
    #expect(device.resolvePendingButton(at: 2).action == nil)
}

@Test func macOS27HardwareTimelineDistinguishesPressesFromThreeFingerDrag() {
    // Condensed from this Mac's 2026-09-15 capture. Mouse-down precedes the
    // hardware value by 27 ms / 18 ms. Dragging has no hardware transition.
    var device = DeviceGestureState()
    var gate = ClickGate()
    for (start, fingers, expected) in [
        (37.0, three, GestureAction.closeWindow),
        (38.57, four, .quitApplication),
        (40.0, three, .closeWindow),
    ] {
        _ = device.frame(fingers, at: start)
        #expect(!gate.mouseDown(button: 0, at: start + 0.024).swallow)
        if start != 40 {
            device.buttonHeader(isDown: true)
            let pressed = device.frame(fingers, at: start + 0.055)
            #expect(pressed.action == expected)
            gate.physicalPress(pressed.action, at: start + 0.055)
            #expect(gate.mouseDown(button: 0, at: start + 0.074).swallow)
            device.buttonHeader(isDown: false)
            #expect(gate.mouseUp(button: 0) == true)
        } else {
            #expect(!gate.mouseDown(button: 0, at: start + 0.074).swallow)
            #expect(gate.mouseUp(button: 0) == false)
        }
        _ = device.frame([], at: start + 0.5)
    }
}

@Test func delayedHardwareValueStillSuppressesBufferedClick() {
    var device = DeviceGestureState()
    var gate = ClickGate()
    _ = device.frame(four, at: 1)
    #expect(!gate.mouseDown(button: 0, at: 1.001).swallow)
    // The final acceptance capture included a 54 ms hardware delivery delay.
    _ = device.frame(four, at: 1.05)
    // Hardware down arrives at 1.055; no contact update follows before the fallback.
    device.buttonHeader(isDown: true)
    let result = device.resolvePendingButton(at: 1.067)
    #expect(result.action == .quitApplication)
    gate.physicalPress(result.action, at: 1.067)
    #expect(gate.mouseDown(button: 0, at: 1.081).swallow)
    #expect(gate.mouseUp(button: 0) == true)
}

@Test func duplicateHardwareEdgeDoesNotCancelRecognizedPress() {
    var device = DeviceGestureState()
    device.buttonHeader(isDown: true)
    #expect(device.frame(three, at: 1).action == .closeWindow)
    device.buttonHeader(isDown: true)
    let duplicate = device.frame(three, at: 1.01)
    #expect(!duplicate.physicalPress)
    #expect(duplicate.action == nil)
}

@Test func optionChangeDiscardsAnUndeliveredPress() {
    var device = DeviceGestureState()
    device.buttonHeader(isDown: true)
    device.options.fourFingerPress = false
    #expect(!device.hasPendingPress)
    #expect(device.frame(three, at: 1).action == nil)
}
