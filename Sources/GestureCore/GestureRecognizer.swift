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
    case middleTap, leftTap, rightTap, threeTap, threePress, fourPress

    public static let defaults: Set<Gesture> = [.middleTap, .threePress, .fourPress]
    public var isPress: Bool { self == .threePress || self == .fourPress }
}

/// One recognizer per touch surface. All times are monotonic seconds supplied by the caller.
public struct GestureRecognizer: Sendable {
    public var enabled = Gesture.defaults {
        didSet { if enabled != oldValue { reset() } }
    }
    public private(set) var contacts: [Contact] = []
    public private(set) var lastFrameTime: Double = -.infinity
    public private(set) var buttonIsDown = false
    private var anchors: [Contact] = []
    private var anchorsSince: Double = 0
    private var tap: (finger: Contact, gesture: Gesture, since: Double)?
    private var lastTap: Double = -.infinity
    private var burst = Burst()

    /// Three fingers that land together, stay put and lift together.
    private struct Burst: Sendable {
        var start: Double = 0
        var landed: Double?
        var origins: [Int32: Contact] = [:]
        var live = false
    }

    public init() {}

    public mutating func reset() {
        contacts = []
        anchors = []
        tap = nil
        burst = Burst()
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

    /// Any button edge or broken chord also ends a three finger tap in progress.
    public mutating func cancelTap() {
        tap = nil
        anchors = []
        burst.live = false
    }

    @discardableResult
    public mutating func update(_ newContacts: [Contact], at time: Double) -> Gesture? {
        // A broken stream must never preserve a chord or use a stale finger count.
        let broken = time < lastFrameTime || time - lastFrameTime > 0.25
        if broken { cancelTap() }
        let began = contacts.isEmpty
        contacts = newContacts
        lastFrameTime = time
        if buttonIsDown { return nil }
        return chord(at: time) ?? threeFingerTap(began: began, at: time)
    }

    private mutating func chord(at time: Double) -> Gesture? {
        guard !enabled.isDisjoint(with: [.middleTap, .leftTap, .rightTap]) else { return nil }
        if let tap {
            guard anchorsHeld(within: 0.045) else {
                cancelTap()
                return nil
            }
            let elapsed = time - tap.since
            if contacts.count == 2 {
                self.tap = nil
                rest(at: time)
                guard elapsed >= 0.025, elapsed <= 0.26, time - lastTap >= 0.18 else { return nil }
                lastTap = time
                burst.live = false
                return tap.gesture
            }
            if contacts.count != 3 || elapsed > 0.26
                || !contacts.contains(where: { $0.id == tap.finger.id && $0.distance(to: tap.finger) < 0.04 })
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
            if let gesture = side(of: finger), enabled.contains(gesture) {
                tap = (finger, gesture, time)
            } else {
                cancelTap()
            }
        default:
            anchors = []
        }
        return nil
    }

    private func side(of finger: Contact) -> Gesture? {
        let left = anchors[0]
        let right = anchors[1]
        let span = right.x - left.x
        guard span >= 0.065, span <= 0.65, abs(finger.y - (left.y + right.y) / 2) <= 0.30 else { return nil }
        if finger.x > left.x + span * 0.13 && finger.x < right.x - span * 0.13 { return .middleTap }
        if (0.04...0.4).contains(left.x - finger.x) { return .leftTap }
        if (0.04...0.4).contains(finger.x - right.x) { return .rightTap }
        return nil
    }

    private mutating func threeFingerTap(began: Bool, at time: Double) -> Gesture? {
        if began { burst = Burst(start: time, live: enabled.contains(.threeTap)) }
        guard burst.live else { return nil }
        for contact in contacts {
            if let origin = burst.origins[contact.id] {
                if contact.distance(to: origin) > 0.03 { burst.live = false }
            } else {
                burst.origins[contact.id] = contact
            }
        }
        if contacts.count == 3 && burst.landed == nil { burst.landed = time }
        if burst.origins.count > 3 || time - burst.start > 0.3 || (burst.landed ?? burst.start) - burst.start > 0.07 {
            burst.live = false
        }
        guard burst.live, contacts.isEmpty, burst.landed != nil else { return nil }
        burst.live = false
        return .threeTap
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
