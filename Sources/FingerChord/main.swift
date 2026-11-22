// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import TouchBridge

if CommandLine.arguments.contains("--start-diagnostics") {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("local.FingerChord.beginDiagnostics"), object: nil, userInfo: nil,
        deliverImmediately: true)
    print(DiagnosticTrace.outputURL.path)
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--relaunch-after") {
    // Wait for the closing instance to exit, then start an ordinary background launch.
    let queue = kqueue()
    var quit = kevent(
        ident: UInt(CommandLine.arguments[index + 1])!, filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD),
        fflags: NOTE_EXIT, data: 0, udata: nil)
    var event = kevent()
    kevent(queue, &quit, 1, &event, 1, nil)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.arguments = ["--relaunch"]
    let launched = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
        launched.signal()
    }
    launched.wait()
    exit(0)
}

if CommandLine.arguments.contains("--probe") {
    exit(Diagnostics.probe())
}
if CommandLine.arguments.contains("--self-test-events") {
    exit(Diagnostics.testEvents())
}
if CommandLine.arguments.contains("--self-test-login") {
    exit(Diagnostics.testLoginService())
}
if let index = CommandLine.arguments.firstIndex(of: "--render-settings"),
    CommandLine.arguments.count > index + 1
{
    exit(Diagnostics.renderSettings(to: CommandLine.arguments[index + 1]))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
