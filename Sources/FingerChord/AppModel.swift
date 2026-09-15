import AppKit
import ApplicationServices
import Combine
import GestureCore
import ServiceManagement

final class AppModel: ObservableObject {
    @Published var middleTap: Bool { didSet { defaults.set(middleTap, forKey: "middleTap"); updateOptions() } }
    @Published var threePress: Bool { didSet { defaults.set(threePress, forKey: "threePress"); updateOptions() } }
    @Published var fourPress: Bool { didSet { defaults.set(fourPress, forKey: "fourPress"); updateOptions() } }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled"); reconcile() } }
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var running = false
    @Published var statusText = "正在连接触摸板…"
    @Published var deviceCount = 0
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var loginError: String?
    @Published var testMode = false
    @Published var snapshot = MonitorSnapshot()
    @Published var lastAction = "等待手势"
    @Published var actionCount = 0
    var settingsVisible = false
    var suspended = false
    let monitor = InputMonitor()
    private let defaults = UserDefaults.standard
    private var statusTimer: Timer?
    private var previewTimer: Timer?

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["middleTap": true, "threePress": true, "fourPress": true, "enabled": true])
        middleTap = d.bool(forKey: "middleTap")
        threePress = d.bool(forKey: "threePress")
        fourPress = d.bool(forKey: "fourPress")
        enabled = d.bool(forKey: "enabled")
        updateOptions()
        monitor.onAction = { [weak self] action in self?.perform(action) }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile() }
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
        let ax = AXIsProcessTrusted(), input = CGPreflightListenEventAccess()
        if accessibility != ax { accessibility = ax }
        if inputMonitoring != input { inputMonitoring = input }
        if !enabled || suspended || !ax || !input {
            if monitor.isRunning { monitor.stop() }
        } else if !monitor.isRunning { monitor.start() }
        running = monitor.isRunning && monitor.isEventTapEnabled
        deviceCount = monitor.deviceCount
        if !enabled { statusText = "已暂停" }
        else if !ax || !input { statusText = "需要系统授权" }
        else if suspended { statusText = "等待会话恢复" }
        else if running { statusText = "正在后台运行" }
        else { statusText = monitor.error ?? "正在恢复监听…" }
        refreshLoginStatus()
    }

    func reconnect() { monitor.stop(); reconcile() }

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
        previewTimer?.invalidate(); previewTimer = nil
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
        loginEnabled = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func setLoginEnabled(_ value: Bool) {
        loginError = nil
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { loginError = error.localizedDescription }
        refreshLoginStatus()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func perform(_ action: GestureAction) {
        guard running, enabled, !suspended else { return }
        if action == .commandClick && !middleTap { return }
        if action == .closeWindow && !threePress { return }
        if action == .quitApplication && !fourPress { return }
        let name: String
        switch action {
        case .commandClick: name = "⌘ + 点击"
        case .closeWindow: name = "⌘W · 关闭窗口"
        case .quitApplication: name = "⌘Q · 退出 App"
        }
        if testMode && settingsVisible {
            lastAction = "已识别 \(name)"
        } else if EventEmitter.send(action) {
            lastAction = "已发送 \(name)"
        } else {
            lastAction = "发送失败，请检查辅助功能权限"
            reconcile()
            return
        }
        actionCount += 1
    }

    func shutdown() {
        previewTimer?.invalidate(); statusTimer?.invalidate()
        monitor.stop()
    }
}
