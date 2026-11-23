// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import GestureCore
import ServiceManagement

/// Only the live preview observes contact updates; the rest of the settings view stays still.
final class TouchFeed: ObservableObject {
    @Published var snapshot = MonitorSnapshot()
    @Published var recognized: Gesture?
    private var fade: DispatchWorkItem?

    func show(_ gesture: Gesture) {
        recognized = gesture
        fade?.cancel()
        let fade = DispatchWorkItem { [weak self] in self?.recognized = nil }
        self.fade = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: fade)
    }
}

final class AppModel: ObservableObject {
    @Published var gestures: Set<Gesture> {
        didSet {
            for gesture in Gesture.allCases { defaults.set(gestures.contains(gesture), forKey: gesture.rawValue) }
            monitor.setEnabled(gestures)
            reconcile()
        }
    }
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "enabled")
            reconcile()
        }
    }
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            L10n.language = language
            reconcile()
            onLanguageChange?()
        }
    }
    var onLanguageChange: (() -> Void)?
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var problem: String?
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var loginError: String?
    let touches = TouchFeed()
    var settingsVisible = false
    var suspended = false
    let monitor = InputMonitor()
    private let defaults: UserDefaults
    private let monitorsInput: Bool
    private var deviceWatcher: DeviceWatcher?
    private var retrying = false

    init(monitorsInput: Bool = true, defaults d: UserDefaults = .standard) {
        defaults = d
        self.monitorsInput = monitorsInput
        language = L10n.language
        var registered: [String: Any] = ["enabled": true]
        for gesture in Gesture.allCases { registered[gesture.rawValue] = true }
        d.register(defaults: registered)
        gestures = Set(Gesture.allCases.filter { d.bool(forKey: $0.rawValue) })
        enabled = d.bool(forKey: "enabled")
        monitor.setEnabled(gestures)
        monitor.onAction = { [weak self] gesture in self?.perform(gesture) }
        guard monitorsInput else { return }
        deviceWatcher = DeviceWatcher { [weak self] in self?.reconnect() }
        reconcile()
    }

    func reconcile() {
        guard monitorsInput else { return }
        let ax = AXIsProcessTrusted()
        let input = CGPreflightListenEventAccess()
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let screenLocked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        if accessibility != ax { accessibility = ax }
        if inputMonitoring != input { inputMonitoring = input }
        let wanted = enabled && !gestures.isEmpty && !suspended && !screenLocked && ax && input
        if !wanted {
            if monitor.isRunning { monitor.stop() }
        } else {
            if monitor.isRunning && (!monitor.devicesHealthy || !monitor.isEventTapEnabled) {
                monitor.stop()
            }
            // A trackpad can still be settling after wake or pairing; retry a failed start once.
            if !monitor.isRunning && !monitor.start() && !retrying {
                retrying = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.reconcile()
                    self?.retrying = false
                }
            }
        }
        let running = monitor.isRunning && monitor.isEventTapEnabled
        let problem = wanted && !running ? L10n.text(monitor.error ?? "status.connecting") : nil
        if self.problem != problem { self.problem = problem }
        refreshLoginStatus()
        DiagnosticTrace.record("status", ["running": running, "ax": ax, "input": input])
    }

    func reconnect() {
        monitor.stop()
        reconcile()
    }

    func showSettings() {
        settingsVisible = true
        monitor.observe { [weak touches] value in
            if touches?.snapshot != value { touches?.snapshot = value }
        }
        reconcile()
    }

    func hideSettings() {
        settingsVisible = false
        monitor.observe(nil)
        touches.snapshot = MonitorSnapshot()
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openPrivacy("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        openPrivacy("Privacy_ListenEvent")
    }

    private func openPrivacy(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        let enabled = status == .enabled || status == .requiresApproval
        let needsApproval = status == .requiresApproval
        if loginEnabled != enabled { loginEnabled = enabled }
        if loginNeedsApproval != needsApproval { loginNeedsApproval = needsApproval }
    }

    func setLoginEnabled(_ value: Bool) {
        loginError = nil
        do {
            if value {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch { loginError = error.localizedDescription }
        refreshLoginStatus()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// While the settings window is in front, gestures are shown instead of sent:
    /// ⌘W and ⌘Q would otherwise close or quit this very window.
    private func perform(_ gesture: Gesture) {
        DiagnosticTrace.record("perform", ["gesture": gesture.rawValue, "settings": settingsVisible])
        HapticFeedback.perform(for: gesture)
        if settingsVisible { touches.show(gesture) }
        if !settingsVisible || !NSApp.isActive { EventEmitter.send(gesture) }
    }

    func shutdown() {
        monitor.observe(nil)
        deviceWatcher = nil
        if monitorsInput { monitor.stop() }
    }

    deinit { shutdown() }
}
