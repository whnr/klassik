#!/usr/bin/env bash
# Runs listening-data rules and the server adapter without an iOS SDK.
set -euo pipefail
cd "$(dirname "$0")/.."

package=$(mktemp -d)
trap 'rm -rf "$package"' EXIT
mkdir -p "$package/Sources/Klassik" "$package/Sources/KlassikEngine" "$package/Tests/KlassikTests"
for source in PlaybackHistory ServerTrouble QueueItem ServerPort SubsonicClient WorkIndex Roles ClassicalFilter; do
  cp "Klassik/$source.swift" "$package/Sources/Klassik/"
done
# The engine files that the fake engine and the transfer need. The AVFoundation files stay out.
for source in PlaybackEngine PlaybackTrack TrackTransfer PartialAudioFile AudioStorageBudget; do
  cp "KlassikEngine/$source.swift" "$package/Sources/KlassikEngine/"
done
for source in PlaybackHistoryTests PlaybackHistoryFixtureTests PlaybackFakes SubsonicClientTests; do
  cp "KlassikTests/$source.swift" "$package/Tests/KlassikTests/"
done
# Linux Foundation lacks ListFormatter. Listening-data tests do not check display text.
cat > "$package/Sources/Klassik/ListFormatter.swift" <<'SWIFT'
#if os(Linux)
import Foundation

final class ListFormatter {
    var locale = Locale.current
    func string(from names: [String]) -> String? { names.joined(separator: " ") }
}
#endif
SWIFT
# The app's mapping file needs the track store, which this package leaves out. The fake engine needs only the mapping.
cat > "$package/Sources/Klassik/PlaybackTrackMapping.swift" <<'SWIFT'
import KlassikEngine

extension Song {
    var playbackTrack: PlaybackTrack {
        PlaybackTrack(
            id: id, duration: duration, suffix: suffix, bitRate: bitRate, samplingRate: samplingRate,
            bitDepth: bitDepth, channelCount: channelCount, replayGain: nil)
    }
}
SWIFT
cat > "$package/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KlassikPlaybackHistory",
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")],
    targets: [
        .target(name: "KlassikEngine"),
        .target(
            name: "Klassik",
            dependencies: ["KlassikEngine", .product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(name: "KlassikTests", dependencies: ["Klassik", "KlassikEngine"]),
    ]
)
SWIFT
swift test --jobs 4 --package-path "$package" --scratch-path "$PWD/.scratch/playback-history-build"
