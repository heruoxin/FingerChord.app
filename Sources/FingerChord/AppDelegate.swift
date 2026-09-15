// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var window: NSWindow?
    private var layoutSubscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var instanceLock: Int32 = -1
    private let reopenName = Notification.Name("local.FingerChord.showSettings")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard acquireInstanceLock() else {
            DistributedNotificationCenter.default().postNotificationName(
                reopenName, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        installMenu()
        if CommandLine.arguments.contains("--self-test-lifecycle") {
            DispatchQueue.main.async {
                _ = Diagnostics.testLifecycle()
                if CommandLine.arguments.contains("--hold-for-leaks") {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 45))
                }
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--diagnose") { DiagnosticTrace.start() }
        model = AppModel()
        layoutSubscription = Publishers.CombineLatest4(
            model.$accessibility, model.$inputMonitoring,
            model.$loginNeedsApproval, model.$loginError
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.window?.setContentSize(NSSize(width: 680, height: SettingsView.windowHeight(self.model)))
        }
        model.onLanguageChange = { [weak self] in
            self?.installMenu()
            self?.window?.title = L10n.text("window.title")
        }
        if CommandLine.arguments.contains("--diagnose") { model.testMode = true }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showSettings), name: reopenName, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(beginDiagnostics),
            name: Notification.Name("local.FingerChord.beginDiagnostics"), object: nil)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.model.suspended = true
                    self?.model.reconcile()
                })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self?.model.suspended = false
                        self?.model.reconnect()
                    }
                })
        }
        let launched = UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if !launched || CommandLine.arguments.contains("--settings") || !model.accessibility
            || !model.inputMonitoring
        {
            showSettings()
        }
        if CommandLine.arguments.contains("--diagnose") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.model.monitor.stop()
                let result = Diagnostics.testEvents()
                DiagnosticTrace.record("eventSelfTest", ["passed": result == 0])
                self.model.reconcile()
            }
        }
    }

    @objc func showSettings() {
        guard model != nil else { return }
        if window == nil {
            let view = SettingsView(
                model: model, hide: { [weak self] in self?.window?.close() }, quit: { NSApp.terminate(nil) }
            )
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = L10n.text("window.title")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.setContentSize(controller.view.fittingSize)
            window.center()
            self.window = window
        }
        model.showSettings()
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func beginDiagnostics() { DiagnosticTrace.start() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillClose(_ notification: Notification) { model.hideSettings() }
    func applicationWillTerminate(_ notification: Notification) {
        layoutSubscription = nil
        model?.shutdown()
        DiagnosticTrace.stop()
        DistributedNotificationCenter.default().removeObserver(self)
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if instanceLock >= 0 { close(instanceLock) }
    }

    private func acquireInstanceLock() -> Bool {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FingerChord")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch { return false }
        instanceLock = open(
            folder.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard instanceLock >= 0 else { return false }
        guard flock(instanceLock, LOCK_EX | LOCK_NB) == 0 else {
            close(instanceLock)
            instanceLock = -1
            return false
        }
        return true
    }

    private func installMenu() {
        let menu = NSMenu()
        let root = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: L10n.text("menu.settings"), action: #selector(showSettings), keyEquivalent: ","
        ).target = self
        appMenu.addItem(
            withTitle: L10n.text("menu.close"), action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: L10n.text("action.quit"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        root.submenu = appMenu
        menu.addItem(root)
        NSApp.mainMenu = menu
    }
}
