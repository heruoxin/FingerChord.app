import AppKit
import TouchBridge

if CommandLine.arguments.contains("--probe") {
    let count = FCStart({ _, _, _, _ in }, { _, _, _ in }, nil)
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Trackpads: \(count); \(String(cString: FCError()))")
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
    FCStop()
    exit(count > 0 ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
