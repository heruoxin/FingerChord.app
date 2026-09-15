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
    private var recognizers: [UInt: GestureRecognizer] = [:]
    private var clickGate = ClickGate()
    private var options = GestureOptions()
    private var snapshot = MonitorSnapshot()
    private var running = false
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private(set) var deviceCount = 0
    private(set) var error: String?
    var onAction: ((GestureAction) -> Void)?

    var isRunning: Bool { lock.withLock { running } }
    var isEventTapEnabled: Bool { eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    func readSnapshot() -> MonitorSnapshot { lock.withLock { snapshot } }

    func setOptions(_ value: GestureOptions) {
        lock.withLock {
            options = value
            for key in Array(recognizers.keys) { recognizers[key]?.options = value }
            clickGate.cancelPending()
        }
    }

    @discardableResult func start() -> Bool {
        if isRunning { return true }
        error = nil
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
        return true
    }

    func stop() {
        lock.withLock { running = false }
        FCStop() // Unregister + drain framework callbacks before releasing their context.
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventSource = nil; eventTap = nil; deviceCount = 0
        lock.withLock { recognizers = [:]; clickGate.reset(); snapshot.contacts = []; snapshot.buttonDown = false }
    }

    private func receiveFrame(device: UInt, contacts: [Contact]) {
        let now = ProcessInfo.processInfo.systemUptime
        let action: GestureAction? = lock.withLock {
            guard running else { return nil }
            var recognizer = recognizers[device] ?? GestureRecognizer()
            recognizer.options = options
            let action = recognizer.update(contacts, at: now)
            recognizers[device] = recognizer
            snapshot.frames += 1; snapshot.lastFrame = now
            snapshot.contacts = recognizers.values.flatMap(\.contacts)
            return action
        }
        if let action { deliver(action) }
    }

    private func receiveButton(device: UInt, down: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            guard running else { return }
            var recognizer = recognizers[device] ?? GestureRecognizer()
            recognizer.options = options
            let action = recognizer.buttonChanged(isDown: down, at: now)
            recognizers[device] = recognizer
            snapshot.buttonDown = recognizers.values.contains { $0.buttonIsDown }
            if down { snapshot.physicalPresses += 1; clickGate.physicalPress(action, at: now) }
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.withLock { clickGate.reset(); for key in Array(recognizers.keys) { recognizers[key]?.reset() } }
            if let tap = eventTap, isRunning { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.eventMarker {
            return Unmanaged.passUnretained(event)
        }
        let now = ProcessInfo.processInfo.systemUptime
        let button: Int64 = (type == .rightMouseDown || type == .rightMouseUp || type == .rightMouseDragged) ? 1 : 0
        var action: GestureAction?
        let swallow: Bool = lock.withLock {
            guard running else { return false }
            switch type {
            case .leftMouseDown, .rightMouseDown:
                snapshot.mouseClicks += 1
                let result = clickGate.mouseDown(button: button, at: now)
                action = result.action
                return result.swallow
            case .leftMouseUp, .rightMouseUp: return clickGate.mouseUp(button: button)
            case .leftMouseDragged, .rightMouseDragged: return clickGate.shouldSwallowDrag(button: button)
            case .scrollWheel:
                for key in Array(recognizers.keys) { recognizers[key]?.cancelTap() }
                return false
            default: return false
            }
        }
        if let action { deliver(action) }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    private func deliver(_ action: GestureAction) {
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
            let key: CGKeyCode = action == .closeWindow ? 13 : 12 // ANSI W / Q; remapped below for keyboard layouts.
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
