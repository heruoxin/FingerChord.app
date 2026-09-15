import Foundation

public struct Contact: Equatable, Sendable, Identifiable {
    public let id: Int32
    public let x: Double
    public let y: Double

    public init(id: Int32, x: Double, y: Double) { self.id = id; self.x = x; self.y = y }
    func distance(to other: Contact) -> Double { hypot(x - other.x, y - other.y) }
}

public enum GestureAction: String, Sendable {
    case commandClick, closeWindow, quitApplication
}

public struct GestureOptions: Equatable, Sendable {
    public var middleTap = true
    public var threeFingerPress = true
    public var fourFingerPress = true
    public init() {}
}

/// One recognizer per touch surface. All times are monotonic seconds supplied by the caller.
public struct GestureRecognizer: Sendable {
    public var options = GestureOptions() {
        didSet { if options != oldValue { reset() } }
    }
    public private(set) var contacts: [Contact] = []
    public private(set) var lastFrameTime: Double = -.infinity
    public private(set) var buttonIsDown = false
    private var anchors: [Contact] = []
    private var anchorsSince: Double = 0
    private var middle: Contact?
    private var middleSince: Double = 0
    private var blockedUntilLift = false
    private var lastTap: Double = -.infinity

    public init() {}

    public mutating func reset() {
        contacts = []; anchors = []; middle = nil
        lastFrameTime = -.infinity; buttonIsDown = false
        blockedUntilLift = false; lastTap = -.infinity
    }

    public func pressAction(at time: Double) -> GestureAction? {
        guard time >= lastFrameTime, time - lastFrameTime < 0.18 else { return nil }
        if contacts.count == 3 && options.threeFingerPress { return .closeWindow }
        if contacts.count == 4 && options.fourFingerPress { return .quitApplication }
        return nil
    }

    /// Called from the trackpad's hardware button callback, never from tap-to-click events.
    public mutating func buttonChanged(isDown: Bool, at time: Double) -> GestureAction? {
        guard buttonIsDown != isDown else { return nil }
        buttonIsDown = isDown
        middle = nil; anchors = []; blockedUntilLift = true
        guard isDown else { return nil }
        return pressAction(at: time)
    }

    public mutating func cancelTap() {
        middle = nil; anchors = []; blockedUntilLift = true
    }

    @discardableResult
    public mutating func update(_ newContacts: [Contact], at time: Double) -> GestureAction? {
        // A broken stream must never preserve a chord or use a stale finger count.
        if time < lastFrameTime || time - lastFrameTime > 0.25 {
            anchors = []; middle = nil
        }
        contacts = newContacts
        lastFrameTime = time
        if contacts.isEmpty {
            anchors = []; middle = nil; blockedUntilLift = false
            return nil
        }
        guard options.middleTap, !buttonIsDown, !blockedUntilLift else { return nil }

        if let middle {
            guard anchorsAreStable(in: contacts) else { cancelTap(); return nil }
            let elapsed = time - middleSince
            if contacts.count == 2, !contacts.contains(where: { $0.id == middle.id }) {
                self.middle = nil
                anchors = contacts.sorted { $0.x < $1.x }
                anchorsSince = time
                if elapsed >= 0.025 && elapsed <= 0.26 && time - lastTap >= 0.18 {
                    lastTap = time
                    return .commandClick
                }
                return nil
            }
            guard contacts.count == 3,
                  let current = contacts.first(where: { $0.id == middle.id }),
                  current.distance(to: middle) < 0.04, elapsed <= 0.26 else {
                cancelTap(); return nil
            }
            return nil
        }

        if contacts.count == 2 {
            if anchors.count != 2 || !anchorsAreStable(in: contacts) {
                anchors = contacts.sorted { $0.x < $1.x }; anchorsSince = time
            }
        } else if contacts.count == 3, anchors.count == 2,
                  time - anchorsSince >= 0.08, anchorsAreStable(in: contacts),
                  let added = contacts.first(where: { c in !anchors.contains(where: { $0.id == c.id }) }) {
            let left = anchors[0], right = anchors[1]
            // Both hands work. The new finger must be horizontally between the resting fingers.
            let span = right.x - left.x
            guard span >= 0.065, span <= 0.65,
                  added.x > left.x + span * 0.13, added.x < right.x - span * 0.13,
                  abs(added.y - (left.y + right.y) / 2) <= 0.30 else {
                cancelTap(); return nil
            }
            middle = added; middleSince = time
        } else {
            anchors = []
        }
        return nil
    }

    private func anchorsAreStable(in touches: [Contact]) -> Bool {
        anchors.count == 2 && anchors.allSatisfy { anchor in
            touches.contains { $0.id == anchor.id && $0.distance(to: anchor) < 0.045 }
        }
    }
}
