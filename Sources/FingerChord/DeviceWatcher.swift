// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit

/// Multitouch devices appear after login, pairing or wake and disappear on disconnect.
/// Each edge reports a change, so device health never needs polling.
final class DeviceWatcher {
    private let port = IONotificationPortCreate(kIOMainPortDefault)
    private var iterators: [io_iterator_t] = []
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"),
                { context, iterator in
                    DeviceWatcher.drain(iterator)
                    Unmanaged<DeviceWatcher>.fromOpaque(context!).takeUnretainedValue().onChange()
                }, context, &iterator)
            // Draining arms the notification; devices present at launch are not changes.
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    deinit {
        for iterator in iterators { IOObjectRelease(iterator) }
        IONotificationPortDestroy(port)
    }

    private static func drain(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}
