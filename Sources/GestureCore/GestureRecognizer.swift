// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public struct Contact: Equatable, Sendable, Identifiable {
    public let id: Int32
    public let x: Double
    public let y: Double

    public init(id: Int32, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
    func distance(to other: Contact) -> Double { hypot(x - other.x, y - other.y) }
}

public enum Gesture: String, CaseIterable, Sendable {
    case middleTap, threePress, fourPress

    public var isPress: Bool { self != .middleTap }
}

/// One recognizer per touch surface. All times are monotonic seconds supplied by the caller.
public struct GestureRecognizer: Sendable {
    public var enabled = Set(Gesture.allCases) {
        didSet { if enabled != oldValue { reset() } }
    }
    public private(set) var contacts: [Contact] = []
    public private(set) var lastFrameTime: Double = -.infinity
    public private(set) var buttonIsDown = false
    private var anchors: [Contact] = []
    private var anchorsSince: Double = 0
    private var middle: (finger: Contact, since: Double)?
    private var lastTap: Double = -.infinity

    public init() {}

    public mutating func reset() {
        contacts = []
        anchors = []
        middle = nil
        lastFrameTime = -.infinity
        buttonIsDown = false
        lastTap = -.infinity
    }

    public func pressAction(at time: Double) -> Gesture? {
        guard time >= lastFrameTime, time - lastFrameTime < 0.18 else { return nil }
        let gesture: Gesture? = [3: .threePress, 4: .fourPress][contacts.count]
        return gesture.flatMap { enabled.contains($0) ? $0 : nil }
    }

    /// Every gesture needs three or more fresh contacts. Other system clicks need no delay.
    public func mayOwnClick(at time: Double) -> Bool {
        !enabled.isEmpty && contacts.count >= 3 && time - lastFrameTime < 0.18
    }

    /// Called from the trackpad's hardware button callback, never from tap-to-click events.
    public mutating func buttonChanged(isDown: Bool, at time: Double) -> Gesture? {
        guard buttonIsDown != isDown else { return nil }
        buttonIsDown = isDown
        cancelTap()
        return isDown ? pressAction(at: time) : nil
    }

    public mutating func cancelTap() {
        middle = nil
        anchors = []
    }

    @discardableResult
    public mutating func update(_ newContacts: [Contact], at time: Double) -> Gesture? {
        // A broken stream must never preserve a chord or use a stale finger count.
        if time < lastFrameTime || time - lastFrameTime > 0.25 { cancelTap() }
        contacts = newContacts
        lastFrameTime = time
        guard enabled.contains(.middleTap), !buttonIsDown else { return nil }
        if let middle {
            guard anchorsHeld(within: 0.045) else {
                cancelTap()
                return nil
            }
            let elapsed = time - middle.since
            if contacts.count == 2 {
                self.middle = nil
                rest(at: time)
                guard elapsed >= 0.025, elapsed <= 0.26, time - lastTap >= 0.18 else { return nil }
                lastTap = time
                return .middleTap
            }
            if contacts.count != 3 || elapsed > 0.26
                || !contacts.contains(where: { $0.id == middle.finger.id && $0.distance(to: middle.finger) < 0.04 })
            {
                cancelTap()
            }
            return nil
        }
        switch contacts.count {
        case 2:
            // Resting means still: a scrolling pair keeps restarting its clock.
            if !anchorsHeld(within: 0.015) { rest(at: time) }
        case 3 where time - anchorsSince >= 0.08 && anchorsHeld(within: 0.045):
            let finger = contacts.first { contact in !anchors.contains { $0.id == contact.id } }!
            if isBetweenAnchors(finger) { middle = (finger, time) } else { cancelTap() }
        default:
            anchors = []
        }
        return nil
    }

    /// Both hands work. The new finger must be horizontally between the resting fingers.
    private func isBetweenAnchors(_ finger: Contact) -> Bool {
        let left = anchors[0]
        let right = anchors[1]
        let span = right.x - left.x
        return span >= 0.065 && span <= 0.65
            && finger.x > left.x + span * 0.13 && finger.x < right.x - span * 0.13
            && abs(finger.y - (left.y + right.y) / 2) <= 0.30
    }

    private mutating func rest(at time: Double) {
        anchors = contacts.sorted { $0.x < $1.x }
        anchorsSince = time
    }

    private func anchorsHeld(within limit: Double) -> Bool {
        anchors.count == 2
            && anchors.allSatisfy { anchor in
                contacts.contains { $0.id == anchor.id && $0.distance(to: anchor) < limit }
            }
    }
}
