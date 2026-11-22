// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private let reopenName = Notification.Name("local.FingerChord.showSettings")
    private let relaunched = CommandLine.arguments.contains("--relaunch")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FingerChord")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Held until exit.
        let lock = open(folder.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
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
        model.onLanguageChange = { [weak self] in
            self?.installMenu()
            self?.window?.title = L10n.text("app.name")
        }
        // Inactive apps hold distributed notifications by default; this app is almost always inactive.
        for (selector, name) in [
            (#selector(showSettings), reopenName),
            (#selector(beginDiagnostics), Notification.Name("local.FingerChord.beginDiagnostics")),
            (#selector(reconcile), Notification.Name("com.apple.screenIsLocked")),
            (#selector(reconcile), Notification.Name("com.apple.screenIsUnlocked")),
        ] {
            DistributedNotificationCenter.default().addObserver(
                self, selector: selector, name: name, object: nil, suspensionBehavior: .deliverImmediately)
        }
        let center = NSWorkspace.shared.notificationCenter
        // Permissions and login items change in System Settings; leaving it is the moment to recheck.
        observers.append(
            center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) {
                [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier == "com.apple.systempreferences" { self?.model.reconcile() }
            })
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
        if !relaunched
            && (!launched || CommandLine.arguments.contains("--settings") || !model.accessibility
                || !model.inputMonitoring || CommandLine.arguments.contains("--diagnose"))
        {
            showSettings()
        }
    }

    @objc func showSettings() {
        guard model != nil else { return }
        if window == nil {
            let controller = NSHostingController(
                rootView: SettingsView(
                    model: model, hide: { [weak self] in self?.window?.performClose(nil) },
                    quit: { NSApp.terminate(nil) }))
            controller.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: controller)
            window.title = L10n.text("app.name")
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.center()
            self.window = window
        }
        model.showSettings()
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func beginDiagnostics() { DiagnosticTrace.start() }
    @objc private func reconcile() { model.reconcile() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// SwiftUI keeps megabytes of caches after its window closes. A helper starts a fresh
    /// background instance once this one has quit, so the resident process never holds them.
    /// Only a close the user asks for gets here; quitting and logging out close windows without asking.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let helper = Process()
        helper.executableURL = Bundle.main.executableURL
        helper.arguments = ["--relaunch-after", String(getpid())]
        if (try? helper.run()) != nil { DispatchQueue.main.async { NSApp.terminate(nil) } }
        return true
    }

    func windowWillClose(_ notification: Notification) { model.hideSettings() }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        DiagnosticTrace.stop()
        DistributedNotificationCenter.default().removeObserver(self)
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
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
            withTitle: L10n.text("quit"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        root.submenu = appMenu
        menu.addItem(root)
        NSApp.mainMenu = menu
    }
}
