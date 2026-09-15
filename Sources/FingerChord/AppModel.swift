// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import Combine
import GestureCore
import ServiceManagement

final class AppModel: ObservableObject {
    @Published var middleTap: Bool {
        didSet {
            defaults.set(middleTap, forKey: "middleTap")
            updateOptions()
        }
    }
    @Published var threePress: Bool {
        didSet {
            defaults.set(threePress, forKey: "threePress")
            updateOptions()
        }
    }
    @Published var fourPress: Bool {
        didSet {
            defaults.set(fourPress, forKey: "fourPress")
            updateOptions()
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
            refreshActionText()
            reconcile()
            onLanguageChange?()
        }
    }
    var onLanguageChange: (() -> Void)?
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var running = false
    @Published var statusText = L10n.text("status.connecting")
    @Published var deviceCount = 0
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var loginError: String?
    @Published var testMode = false
    @Published var snapshot = MonitorSnapshot()
    @Published var lastAction = L10n.text("result.waiting")
    @Published var actionCount = 0
    var settingsVisible = false
    var suspended = false
    let monitor = InputMonitor()
    private let defaults: UserDefaults
    private let monitorsInput: Bool
    private var lastGesture: GestureAction?
    private var actionResult = "result.waiting"
    private var statusTimer: Timer?
    private var previewTimer: Timer?

    init(monitorsInput: Bool = true, defaults d: UserDefaults = .standard) {
        defaults = d
        self.monitorsInput = monitorsInput
        language = L10n.language
        d.register(defaults: [
            "middleTap": true, "threePress": true, "fourPress": true, "enabled": true,
        ])
        middleTap = d.bool(forKey: "middleTap")
        threePress = d.bool(forKey: "threePress")
        fourPress = d.bool(forKey: "fourPress")
        enabled = d.bool(forKey: "enabled")
        updateOptions()
        monitor.onAction = { [weak self] action in self?.perform(action) }
        guard monitorsInput else { return }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.reconcile()
        }
        reconcile()
    }

    func updateOptions() {
        var options = GestureOptions()
        options.middleTap = middleTap
        options.threeFingerPress = threePress
        options.fourFingerPress = fourPress
        monitor.setOptions(options)
    }

    func reconcile() {
        guard monitorsInput else { return }
        let ax = AXIsProcessTrusted()
        let input = CGPreflightListenEventAccess()
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let screenLocked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        if accessibility != ax { accessibility = ax }
        if inputMonitoring != input { inputMonitoring = input }
        if !enabled || suspended || screenLocked || !ax || !input {
            if monitor.isRunning { monitor.stop() }
        } else {
            if monitor.isRunning && (!monitor.devicesHealthy || !monitor.isEventTapEnabled) {
                monitor.stop()
            }
            if !monitor.isRunning { monitor.start() }
        }
        running = monitor.isRunning && monitor.isEventTapEnabled
        deviceCount = monitor.deviceCount
        if !enabled {
            statusText = L10n.text("status.paused")
        } else if !ax || !input {
            statusText = L10n.text("status.permissions")
        } else if suspended || screenLocked {
            statusText = L10n.text("status.waiting")
        } else if running {
            statusText = L10n.text("status.running")
        } else {
            statusText = L10n.text(monitor.error ?? "status.recovering")
        }
        refreshLoginStatus()
        DiagnosticTrace.record(
            "status",
            [
                "running": running, "ax": ax, "input": input, "devices": deviceCount,
                "frames": monitor.readSnapshot().frames, "status": statusText,
            ])
    }

    func reconnect() {
        monitor.stop()
        reconcile()
    }

    func showSettings() {
        settingsVisible = true
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self else { return }
            var value = self.monitor.readSnapshot()
            if ProcessInfo.processInfo.systemUptime - value.lastFrame > 0.3 { value.contacts = [] }
            self.snapshot = value
        }
        reconcile()
    }

    func hideSettings() {
        settingsVisible = false
        testMode = false
        previewTimer?.invalidate()
        previewTimer = nil
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
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

    private func perform(_ action: GestureAction) {
        DiagnosticTrace.record(
            "perform",
            [
                "action": action.rawValue, "running": running, "enabled": enabled,
                "suspended": suspended, "test": testMode && settingsVisible,
            ])
        guard running, enabled, !suspended else { return }
        if action == .commandClick && !middleTap { return }
        if action == .closeWindow && !threePress { return }
        if action == .quitApplication && !fourPress { return }
        HapticFeedback.perform()
        lastGesture = action
        if testMode && settingsVisible {
            actionResult = "result.recognized"
        } else if EventEmitter.send(action) {
            actionResult = "result.sent"
        } else {
            actionResult = "result.failed"
            refreshActionText()
            reconcile()
            return
        }
        refreshActionText()
        actionCount += 1
    }

    private func refreshActionText() {
        let name: String
        switch lastGesture {
        case .commandClick: name = L10n.text("result.click")
        case .closeWindow: name = L10n.text("result.close")
        case .quitApplication: name = L10n.text("result.quit")
        case nil: name = ""
        }
        lastAction = L10n.text(actionResult, name)
    }

    func shutdown() {
        previewTimer?.invalidate()
        previewTimer = nil
        statusTimer?.invalidate()
        statusTimer = nil
        if monitorsInput { monitor.stop() }
    }

    deinit { shutdown() }
}
