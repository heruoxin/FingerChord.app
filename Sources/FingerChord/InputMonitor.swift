// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import GestureCore
import TouchBridge

struct MonitorSnapshot: Equatable {
    var contacts: [Contact] = []
    var buttonDown = false
}

final class InputMonitor {
    static let eventMarker: Int64 = 0x46_434F_5244
    private let lock = NSLock()
    private var devices: [UInt: DeviceGestureState] = [:]
    private var clickGates: [UInt64: ClickGate] = [:]
    private var senders: Set<UInt64> = []
    private var deviceSenders: [UInt: UInt64] = [:]
    private var options = GestureOptions()
    private var observer: ((MonitorSnapshot) -> Void)?
    private var previewQueued = false
    // Mouse events and MultitouchSupport are delivered independently. Buffer button-down events
    // briefly so either delivery order produces the same result, without blocking the event tap.
    // A released click reposts its remaining events too; a real up must never overtake its reposted down.
    private struct ClickKey: Hashable {
        let sender: UInt64
        let button: Int64
    }
    private struct BufferedClick {
        let token = UUID()
        var events: [CGEvent]
        var released = false
        var finished: Bool { events.contains { $0.type == .leftMouseUp || $0.type == .rightMouseUp } }
    }
    private var bufferedClicks: [ClickKey: BufferedClick] = [:]
    // Protect the generation with the same lock as recognition, including worker callbacks.
    private var generation: UInt64 = 0
    private var ownsBridge = false
    private var running = false
    private var taps: [(port: CFMachPort, source: CFRunLoopSource)] = []
    private let hardwareButtons = HardwareButtonMonitor()
    private(set) var deviceCount = 0
    private(set) var error: String?
    var onAction: ((GestureAction) -> Void)?

    var isRunning: Bool { lock.withLock { running } }
    var isEventTapEnabled: Bool { !taps.isEmpty && taps.allSatisfy { CGEvent.tapIsEnabled(tap: $0.port) } }
    var devicesHealthy: Bool { FCDevicesHealthy() }

    /// Streams the live preview on the main queue while a handler is set.
    func observe(_ handler: ((MonitorSnapshot) -> Void)?) {
        lock.withLock {
            observer = handler
            publishPreview()
        }
    }

    func setOptions(_ value: GestureOptions) {
        lock.withLock {
            options = value
            for key in Array(devices.keys) { devices[key]?.options = value }
            for key in Array(clickGates.keys) { clickGates[key]?.cancelPending() }
        }
    }

    @discardableResult func start() -> Bool {
        if isRunning { return true }
        error = nil
        DiagnosticTrace.record("monitorStart")
        guard AXIsProcessTrusted() else {
            error = "error.accessibility"
            return false
        }
        guard CGPreflightListenEventAccess() else {
            error = "error.input"
            return false
        }
        let clicks: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .leftMouseDragged, .rightMouseDragged,
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Scrolls are only observed, so system scrolling never waits for this process.
        for (types, option) in [(clicks, CGEventTapOptions.defaultTap), ([.scrollWheel], .listenOnly)] {
            guard
                let port = CGEvent.tapCreate(
                    tap: .cghidEventTap, place: .headInsertEventTap, options: option,
                    eventsOfInterest: types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) },
                    callback: { _, type, event, context in
                        Unmanaged<InputMonitor>.fromOpaque(context!).takeUnretainedValue().handle(type, event)
                    }, userInfo: context)
            else {
                stop()
                error = "error.tap"
                return false
            }
            let source: CFRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            taps.append((port, source))
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
        }
        lock.withLock {
            generation &+= 1
            running = true
        }
        ownsBridge = true
        deviceCount = Int(
            FCStart(
                { device, data, count, context in
                    guard let context, count >= 0 else { return }
                    let monitor = Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue()
                    DiagnosticTrace.record(
                        "raw",
                        [
                            "device": device,
                            "touches": UnsafeBufferPointer(start: data, count: Int(count)).map {
                                [
                                    "id": Double($0.identifier), "state": Double($0.state), "x": Double($0.x),
                                    "y": Double($0.y),
                                ]
                            },
                        ])
                    let contacts = UnsafeBufferPointer(start: data, count: Int(count)).compactMap {
                        touch -> Contact? in
                        guard touch.state == 3 || touch.state == 4, touch.x.isFinite, touch.y.isFinite,
                            touch.x >= 0, touch.x <= 1, touch.y >= 0, touch.y <= 1
                        else { return nil }
                        return Contact(id: touch.identifier, x: Double(touch.x), y: Double(touch.y))
                    }
                    monitor.receiveFrame(device: device, contacts: contacts)
                },
                { device, down, context in
                    guard let context else { return }
                    Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue().receiveButton(
                        device: device, down: down)
                }, context))
        if deviceCount <= 0 {
            let message = String(cString: FCError())
            stop()
            error = message
            return false
        }
        hardwareButtons.onButton = { [weak self] device, down in
            self?.receiveButton(device: device, down: down)
        }
        guard hardwareButtons.start() else {
            stop()
            error = "error.button"
            return false
        }
        return true
    }

    func stop() {
        DiagnosticTrace.record("monitorStop")
        lock.withLock {
            running = false
            generation &+= 1
        }
        hardwareButtons.stop()
        if ownsBridge {
            FCStop()  // Unregister and drain framework callbacks before releasing their context.
            ownsBridge = false
        }
        for tap in taps {
            CGEvent.tapEnable(tap: tap.port, enable: false)
            CFMachPortInvalidate(tap.port)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tap.source, .commonModes)
        }
        taps = []
        deviceCount = 0
        for batch in bufferedClicks.values where batch.finished { replay(batch.events) }
        bufferedClicks = [:]
        lock.withLock {
            devices = [:]
            clickGates = [:]
            senders = []
            deviceSenders = [:]
            publishPreview()
        }
    }

    deinit { stop() }

    private func receiveFrame(device: UInt, contacts: [Contact]) {
        let now = ProcessInfo.processInfo.systemUptime
        let recognized: (GestureAction, UInt64)? = lock.withLock {
            guard running else { return nil }
            var state = devices[device] ?? DeviceGestureState()
            state.options = options
            let result = state.frame(contacts, at: now)
            var action = result.action
            DiagnosticTrace.record(
                "frame",
                [
                    "device": device, "state": state.recognizer.debugState, "physical": result.physicalPress,
                    "action": result.action?.rawValue ?? "none",
                ])
            let sender = deviceSenders[device] ?? FCSenderID(device)
            if sender != 0 {
                deviceSenders[device] = sender
                senders.insert(sender)
                if result.physicalPress || action == .commandClick {
                    action = clickGates[sender, default: ClickGate()].physicalPress(action, at: now)
                }
            }
            devices[device] = state
            publishPreview()
            return action.map { ($0, generation) }
        }
        if let (action, generation) = recognized { deliver(action, generation: generation) }
    }

    private func receiveButton(device: UInt, down: Bool) {
        DiagnosticTrace.record("button", ["device": device, "down": down])
        let session: UInt64? = lock.withLock {
            guard running else { return nil }
            // Resolve against the next contact frame to include a fourth finger landing
            // with the press. The fallback below handles a stationary contact stream.
            if devices[device] == nil {
                var state = DeviceGestureState()
                state.options = options
                devices[device] = state
            }
            devices[device]?.buttonHeader(isDown: down)
            publishPreview()
            return generation
        }
        guard let session else { return }
        // A stationary finger or final release may have no following contact frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            self?.resolveButton(device: device, generation: session)
        }
    }

    private func resolveButton(device: UInt, generation session: UInt64) {
        let now = ProcessInfo.processInfo.systemUptime
        let action: GestureAction? = lock.withLock {
            guard running, generation == session, var state = devices[device] else { return nil }
            let result = state.resolvePendingButton(at: now)
            devices[device] = state
            var action = result.action
            if result.physicalPress {
                let sender = FCSenderID(device)
                if sender != 0 {
                    action = clickGates[sender, default: ClickGate()].physicalPress(action, at: now)
                }
            }
            publishPreview()
            return action
        }
        if let action { deliver(action, generation: session) }
    }

    // Caller holds the state lock. Frames coalesce into one pending main-queue update.
    private func publishPreview() {
        guard observer != nil, !previewQueued else { return }
        previewQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let (handler, snapshot) = self.lock.withLock {
                self.previewQueued = false
                return (
                    self.observer,
                    MonitorSnapshot(
                        contacts: self.devices.values.flatMap { $0.recognizer.contacts },
                        buttonDown: self.devices.values.contains { $0.recognizer.buttonIsDown })
                )
            }
            handler?(snapshot)
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DiagnosticTrace.record("tapDisabled", ["type": type.rawValue])
            // Clicks bypassed the disabled filter tap, so a held down replayed now could follow its own up.
            if !CGEvent.tapIsEnabled(tap: taps[0].port) {
                bufferedClicks = [:]
                lock.withLock {
                    clickGates = [:]
                    for key in Array(devices.keys) { devices[key]?.reset() }
                }
            }
            if isRunning { for tap in taps { CGEvent.tapEnable(tap: tap.port, enable: true) } }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.eventMarker {
            return Unmanaged.passUnretained(event)
        }
        let sender = HIDEventInfo.senderID(event)
        if [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(type) {
            DiagnosticTrace.record("mouse", ["type": type.rawValue, "sender": sender])
        }
        let now = ProcessInfo.processInfo.systemUptime
        let button: Int64 =
            (type == .rightMouseDown || type == .rightMouseUp || type == .rightMouseDragged) ? 1 : 0
        let key = ClickKey(sender: sender, button: button)
        let queued = bufferedClicks[key] != nil
        if type == .leftMouseDown || type == .rightMouseDown {
            resolveBufferedClick(key: key)
            bufferedClicks[key] = nil
        }
        var deferClick = false
        let swallow: Bool = lock.withLock {
            guard running, senders.contains(sender) else { return false }
            switch type {
            case .leftMouseDown, .rightMouseDown:
                let result = clickGates[sender, default: ClickGate()].mouseDown(button: button, at: now)
                if !result.swallow {
                    // HID switch values arrive up to 69 ms after CG down. Only clicks that the trackpad's
                    // current contacts could turn into a gesture wait for them, or that follow a reposted click.
                    deferClick =
                        queued
                        || devices.contains {
                            deviceSenders[$0.key] == sender && $0.value.recognizer.mayOwnClick(at: now)
                        }
                    if !deferClick { clickGates[sender]?.delivered(at: now) }
                }
                return result.swallow
            case .leftMouseUp, .rightMouseUp:
                return clickGates[sender, default: ClickGate()].mouseUp(button: button)
            case .leftMouseDragged, .rightMouseDragged:
                let swallowed = clickGates[sender, default: ClickGate()].shouldSwallowDrag(button: button)
                if !swallowed { cancelTap(sender: sender, reason: "drag") }
                return swallowed
            case .scrollWheel:
                // Momentum belongs to the previous scroll, even after the resting pair
                // is ready for another chord. An external mouse must not cancel it either.
                if event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 {
                    cancelTap(sender: sender, reason: "scroll")
                }
                return false
            default: return false
            }
        }
        if deferClick, let copy = event.copy() {
            let batch = BufferedClick(events: [copy])
            bufferedClicks[key] = batch
            let token = batch.token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.bufferedClicks[key]?.token == token else { return }
                self.resolveBufferedClick(key: key)
            }
            return nil
        }
        if type != .scrollWheel, let batch = bufferedClicks[key], let copy = event.copy() {
            if batch.released {
                replay([copy])
                if type == .leftMouseUp || type == .rightMouseUp { bufferedClicks[key] = nil }
            } else {
                bufferedClicks[key]?.events.append(copy)
            }
            return nil
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    // Caller holds the state lock.
    private func cancelTap(sender: UInt64, reason: String) {
        for device in Array(devices.keys) where sender != 0 && deviceSenders[device] == sender {
            devices[device]?.cancelTap()
            DiagnosticTrace.record("cancelTap", ["device": device, "reason": reason])
        }
    }

    private func resolveBufferedClick(key: ClickKey) {
        guard let batch = bufferedClicks[key], !batch.released else { return }
        let swallow = lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            let result = clickGates[key.sender, default: ClickGate()].mouseDown(button: key.button, at: now)
            if !result.swallow {
                clickGates[key.sender]?.delivered(at: now)
            } else if batch.finished {
                _ = clickGates[key.sender]?.mouseUp(button: key.button)
            }
            return result.swallow
        }
        DiagnosticTrace.record(
            "resolvedClick", ["sender": key.sender, "swallow": swallow, "events": batch.events.count])
        bufferedClicks[key] = swallow || batch.finished ? nil : BufferedClick(events: [], released: true)
        if !swallow { replay(batch.events) }
    }

    private func replay(_ events: [CGEvent]) {
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func deliver(_ action: GestureAction, generation session: UInt64) {
        DiagnosticTrace.record("recognized", ["action": action.rawValue])
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lock.withLock({ self.running && self.generation == session }) else {
                return
            }
            self.onAction?(action)
        }
    }
}
