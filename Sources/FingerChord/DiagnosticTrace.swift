// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Opt-in, bounded, local-only input diagnostics. No keyboard events or app contents.
/// Start and stop run on the main thread; record may run on a device callback.
enum DiagnosticTrace {
    private static let lock = NSLock()
    private static var entries: [[String: Any]] = []
    private static var until: Double = 0
    private static var generation: UInt64 = 0
    private static var timer: Timer?
    static let capacity = 10000
    static var bufferedEntryCount: Int { lock.withLock { entries.count } }
    static var outputURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FingerChord/diagnostic.json")
    }

    static func start() {
        stop()
        lock.withLock { until = ProcessInfo.processInfo.systemUptime + 180 }
        record("begin", ["pid": ProcessInfo.processInfo.processIdentifier])
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { _ in stop() }
    }

    static func record(_ kind: String, _ fields: @autoclosure () -> [String: Any] = [:]) {
        let session: UInt64? = lock.withLock { ProcessInfo.processInfo.systemUptime < until ? generation : nil }
        guard let session else { return }
        // Fields may read monitor state. Evaluate without the trace lock to avoid
        // inverting the monitor → trace lock order used by hardware callbacks.
        var entry = fields()
        entry["event"] = kind
        entry["time"] = ProcessInfo.processInfo.systemUptime
        let filled: Bool = lock.withLock {
            guard session == generation, entries.count < capacity else { return false }
            entries.append(entry)
            return entries.count == capacity
        }
        if filled { DispatchQueue.main.async { if lock.withLock({ session == generation }) { stop() } } }
    }

    static func stop() {
        timer?.invalidate()
        timer = nil
        let saved: [[String: Any]] = lock.withLock {
            until = 0
            generation &+= 1
            let saved = entries
            entries = []
            return saved
        }
        guard !saved.isEmpty,
            let data = try? JSONSerialization.data(withJSONObject: saved, options: [.sortedKeys])
        else { return }
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: outputURL, options: [.atomic])
    }
}
