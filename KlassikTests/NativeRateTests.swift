import AVFoundation
import Synchronization
import Testing

@testable import KlassikEngine

/// Native-rate playback (ADR 0060): each track plays at its own sample rate and channel count, and the engine
/// never converts. The tracks are local WAV files and the engine renders offline, so the output does not depend on
/// a server or on runner load.
@Suite(.serialized)
struct NativeRateTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "native-rate-\(UUID().uuidString)")

    /// The samples that the tap saw: one array for each channel, and the rate of the first block.
    private final class Tap: Sendable {
        private struct State {
            var channels: [[Float]] = []
            var rate = 0.0
        }
        private let state = Mutex(State())
        var rate: Double { state.withLock { $0.rate } }
        var channelCount: Int { state.withLock { $0.channels.count } }

        func channel(_ index: Int) -> [Float] {
            state.withLock { $0.channels.indices.contains(index) ? $0.channels[index] : [] }
        }

        func record(_ buffer: AVReadOnlyAudioPCMBuffer) {
            guard buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved else { return }
            let frames = Int(buffer.frameLength)
            buffer.withUnsafeAudioBufferList { list in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
                state.withLock { state in
                    if state.channels.isEmpty {
                        state.channels = Array(repeating: [], count: buffers.count)
                        state.rate = buffer.format.sampleRate
                    }
                    for (index, audio) in buffers.enumerated() where index < state.channels.count {
                        guard let source = audio.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        state.channels[index].append(contentsOf: UnsafeBufferPointer(start: source, count: frames))
                    }
                }
            }
        }
    }

    @MainActor private final class Events {
        var log: [String] = []
    }

    /// What one load played, and what the engine said about its graph.
    private struct Played {
        var log: [String]
        var tap: Tap
        var rate: Double?
        var channels: Int?
        var activated: Double?
    }

    /// A signal that is never zero at its first sample, so that the first non-zero output sample is its start.
    /// Another sample rate or a filter changes it.
    static func signal(_ count: Int, channel: Int = 0) -> [Float] {
        (0..<count).map { Float(sin(Double($0) * 0.37 + 1 + Double(channel)) * 0.5) }
    }

    func wav(_ name: String, rate: Double, channels: Int, count: Int) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels)))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<channels {
            for (frame, sample) in Self.signal(count, channel: channel).enumerated() {
                buffer.floatChannelData![channel][frame] = sample
            }
        }
        let url = root.appending(path: name)
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        try AVAudioFile(forWriting: url, settings: settings).write(from: buffer)
        return url
    }

    /// Loads `files` from `start` and waits until the last one ends, or the engine reports a format change or a
    /// failure. A host would reload at a format change. This helper stops there.
    @MainActor private func play(
        _ files: [URL], from start: Int = 0, gainNode: Bool = false
    ) async throws -> Played {
        let tap = Tap()
        let events = Events()
        let engine = GaplessEngine(
            rendered: { tap.record($0) }, manualRendering: true, gainNode: gainNode, fadeSeconds: 0)
        engine.onEvent = { event in
            switch event {
            case .movementEnded(let index): events.log.append("end \(index)")
            case .formatChanged(let index): events.log.append("format \(index)")
            case .failed(let text), .problem(let text): events.log.append("failed \(text)")
            default: break
            }
        }
        defer { engine.discard() }
        let tracks = files.indices.map { PlaybackTrack(id: String($0), duration: 1, suffix: "wav") }
        engine.load(tracks, from: start, offset: 0) { .file(files[Int($0.id)!]) }
        let last = "end \(files.count - 1)"
        for _ in 0..<1000
        where !events.log.contains(last) && !events.log.contains(where: { $0.hasPrefix("failed") || $0.hasPrefix("format") })
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        // The tap delivers whole blocks, so its last block can arrive after the end event.
        try await Task.sleep(for: .milliseconds(300))
        return Played(
            log: events.log, tap: tap, rate: engine.sourceSampleRate, channels: engine.sourceChannelCount,
            activated: engine.activatedSampleRate)
    }

    /// The output from its first sound on. Digital silence before it is the node's start.
    private func rendered(_ tap: Tap, channel: Int) -> ArraySlice<Float> {
        let samples = tap.channel(channel)
        guard let first = samples.firstIndex(where: { $0 != 0 }) else { return [] }
        return samples[first...]
    }

    /// Checks that the output starts with `expected`, sample for sample, up to the last block that the tap holds.
    private func expectExact(_ tap: Tap, channel: Int, _ expected: [Float], rate: Double) {
        let output = rendered(tap, channel: channel)
        // The last tap block is partial and can still wait. Everything before it is exact.
        let compared = min(output.count, expected.count)
        #expect(compared >= expected.count - Int(rate * 0.3), "The output holds \(compared) of \(expected.count) frames")
        #expect(Array(output.prefix(compared)) == Array(expected.prefix(compared)))
    }

    @MainActor @Test(arguments: [44_100.0, 48_000, 88_200, 96_000, 176_400, 192_000])
    func aTrackPlaysAtItsOwnRateWithoutConversion(rate: Double) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let count = Int(rate * 1.5)
        let played = try await play([try wav("track.wav", rate: rate, channels: 2, count: count)])
        #expect(played.log == ["end 0"])
        #expect(played.rate == rate)
        #expect(played.tap.rate == rate)
        #expect(played.tap.channelCount == 2)
        #expect(played.activated.map { $0 > 0 } == true, "The engine reads the session rate back after activation")
        for channel in 0..<2 {
            expectExact(played.tap, channel: channel, Self.signal(count, channel: channel), rate: rate)
        }
    }

    @MainActor @Test func aJoinAtTheSameFormatStaysGapless() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let count = 96_000
        let files = [
            try wav("a.wav", rate: 96_000, channels: 2, count: count),
            try wav("b.wav", rate: 96_000, channels: 2, count: count),
        ]
        let played = try await play(files)
        #expect(played.log == ["end 0", "end 1"])
        #expect(played.tap.rate == 96_000)
        let signal = Self.signal(count)
        expectExact(played.tap, channel: 0, signal + signal, rate: 96_000)
    }

    /// The engine stops scheduling at the boundary, plays the track before it out, and asks the host to reload. The
    /// reload then plays the next track at its own rate.
    @MainActor @Test func aRateChangeEndsTheLoadAndTheReloadKeepsTheNewRate() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            try wav("first.wav", rate: 44_100, channels: 2, count: 44_100),
            try wav("second.wav", rate: 96_000, channels: 2, count: 96_000),
        ]
        let first = try await play(files)
        #expect(first.log == ["end 0", "format 1"])
        #expect(first.rate == 44_100)
        #expect(first.tap.rate == 44_100)
        expectExact(first.tap, channel: 0, Self.signal(44_100), rate: 44_100)
        let second = try await play(files, from: 1)
        #expect(second.log == ["end 1"])
        #expect(second.rate == 96_000)
        #expect(second.tap.rate == 96_000)
        expectExact(second.tap, channel: 0, Self.signal(96_000), rate: 96_000)
    }

    @MainActor @Test func aChannelChangeEndsTheLoadWithoutDownmixing() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            try wav("mono.wav", rate: 48_000, channels: 1, count: 48_000),
            try wav("stereo.wav", rate: 48_000, channels: 2, count: 48_000),
        ]
        let first = try await play(files)
        #expect(first.log == ["end 0", "format 1"])
        #expect(first.channels == 1)
        #expect(first.tap.channelCount == 1)
        expectExact(first.tap, channel: 0, Self.signal(48_000), rate: 48_000)
        let second = try await play(files, from: 1)
        #expect(second.log == ["end 1"])
        #expect(second.channels == 2)
        #expect(second.tap.channelCount == 2)
        expectExact(second.tap, channel: 1, Self.signal(48_000, channel: 1), rate: 48_000)
    }

    /// With the gain node in the path and 0 dB set, the stage can still change samples. The number goes to the log,
    /// so that the Lab can decide whether the node must leave the path when leveling is off.
    @MainActor @Test func measureTheGainNodeAtZeroDecibels() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let count = 96_000
        let played = try await play([try wav("level.wav", rate: 96_000, channels: 2, count: count)], gainNode: true)
        let output = rendered(played.tap, channel: 0)
        let expected = Self.signal(count)
        let compared = min(output.count, expected.count)
        let error = zip(output.prefix(compared), expected.prefix(compared)).map { abs($0 - $1) }.max() ?? .infinity
        print("gain node at 0 dB: compared=\(compared), max error=\(error)")
        #expect(compared > count / 2)
        #expect(error < 0.001)
    }
}
