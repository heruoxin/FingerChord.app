// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Opt-in, bounded, local-only input diagnostics. No keyboard events or app contents.
/// Start, flush and stop run on the main thread; record may run on a device callback.
enum DiagnosticTrace {
    private static let lock = NSLock()
    private static let writer = DispatchQueue(
        label: "local.FingerChord.diagnosticWriter", qos: .utility)
    private static var entries: [[String: Any]] = []
    private static var until: Double = 0
    private static var generation: UInt64 = 0
    private static var saving = false
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
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in flush() }
    }

    static func record(_ kind: String, _ fields: @autoclosure () -> [String: Any] = [:]) {
        let session: UInt64? = lock.withLock {
            guard ProcessInfo.processInfo.systemUptime < until, entries.count < capacity else { return nil }
            return generation
        }
        guard let session else { return }
        // Fields may read monitor state. Evaluate without the trace lock to avoid
        // inverting the monitor → trace lock order used by hardware callbacks.
        var entry = fields()
        let now = ProcessInfo.processInfo.systemUptime
        entry["event"] = kind
        entry["time"] = now
        lock.withLock {
            guard session == generation, now < until, entries.count < capacity else { return }
            entries.append(entry)
        }
    }

    static func flush() {
        if lock.withLock({ ProcessInfo.processInfo.systemUptime >= until || entries.count >= capacity }) {
            stop()
            return
        }
        let saved: [[String: Any]] = lock.withLock {
            // At most one snapshot is queued, even if the disk is unusually slow.
            guard !saving, !entries.isEmpty else { return [] }
            saving = true
            return entries
        }
        guard !saved.isEmpty else { return }
        writer.async {
            write(saved)
            lock.withLock { saving = false }
        }
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
        // Drain older saves before the final write or a new diagnostic session.
        writer.sync { write(saved) }
    }

    private static func write(_ saved: [[String: Any]]) {
        guard !saved.isEmpty,
            let data = try? JSONSerialization.data(withJSONObject: saved, options: [.sortedKeys])
        else { return }
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: outputURL, options: [.atomic])
    }
}
