#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "${0:A:h:h}"
# A temporary package lets hosted macOS runners test the platform-independent state machine.
core_package=$(mktemp -d "${TMPDIR:-/tmp}/fingerchord-core.XXXXXX")
trap 'rm -rf "$core_package"' EXIT
mkdir -p "$core_package/Sources" "$core_package/Tests"
cp -R Sources/GestureCore "$core_package/Sources/"
cp -R Tests/GestureCoreTests "$core_package/Tests/"
cat > "$core_package/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "GestureCoreChecks", targets: [
    .target(name: "GestureCore"),
    .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"])
])
SWIFT
swift test --package-path "$core_package"
