// SPDX-License-Identifier: GPL-3.0-only
import Testing

@testable import GestureCore

@Test func physicalClickSuppressesWholeMouseSequence() {
    var gate = ClickGate()
    gate.physicalPress(.closeWindow, at: 1)
    let result = gate.mouseDown(button: 0, at: 1.01)
    #expect(result.swallow && result.action == .closeWindow)
    #expect(gate.shouldSwallowDrag(button: 0))
    #expect(gate.mouseUp(button: 1) == false)
    #expect(gate.mouseUp(button: 0) == true)
    #expect(gate.mouseUp(button: 0) == false)
}
@Test func ordinaryMouseClickPassesThrough() {
    var gate = ClickGate()
    #expect(!gate.mouseDown(button: 0, at: 1).swallow)
    #expect(gate.mouseUp(button: 0) == false)
}
@Test func staleHardwarePressDoesNotHijackNextClick() {
    var gate = ClickGate()
    gate.physicalPress(.quitApplication, at: 1)
    #expect(!gate.mouseDown(button: 0, at: 1.2).swallow)
}
@Test func switchingGestureOffPreservesSuppressedUp() {
    var gate = ClickGate()
    gate.physicalPress(.closeWindow, at: 1)
    #expect(gate.mouseDown(button: 1, at: 1.01).swallow)
    gate.cancelPending()
    #expect(gate.mouseUp(button: 1) == true)
}
@Test func disabledGestureDoesNotSuppressMouse() {
    var gate = ClickGate()
    gate.physicalPress(nil, at: 1)
    #expect(!gate.mouseDown(button: 0, at: 1.01).swallow)
}
@Test func duplicateDownCannotReuseAnAction() {
    var gate = ClickGate()
    gate.physicalPress(.quitApplication, at: 1)
    #expect(gate.mouseDown(button: 0, at: 1.01).action == .quitApplication)
    #expect(gate.mouseDown(button: 0, at: 1.02).action == nil)
}
@Test func pressAfterItsClickReachedAnAppStaysPlain() {
    var gate = ClickGate()
    gate.delivered(at: 1)
    #expect(gate.physicalPress(.closeWindow, at: 1.07) == nil)
    #expect(!gate.mouseDown(button: 0, at: 1.08).swallow)
}
@Test func earlierDeliveredClickDoesNotBlockNextPress() {
    var gate = ClickGate()
    gate.delivered(at: 1)
    #expect(gate.physicalPress(.closeWindow, at: 1.2) == .closeWindow)
    #expect(gate.mouseDown(button: 0, at: 1.21).swallow)
}
@Test func plainPressConsumesItsDeliveredClick() {
    var gate = ClickGate()
    gate.delivered(at: 1)
    #expect(gate.physicalPress(nil, at: 1.03) == nil)
    #expect(gate.physicalPress(.closeWindow, at: 1.1) == .closeWindow)
}
