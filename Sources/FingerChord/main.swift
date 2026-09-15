import AppKit
import TouchBridge

if CommandLine.arguments.contains("--probe") {
    exit(Diagnostics.probe())
}
if CommandLine.arguments.contains("--self-test-events") {
    exit(Diagnostics.testEvents())
}
if CommandLine.arguments.contains("--self-test-login") {
    exit(Diagnostics.testLoginService())
}
if let index = CommandLine.arguments.firstIndex(of: "--render-settings"), CommandLine.arguments.count > index + 1 {
    exit(Diagnostics.renderSettings(to: CommandLine.arguments[index + 1]))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
