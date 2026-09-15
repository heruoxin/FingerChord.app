// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import GestureCore
import ServiceManagement
import SwiftUI
import TouchBridge

enum Diagnostics {
    static var observed: [(CGEventType, CGEventFlags, Int64)] = []
    static var rawFrameCount = 0
    static var buttonCount = 0
    static let counterLock = NSLock()

    static func probe() -> Int32 {
        let seconds: Double = CommandLine.arguments.contains("--observe") ? 15 : 1
        let count = FCStart(
            { _, _, _, _ in Diagnostics.counterLock.withLock { Diagnostics.rawFrameCount += 1 } },
            { _, _, _ in Diagnostics.counterLock.withLock { Diagnostics.buttonCount += 1 } }, nil)
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print(
            "Accessibility: \(AXIsProcessTrusted()); Input monitoring: \(CGPreflightListenEventAccess())")
        print("Trackpads: \(count); Healthy: \(FCDevicesHealthy()); \(String(cString: FCError()))")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
        FCStop()
        print("Observed frames: \(rawFrameCount); button transitions: \(buttonCount)")
        return count > 0 ? 0 : 1
    }

    /// Tests our real event emitter while absorbing every tagged test event before applications.
    static func testEvents() -> Int32 {
        observed = []
        guard AXIsProcessTrusted() else {
            print("Event self-test requires Accessibility")
            return 1
        }
        guard CGPreflightListenEventAccess() else {
            print("Event self-test requires Input Monitoring and an unlocked Mac; no events sent")
            return 1
        }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        guard session?["CGSSessionScreenIsLocked"] as? Bool != true else {
            print("Unlock the Mac before event self-test; no events sent")
            return 1
        }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, _ in
                    guard event.getIntegerValueField(.eventSourceUserData) == InputMonitor.eventMarker else {
                        return Unmanaged.passUnretained(event)
                    }
                    let detail = event.getIntegerValueField(
                        type == .keyDown || type == .keyUp ? .keyboardEventKeycode : .mouseEventClickState)
                    Diagnostics.observed.append((type, event.flags, detail))
                    return nil
                }, userInfo: nil), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        else {
            print("Cannot install absorbing event tap; no events sent")
            return 1
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        _ = EventEmitter.send(.commandClick)
        _ = EventEmitter.send(.commandClick)
        _ = EventEmitter.send(.commandClick)
        _ = EventEmitter.send(.closeWindow)
        _ = EventEmitter.send(.quitApplication)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(tap)
        let expected: [(CGEventType, Int64)] = [
            (.leftMouseDown, 1), (.leftMouseUp, 1),
            (.leftMouseDown, 1), (.leftMouseUp, 1),
            (.leftMouseDown, 1), (.leftMouseUp, 1),
            (.keyDown, 13), (.keyUp, 13), (.keyDown, 12), (.keyUp, 12),
        ]
        let valid =
            observed.count == expected.count
            && zip(observed, expected).allSatisfy {
                $0.0.0 == $0.1.0 && $0.0.1.contains(.maskCommand) && $0.0.2 == $0.1.1
            }
        print(
            "Event self-test: \(valid ? "PASS" : "FAIL"), \(observed.count)/\(expected.count) events, all intercepted before apps"
        )
        for value in observed {
            print("type=\(value.0.rawValue) flags=\(value.1.rawValue) detail=\(value.2)")
        }
        return valid ? 0 : 1
    }

    /// Exercise actual framework/tap/HID ownership, then hold the process for Instruments/leaks.
    /// Run as the only app instance; all recognizer actions are disabled during this test.
    static func testLifecycle() -> Bool {
        var started = 0
        var released = 0
        var traceReleased = true
        let rounds = 100
        var failures: [String] = []
        for _ in 0..<rounds {
            weak var reference: InputMonitor?
            autoreleasepool {
                let monitor = InputMonitor()
                reference = monitor
                var options = GestureOptions()
                options.middleTap = false
                options.threeFingerPress = false
                options.fourFingerPress = false
                monitor.setOptions(options)
                if monitor.start(), monitor.isEventTapEnabled, monitor.devicesHealthy {
                    started += 1
                } else {
                    failures.append(monitor.error ?? "Device/tap health check failed")
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.025))
                monitor.stop()
            }
            if reference == nil { released += 1 }
        }
        for _ in 0..<10 {
            autoreleasepool {
                DiagnosticTrace.start()
                for i in 0..<(DiagnosticTrace.capacity + 100) { DiagnosticTrace.record("capacityTest", ["index": i]) }
                traceReleased = traceReleased && DiagnosticTrace.bufferedEntryCount == DiagnosticTrace.capacity
                DiagnosticTrace.stop()
                traceReleased = traceReleased && DiagnosticTrace.bufferedEntryCount == 0
            }
        }
        let eventsPassed = testEvents() == 0
        let passed = started == rounds && released == rounds && traceReleased && eventsPassed
        let report: [String: Any] = [
            "passed": passed, "rounds": rounds, "started": started, "released": released,
            "traceReleased": traceReleased, "eventSelfTest": eventsPassed, "failures": failures,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "pid": ProcessInfo.processInfo.processIdentifier,
        ]
        let url = DiagnosticTrace.outputURL.deletingLastPathComponent().appendingPathComponent("lifecycle-test.json")
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            print("Lifecycle self-test: \(passed ? "PASS" : "FAIL"). Report: \(url.path)")
        } catch {
            print(error)
            return false
        }
        return passed
    }

    static func renderSettings(to path: String) -> Int32 {
        _ = NSApplication.shared
        if let i = CommandLine.arguments.firstIndex(of: "--language"),
            CommandLine.arguments.count > i + 1,
            let language = AppLanguage(rawValue: CommandLine.arguments[i + 1])
        {
            L10n.language = language
        }
        let model = AppModel(monitorsInput: false)
        let permissions = CommandLine.arguments.contains("--permissions")
        model.accessibility = !permissions
        model.inputMonitoring = !permissions
        model.running = !permissions
        model.statusText = L10n.text(permissions ? "status.permissions" : "status.running")
        model.loginEnabled = false
        NSApp.appearance = NSAppearance(
            named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        if let iconURL = Bundle.main.url(forResource: "FingerChord", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: iconURL)
        }
        let view = NSHostingView(rootView: SettingsView(model: model, hide: {}, quit: {}))
        view.frame = CGRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer {
            window.contentView = nil
            window.close()
        }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 1 }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return 1 }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("Rendered settings \(Int(view.frame.width))×\(Int(view.frame.height)) to \(path)")
        } catch {
            print(error)
            return 1
        }
        model.shutdown()
        return 0
    }

    static func testLoginService() -> Int32 {
        let service = SMAppService.mainApp
        guard service.status == .notRegistered || service.status == .notFound else {
            print(
                "Login self-test skipped: existing user login preference is preserved (status \(service.status.rawValue))"
            )
            return 1
        }
        do {
            try service.register()
            let registered = service.status
            try service.unregister()
            let removed = service.status
            let valid =
                (registered == .enabled || registered == .requiresApproval)
                && (removed == .notRegistered || removed == .notFound)
            print(
                "Login self-test: \(valid ? "PASS" : "FAIL"); registered=\(registered.rawValue), restored=\(removed.rawValue)"
            )
            return valid ? 0 : 1
        } catch {
            try? service.unregister()
            print(
                "Login self-test failed: \(error.localizedDescription); restored status=\(service.status.rawValue)"
            )
            return 1
        }
    }
}
