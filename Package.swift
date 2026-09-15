// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-only
import PackageDescription

let package = Package(
    name: "FingerChord",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "FingerChord", targets: ["FingerChord"])],
    targets: [
        .target(name: "GestureCore"),
        .target(
            name: "TouchBridge",
            linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("IOKit")]),
        .executableTarget(
            name: "FingerChord", dependencies: ["GestureCore", "TouchBridge"],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"]),
        .testTarget(name: "FingerChordTests", dependencies: ["FingerChord"]),
    ],
    swiftLanguageModes: [.v5]
)
