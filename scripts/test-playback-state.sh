#!/usr/bin/env bash
# Runs the audio-session policy tests without an iOS SDK.
set -euo pipefail
cd "$(dirname "$0")/.."

package=$(mktemp -d)
trap 'rm -rf "$package"' EXIT
mkdir -p "$package/Sources/Klassik" "$package/Tests/KlassikTests"
cp Klassik/PlaybackState.swift "$package/Sources/Klassik/"
cp KlassikTests/PlaybackStateTests.swift "$package/Tests/KlassikTests/"
cat > "$package/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KlassikPlaybackState",
    targets: [
        .target(name: "Klassik"),
        .testTarget(name: "KlassikTests", dependencies: ["Klassik"]),
    ]
)
SWIFT
swift test --package-path "$package"
