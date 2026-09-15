// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FingerChord",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "FingerChord", targets: ["FingerChord"])],
    targets: [
        .target(name: "GestureCore"),
        .target(name: "TouchBridge", linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("IOKit")]),
        .executableTarget(name: "FingerChord", dependencies: ["GestureCore", "TouchBridge"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"])
    ],
    swiftLanguageModes: [.v5]
)
