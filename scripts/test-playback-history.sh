#!/usr/bin/env bash
# Runs listening-data rules and the server adapter without an iOS SDK.
set -euo pipefail
cd "$(dirname "$0")/.."

package=$(mktemp -d)
trap 'rm -rf "$package"' EXIT
mkdir -p "$package/Sources/Klassik" "$package/Tests/KlassikTests"
for source in PlaybackHistory QueueItem ServerPort SubsonicClient WorkIndex ClassicalFilter PlaybackEngine; do
  cp "Klassik/$source.swift" "$package/Sources/Klassik/"
done
for source in PlaybackHistoryTests PlaybackHistoryFixtureTests PlaybackFakes SubsonicClientTests; do
  cp "KlassikTests/$source.swift" "$package/Tests/KlassikTests/"
done
cat > "$package/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KlassikPlaybackHistory",
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")],
    targets: [
        .target(name: "Klassik", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(name: "KlassikTests", dependencies: ["Klassik"]),
    ]
)
SWIFT
swift test --jobs 4 --package-path "$package" --scratch-path "$PWD/.scratch/playback-history-build"
