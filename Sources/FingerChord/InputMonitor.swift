import AppKit
import ApplicationServices
import GestureCore
import TouchBridge

struct MonitorSnapshot {
    var contacts: [Contact] = []
    var frames: UInt64 = 0
    var physicalPresses: UInt64 = 0
    var mouseClicks: UInt64 = 0
    var buttonDown = false
    var lastFrame: Double = 0
}

final class InputMonitor {
    static let eventMarker: Int64 = 0x46434F5244
    private let lock = NSLock()
    private var devices: [UInt: DeviceGestureState] = [:]
    private var clickGates: [UInt64: ClickGate] = [:]
    private var senders: Set<UInt64> = []
    private var options = GestureOptions()
    private var snapshot = MonitorSnapshot()
    // Mouse events and MultitouchSupport are delivered independently. Buffer button-down events
    // briefly so either delivery order produces the same result, without blocking the event tap.
    private struct ClickKey: Hashable { let sender: UInt64; let button: Int64 }
    private var bufferedClicks: [ClickKey: [CGEvent]] = [:]
    private var clickGeneration = 0
    private var running = false
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private let hardwareButtons = HardwareButtonMonitor()
    private(set) var deviceCount = 0
    private(set) var error: String?
    var onAction: ((GestureAction) -> Void)?

    var isRunning: Bool { lock.withLock { running } }
    var isEventTapEnabled: Bool { eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    var devicesHealthy: Bool { FCDevicesHealthy() }
    func readSnapshot() -> MonitorSnapshot { lock.withLock { snapshot } }

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
        guard AXIsProcessTrusted() else { error = "请先允许辅助功能权限"; return false }
        guard CGPreflightListenEventAccess() else { error = "请先允许输入监控权限"; return false }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }, userInfo: context) else {
            error = "无法监听系统点击，请在授权后点“重新连接”"
            return false
        }
        eventTap = tap
        eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.withLock { running = true }
        deviceCount = Int(FCStart({ device, data, count, context in
            guard let context, count >= 0 else { return }
            let monitor = Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue()
            DiagnosticTrace.record("raw", ["device": device, "touches": UnsafeBufferPointer(start: data, count: Int(count)).map {
                ["id": Double($0.identifier), "state": Double($0.state), "x": Double($0.x), "y": Double($0.y)]
            }])
            let contacts = UnsafeBufferPointer(start: data, count: Int(count)).compactMap { touch -> Contact? in
                guard (touch.state == 3 || touch.state == 4), touch.x.isFinite, touch.y.isFinite,
                      touch.x >= 0, touch.x <= 1, touch.y >= 0, touch.y <= 1 else { return nil }
                return Contact(id: touch.identifier, x: Double(touch.x), y: Double(touch.y))
            }
            monitor.receiveFrame(device: device, contacts: contacts)
        }, { device, down, context in
            guard let context else { return }
            Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue().receiveButton(device: device, down: down)
        }, context))
        if deviceCount <= 0 {
            let message = String(cString: FCError())
            stop(); error = message; return false
        }
        hardwareButtons.onButton = { [weak self] device, down in self?.receiveButton(device: device, down: down) }
        guard hardwareButtons.start() else {
            stop(); error = "无法监听触摸板物理按钮，请重新连接"; return false
        }
        return true
    }

    func stop() {
        DiagnosticTrace.record("monitorStop")
        lock.withLock { running = false }
        hardwareButtons.stop()
        clickGeneration += 1
        FCStop() // Unregister + drain framework callbacks before releasing their context.
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventSource = nil; eventTap = nil; deviceCount = 0
        for events in bufferedClicks.values { replay(events) }
        bufferedClicks = [:]
        lock.withLock { devices = [:]; clickGates = [:]; senders = []; snapshot.contacts = []; snapshot.buttonDown = false }
    }

    private func receiveFrame(device: UInt, contacts: [Contact]) {
        let now = ProcessInfo.processInfo.systemUptime
        let action: GestureAction? = lock.withLock {
            guard running else { return nil }
            var state = devices[device] ?? DeviceGestureState()
            state.options = options
            let result = state.frame(contacts, at: now)
            DiagnosticTrace.record("frame", ["device": device, "state": state.recognizer.debugState, "physical": result.physicalPress,
                                               "action": result.action?.rawValue ?? "none"])
            let sender = FCSenderID(device)
            if sender != 0 {
                senders.insert(sender)
                if result.physicalPress || result.action == .commandClick {
                    clickGates[sender, default: ClickGate()].physicalPress(result.action, at: now)
                }
            }
            devices[device] = state
            snapshot.frames += 1; snapshot.lastFrame = now
            snapshot.contacts = devices.values.flatMap { $0.recognizer.contacts }
            snapshot.buttonDown = devices.values.contains { $0.recognizer.buttonIsDown }
            return result.action
        }
        if let action { deliver(action) }
    }

    private func receiveButton(device: UInt, down: Bool) {
        DiagnosticTrace.record("button", ["device": device, "down": down])
        lock.withLock {
            guard running else { return }
            // Resolve against the next contact frame to include a fourth finger landing
            // with the press. The fallback below handles a stationary contact stream.
            if devices[device] == nil { devices[device] = DeviceGestureState() }
            devices[device]?.buttonHeader(isDown: down)
            if down { snapshot.physicalPresses += 1 }
            snapshot.buttonDown = devices.values.contains { $0.recognizer.buttonIsDown }
        }
        // A stationary finger or final release may have no following contact frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            self?.resolveButton(device: device)
        }
    }

    private func resolveButton(device: UInt) {
        let now = ProcessInfo.processInfo.systemUptime
        let action: GestureAction? = lock.withLock {
            guard running, var state = devices[device] else { return nil }
            let result = state.resolvePendingButton(at: now)
            devices[device] = state
            if result.physicalPress {
                let sender = FCSenderID(device)
                if sender != 0 { clickGates[sender, default: ClickGate()].physicalPress(result.action, at: now) }
            }
            snapshot.buttonDown = devices.values.contains { $0.recognizer.buttonIsDown }
            return result.action
        }
        if let action { deliver(action) }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DiagnosticTrace.record("tapDisabled", ["type": type.rawValue])
            lock.withLock { clickGates = [:]; for key in Array(devices.keys) { devices[key]?.reset() } }
            if let tap = eventTap, isRunning { CGEvent.tapEnable(tap: tap, enable: true) }
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
        let button: Int64 = (type == .rightMouseDown || type == .rightMouseUp || type == .rightMouseDragged) ? 1 : 0
        let key = ClickKey(sender: sender, button: button)
        let isMouseButtonEvent = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                 .leftMouseDragged, .rightMouseDragged].contains(type)
        if isMouseButtonEvent, bufferedClicks[key] != nil, let copy = event.copy() {
            bufferedClicks[key]?.append(copy)
            return nil
        }
        var deferClick = false
        let swallow: Bool = lock.withLock {
            guard running else { return false }
            switch type {
            case .leftMouseDown, .rightMouseDown:
                snapshot.mouseClicks += 1
                let result = clickGates[sender, default: ClickGate()].mouseDown(button: button, at: now)
                if !result.swallow {
                    // Measured on this Mac: HID switch values arrive up to 54 ms after CG down.
                    // Only delay events from a known trackpad, never an unrelated mouse.
                    deferClick = senders.contains(sender) && (options.middleTap || options.threeFingerPress || options.fourFingerPress)
                }
                return result.swallow
            case .leftMouseUp, .rightMouseUp: return clickGates[sender, default: ClickGate()].mouseUp(button: button)
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
            bufferedClicks[key] = [copy]
            let generation = clickGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, generation == self.clickGeneration else { return }
                self.resolveBufferedClick(key: key)
            }
            return nil
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    // Caller holds the state lock.
    private func cancelTap(sender: UInt64, reason: String) {
        for device in Array(devices.keys) where sender != 0 && FCSenderID(device) == sender {
            devices[device]?.cancelTap()
            DiagnosticTrace.record("cancelTap", ["device": device, "reason": reason])
        }
    }

    private func resolveBufferedClick(key: ClickKey) {
        guard let events = bufferedClicks.removeValue(forKey: key) else { return }
        let swallow = lock.withLock {
            let result = clickGates[key.sender, default: ClickGate()].mouseDown(button: key.button, at: ProcessInfo.processInfo.systemUptime)
            if result.swallow && events.contains(where: { $0.type == .leftMouseUp || $0.type == .rightMouseUp }) {
                _ = clickGates[key.sender]?.mouseUp(button: key.button)
            }
            return result.swallow
        }
        DiagnosticTrace.record("resolvedClick", ["sender": key.sender, "swallow": swallow, "events": events.count])
        if !swallow { replay(events) }
    }

    private func replay(_ events: [CGEvent]) {
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func deliver(_ action: GestureAction) {
        DiagnosticTrace.record("recognized", ["action": action.rawValue])
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.onAction?(action)
        }
    }
}

enum EventEmitter {
    static func send(_ action: GestureAction) -> Bool {
        guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .privateState) else { return false }
        source.userData = InputMonitor.eventMarker
        let events: [CGEvent?]
        if action == .commandClick {
            guard let location = CGEvent(source: nil)?.location else { return false }
            events = [CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left),
                      CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)]
        } else {
            let key: CGKeyCode = action == .closeWindow ? 13 : 12 // ANSI W / Q on this Mac's keyboard.
            events = [CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                      CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)]
        }
        guard events.allSatisfy({ $0 != nil }) else { return false }
        for event in events.compactMap({ $0 }) {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: InputMonitor.eventMarker)
            if action == .commandClick { event.setIntegerValueField(.mouseEventClickState, value: 1) }
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
