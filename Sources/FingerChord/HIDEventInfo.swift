// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import Darwin
import Foundation

enum HIDEventInfo {
    private static let cg = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    private static let io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private static let copyEvent: (@convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?)? = symbol(
        cg, "CGEventCopyIOHIDEvent")
    private static let getSender: (@convention(c) (CFTypeRef) -> UInt64)? = symbol(
        io, "IOHIDEventGetSenderID")

    private static func symbol<T>(_ library: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let library, let pointer = dlsym(library, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static func senderID(_ event: CGEvent) -> UInt64 {
        guard let copyEvent, let raw = copyEvent(event)?.takeRetainedValue() else { return 0 }
        return getSender?(raw) ?? 0
    }
}
