import Testing
@testable import GestureCore

private let three = [Contact(id: 1, x: 0.2, y: 0.4), Contact(id: 2, x: 0.4, y: 0.4), Contact(id: 3, x: 0.6, y: 0.4)]
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
    var first = DeviceGestureState(), second = DeviceGestureState()
    _ = first.frame([three[0], three[1]], at: 1)
    _ = second.frame([three[2]], at: 1)
    first.buttonHeader(isDown: true)
    #expect(first.frame([three[0], three[1]], at: 1.01).action == nil)
}
