// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import GestureCore
import TouchBridge

struct MonitorSnapshot: Equatable {
    var contacts: [Contact] = []
    var buttonDown = false
}

final class InputMonitor {
    static let eventMarker: Int64 = 0x46_434F_5244
    private typealias Tap = (port: CFMachPort, source: CFRunLoopSource)
    private let lock = NSLock()
    private var devices: [UInt: DeviceGestureState] = [:]
    private var clickGates: [UInt64: ClickGate] = [:]
    private var senders: Set<UInt64> = []
    private var deviceSenders: [UInt: UInt64] = [:]
    private var enabled = Set(Gesture.allCases)
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
    private var running = false
    private var clickTap: Tap?
    // Drags matter only while a click is held or swallowed. Otherwise the tap stays off and drags never wait for us.
    private var dragTap: Tap?
    private var dragTapEnabled = false
    private let hardwareButtons = HardwareButtonMonitor()
    private(set) var error: String?
    var onAction: ((Gesture) -> Void)?

    var isRunning: Bool { lock.withLock { running } }
    var isEventTapEnabled: Bool { clickTap.map { CGEvent.tapIsEnabled(tap: $0.port) } ?? false }
    var devicesHealthy: Bool { FCDevicesHealthy() }

    /// Streams every contact frame to the main queue while a handler is set.
    func observe(_ handler: ((MonitorSnapshot) -> Void)?) {
        FCSetStreaming(handler != nil)
        lock.withLock {
            observer = handler
            publishPreview()
        }
    }

    func setEnabled(_ value: Set<Gesture>) {
        lock.withLock {
            enabled = value
            for key in Array(devices.keys) { devices[key]?.enabled = value }
            for key in Array(clickGates.keys) { clickGates[key]?.cancelPending() }
        }
    }

    @discardableResult func start() -> Bool {
        if isRunning { return true }
        error = nil
        DiagnosticTrace.record("monitorStart")
        let context = Unmanaged.passUnretained(self).toOpaque()
        clickTap = makeTap([.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp], context)
        dragTap = makeTap([.leftMouseDragged, .rightMouseDragged], context)
        guard clickTap != nil, let dragTap else {
            stop()
            error = "error.tap"
            return false
        }
        CGEvent.tapEnable(tap: dragTap.port, enable: false)
        lock.withLock {
            generation &+= 1
            running = true
        }
        let started = FCStart(
            { device, data, count, context in
                let contacts = UnsafeBufferPointer(start: data, count: Int(count)).map {
                    Contact(id: $0.identifier, x: Double($0.x), y: Double($0.y))
                }
                Unmanaged<InputMonitor>.fromOpaque(context!).takeUnretainedValue().receiveFrame(
                    device: device, contacts: contacts)
            },
            { device, down, context in
                Unmanaged<InputMonitor>.fromOpaque(context!).takeUnretainedValue().receiveButton(
                    device: device, down: down)
            }, context)
        if started <= 0 {
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
        FCStop()  // Unregister and drain framework callbacks before releasing their context.
        for tap in [clickTap, dragTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap.port, enable: false)
            CFMachPortInvalidate(tap.port)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tap.source, .commonModes)
        }
        clickTap = nil
        dragTap = nil
        dragTapEnabled = false
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

    private func makeTap(_ types: [CGEventType], _ context: UnsafeMutableRawPointer) -> Tap? {
        guard
            let port = CGEvent.tapCreate(
                tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) },
                callback: { _, type, event, context in
                    Unmanaged<InputMonitor>.fromOpaque(context!).takeUnretainedValue().handle(type, event)
                }, userInfo: context)
        else { return nil }
        let source: CFRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return (port, source)
    }

    // Caller holds the state lock.
    private func freshState() -> DeviceGestureState {
        var state = DeviceGestureState()
        state.enabled = enabled
        return state
    }

    private func receiveFrame(device: UInt, contacts: [Contact]) {
        let now = ProcessInfo.processInfo.systemUptime
        let recognized: (Gesture, UInt64)? = lock.withLock {
            guard running else { return nil }
            let result = devices[device, default: freshState()].frame(contacts, at: now)
            var action = result.action
            let sender = deviceSenders[device] ?? FCSenderID(device)
            if sender != 0 {
                deviceSenders[device] = sender
                senders.insert(sender)
                // A middle tap can produce a system click too; the gate swallows it like a press.
                if result.physicalPress || action != nil {
                    action = clickGates[sender, default: ClickGate()].physicalPress(action, at: now)
                }
            }
            DiagnosticTrace.record(
                "frame",
                [
                    "device": device, "contacts": contacts.map { [Double($0.id), $0.x, $0.y] },
                    "physical": result.physicalPress, "action": action?.rawValue ?? "none",
                ])
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
            devices[device, default: freshState()].buttonHeader(isDown: down)
            publishPreview()
            return generation
        }
        guard let session else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            self?.resolveButton(device: device, generation: session)
        }
    }

    private func resolveButton(device: UInt, generation session: UInt64) {
        let now = ProcessInfo.processInfo.systemUptime
        let action: Gesture? = lock.withLock {
            guard running, generation == session, devices[device] != nil else { return nil }
            let result = devices[device]!.resolvePendingButton(at: now)
            var action = result.action
            let sender = deviceSenders[device] ?? FCSenderID(device)
            if result.physicalPress && sender != 0 {
                action = clickGates[sender, default: ClickGate()].physicalPress(action, at: now)
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
            if let clickTap, !CGEvent.tapIsEnabled(tap: clickTap.port) {
                // Clicks bypassed the disabled tap, so a held down replayed now could follow its own up.
                bufferedClicks = [:]
                lock.withLock {
                    clickGates = [:]
                    for key in Array(devices.keys) { devices[key]?.reset() }
                }
                CGEvent.tapEnable(tap: clickTap.port, enable: true)
            }
            dragTapEnabled = dragTap.map { CGEvent.tapIsEnabled(tap: $0.port) } ?? false
            updateDragTap()
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.eventMarker {
            return Unmanaged.passUnretained(event)
        }
        defer { updateDragTap() }
        let sender = HIDEventInfo.senderID(event)
        DiagnosticTrace.record("mouse", ["type": type.rawValue, "sender": sender])
        let now = ProcessInfo.processInfo.systemUptime
        let button: Int64 = [.rightMouseDown, .rightMouseUp, .rightMouseDragged].contains(type) ? 1 : 0
        let key = ClickKey(sender: sender, button: button)
        let isUp = type == .leftMouseUp || type == .rightMouseUp
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
            default:
                return clickGates[sender]?.shouldSwallowDrag(button: button) ?? false
            }
        }
        if deferClick, let copy = event.copy() {
            let batch = BufferedClick(events: [copy])
            bufferedClicks[key] = batch
            let token = batch.token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.bufferedClicks[key]?.token == token else { return }
                self.resolveBufferedClick(key: key)
                self.updateDragTap()
            }
            return nil
        }
        if let batch = bufferedClicks[key], let copy = event.copy() {
            if batch.released {
                replay([copy])
                if isUp { bufferedClicks[key] = nil }
            } else {
                bufferedClicks[key]?.events.append(copy)
            }
            return nil
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    private func updateDragTap() {
        guard let dragTap else { return }
        let wanted = !bufferedClicks.isEmpty || lock.withLock { clickGates.values.contains { $0.isSwallowing } }
        guard wanted != dragTapEnabled else { return }
        dragTapEnabled = wanted
        CGEvent.tapEnable(tap: dragTap.port, enable: wanted)
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

    private func deliver(_ action: Gesture, generation session: UInt64) {
        DiagnosticTrace.record("recognized", ["action": action.rawValue])
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lock.withLock({ self.running && self.generation == session }) else {
                return
            }
            self.onAction?(action)
        }
    }
}
