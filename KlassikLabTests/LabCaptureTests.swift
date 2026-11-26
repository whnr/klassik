import AVFoundation
import Foundation
import Synchronization
import Testing

@testable import KlassikEngine
@testable import KlassikLab

@Suite(.serialized)
struct LabCaptureTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "lab-capture-\(UUID().uuidString)")

    // MARK: Ring

    @Test func theRingKeepsBlocksInOrderAcrossTheWrap() {
        let ring = CaptureRing(capacity: 32)
        var out = [Float](repeating: 0, count: 8)
        var seen: [Float] = []
        var starts: [Int] = []
        for round in 0..<9 {
            let block = (0..<5).map { Float(round * 5 + $0) }
            #expect(block.withUnsafeBufferPointer { ring.push(start: round * 100, $0.baseAddress!, count: 5) })
            let record = out.withUnsafeMutableBufferPointer { ring.pop(into: $0.baseAddress!, limit: 8) }
            starts.append(record?.start ?? -1)
            seen += out[0..<(record?.count ?? 0)]
        }
        #expect(seen == (0..<45).map(Float.init))
        #expect(starts == (0..<9).map { $0 * 100 })
        #expect(ring.dropped == 0)
        #expect(ring.isEmpty)
    }

    @Test func aFullRingDropsAWholeBlockAndCountsIt() {
        let ring = CaptureRing(capacity: 8)
        let block: [Float] = [1, 2, 3]
        #expect(block.withUnsafeBufferPointer { ring.push(start: 7, $0.baseAddress!, count: 3) })
        #expect(!block.withUnsafeBufferPointer { ring.push(start: 9, $0.baseAddress!, count: 3) })
        #expect(ring.dropped == 3)
        var out = [Float](repeating: 0, count: 3)
        let record = out.withUnsafeMutableBufferPointer { ring.pop(into: $0.baseAddress!, limit: 3) }
        #expect(record?.start == 7 && record?.count == 3 && out == block)
        #expect(out.withUnsafeMutableBufferPointer { ring.pop(into: $0.baseAddress!, limit: 3) } == nil)
    }

    // MARK: Mixer

    @Test func theMixerSumsOverlapsAndFillsGapsWithSilence() {
        var mixer = CaptureMixer(channels: 1)
        let first: [Float] = [1, 1, 1, 1]
        let second: [Float] = [2, 2, 2, 2]
        let third: [Float] = [3, 3]
        first.withUnsafeBufferPointer { mixer.add(start: 0, frames: 4, samples: $0.baseAddress!) }
        second.withUnsafeBufferPointer { mixer.add(start: 2, frames: 4, samples: $0.baseAddress!) }
        third.withUnsafeBufferPointer { mixer.add(start: 10, frames: 2, samples: $0.baseAddress!) }
        var out: [Float] = []
        mixer.release(upTo: 3) { out += $0 }
        mixer.release(upTo: 12) { out += $0 }
        #expect(out == [1, 1, 3, 3, 2, 2, 0, 0, 0, 0, 3, 3])
        #expect(mixer.emitted == 12 && mixer.end == 12 && mixer.late == 0)
        // A block of a time that was released is cut, and counted.
        first.withUnsafeBufferPointer { mixer.add(start: 10, frames: 4, samples: $0.baseAddress!) }
        #expect(mixer.late == 2 && mixer.end == 14)
    }

    // MARK: File

    @Test func theHeaderIsA32BitFloatWAV() throws {
        let header = CaptureWAV.header(rate: 96_000, channels: 2, frames: 10)
        #expect(header.count == CaptureWAV.headerSize)
        #expect(String(decoding: header[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: header[8..<12], as: UTF8.self) == "WAVE")
        func word(_ at: Int, _ size: Int) -> Int {
            (0..<size).reduce(0) { $0 | Int(header[at + $1]) << (8 * $1) }
        }
        #expect(word(20, 2) == 3)
        #expect(word(22, 2) == 2)
        #expect(word(24, 4) == 96_000)
        #expect(word(34, 2) == 32)
        #expect(word(54, 4) == 10 * 2 * 4)
        #expect(word(4, 4) == CaptureWAV.headerSize - 8 + 80)
    }

    private func block(_ frames: Int, channels: Int, rate: Double, start: Int) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels)))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<channels {
            for frame in 0..<frames {
                buffer.floatChannelData![channel][frame] = Float(start + frame) * 0.001 + Float(channel)
            }
        }
        return buffer
    }

    /// A mono block of `frames` frames at 1 kHz, all of one value.
    private func level(_ value: Float, frames: Int) throws -> AVAudioPCMBuffer {
        let buffer = try block(frames, channels: 1, rate: 1_000, start: 0)
        for frame in 0..<frames { buffer.floatChannelData![0][frame] = value }
        return buffer
    }

    private func samples(of url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url).dropFirst(CaptureWAV.headerSize)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    @Test func theRecorderWritesTheSamplesInterleavedAndExact() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "a.wav")
        let recorder = CaptureRecorder(url: url)
        let source = recorder.makeSource(startSeconds: 0)
        for index in 0..<4 {
            source.tap(
                try block(1_000, channels: 2, rate: 48_000, start: index * 1_000),
                atSeconds: Double(index * 1_000) / 48_000)
        }
        let result = await recorder.finish()
        #expect(result.frames == 4_000 && result.rate == 48_000 && result.channels == 2 && result.dropped == 0)
        let data = try Data(contentsOf: url)
        #expect(data.count == CaptureWAV.headerSize + 4_000 * 8)
        let floats = try samples(of: url)
        for frame in [0, 1, 999, 1_000, 3_999] {
            #expect(floats[frame * 2] == Float(frame) * 0.001)
            #expect(floats[frame * 2 + 1] == Float(frame) * 0.001 + 1)
        }
    }

    @Test func graphsThatOverlapAreSummedAndGapsAreSilent() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "mix.wav")
        let recorder = CaptureRecorder(url: url)
        // The graphs exist before their sound does, as in the engine, where a tap installs before its first block.
        let old = recorder.makeSource(startSeconds: 0)
        let new = recorder.makeSource(startSeconds: 0.3)
        let later = recorder.makeSource(startSeconds: 1)
        for index in 0..<5 { old.tap(try level(1, frames: 100), atSeconds: Double(index) / 10) }
        old.finish()
        for index in 0..<5 { new.tap(try level(0.5, frames: 100), atSeconds: 0.3 + Double(index) / 10) }
        new.finish()
        later.tap(try level(0.25, frames: 100), atSeconds: 1)
        later.finish()
        let result = await recorder.finish()
        var expected = [Float](repeating: 0, count: 1_100)
        for frame in 0..<500 { expected[frame] += 1 }
        for frame in 300..<800 { expected[frame] += 0.5 }
        for frame in 1_000..<1_100 { expected[frame] += 0.25 }
        let written = try samples(of: url)
        #expect(result.frames == 1_100 && result.dropped == 0)
        #expect(written == expected)
    }

    /// A mono block at 48 kHz whose frame `first + n` has the value `value(first + n)`.
    private func ramp(first: Int, frames: Int, value: (Int) -> Float) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames { buffer.floatChannelData![0][frame] = value(first + frame) }
        return buffer
    }

    /// Two graphs whose host clocks start 0.35 s apart, with ±5 ms of jitter on every block after the first, over
    /// 60 s. The host time of the first block of a graph places it. After that the blocks follow by sample count, so
    /// the jitter makes no hole and no overlap, the offset between the graphs stays fixed, and nothing drifts.
    @Test func twoGraphsOnTheHostClockLandSampleExactAndDoNotDriftOverSixtySeconds() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "clock.wav")
        let recorder = CaptureRecorder(url: url, maxSeconds: 70, ringWords: 1 << 22)
        let rate = 48_000
        let block = 4_800
        let blocks = 600
        let host = 123_456.0
        let offset = 0.35
        let offsetFrames = 16_800
        let first = recorder.makeSource(startSeconds: host)
        let second = recorder.makeSource(startSeconds: host + offset)
        func a(_ frame: Int) -> Float { Float(frame % 1_000 + 1) * 0.001 }
        func b(_ frame: Int) -> Float { Float(frame % 777 + 1) * -0.002 }
        var seed: UInt64 = 7
        func jitter() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Double(seed >> 33) / Double(1 << 31) - 0.5) * 0.01
        }
        for index in 0..<blocks {
            let nominal = Double(index * block) / Double(rate)
            let noise = index == 0 ? 0 : jitter()
            first.tap(try ramp(first: index * block, frames: block, value: a), atSeconds: host + nominal + noise)
            let other = index == 0 ? 0 : jitter()
            second.tap(
                try ramp(first: index * block, frames: block, value: b), atSeconds: host + offset + nominal + other)
        }
        first.finish()
        second.finish()
        let result = await recorder.finish()
        let total = offsetFrames + blocks * block
        var expected = [Float](repeating: 0, count: total)
        for frame in 0..<(blocks * block) { expected[frame] += a(frame) }
        for frame in 0..<(blocks * block) { expected[offsetFrames + frame] += b(frame) }
        #expect(result.error == nil && result.dropped == 0 && !result.capped)
        #expect(result.frames == total && result.rate == rate)
        let written = try samples(of: url)
        #expect(written.count == total)
        // One comparison for the whole file: a hole, an overlap or a drift would shift the tail against the head.
        let wrong = zip(written, expected).enumerated().first { $0.element.0 != $0.element.1 }
        #expect(wrong == nil, "first difference at frame \(wrong?.offset ?? -1)")
        // The last frame of each graph sits where its sample count says, 60 s after its first.
        #expect(written[blocks * block - 1] == a(blocks * block - 1) + (b(blocks * block - 1 - offsetFrames)))
        #expect(written[total - 1] == b(blocks * block - 1))
    }

    /// A block that comes more than 20 ms away from where the one before it ends is a real gap or overlap of the
    /// device, and the stamp places it. A smaller difference is clock jitter, and the sample count wins.
    @Test func aBlockMoreThanTwentyMillisecondsOffItsPlaceKeepsItsStamp() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "snap.wav")
        let recorder = CaptureRecorder(url: url)
        let source = recorder.makeSource(startSeconds: 0)
        func one(_ frame: Int) -> Float { 1 }
        // 100 ms blocks. The second is 19 ms late, the third 30 ms late after the snap, the fourth on time again.
        source.tap(try ramp(first: 0, frames: 4_800, value: one), atSeconds: 0)
        source.tap(try ramp(first: 0, frames: 4_800, value: one), atSeconds: 0.1 + 0.019)
        source.tap(try ramp(first: 0, frames: 4_800, value: one), atSeconds: 0.2 + 0.030)
        source.tap(try ramp(first: 0, frames: 4_800, value: one), atSeconds: 0.330)
        source.finish()
        let result = await recorder.finish()
        // The first three blocks run on from each other. The third starts 30 ms after its place, so 1 440 frames of
        // silence separate it from the second, and the fourth follows the third by its sample count.
        #expect(result.frames == 4 * 4_800 + 1_440 && result.dropped == 0)
        let written = try samples(of: url)
        #expect(written[0..<9_600].allSatisfy { $0 == 1 })
        #expect(written[9_600..<(9_600 + 1_440)].allSatisfy { $0 == 0 })
        #expect(written[(9_600 + 1_440)...].allSatisfy { $0 == 1 })
    }

    @Test func theCapEndsTheRecordingAtTheLimit() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capped = Mutex(0)
        let recorder = CaptureRecorder(url: root.appending(path: "c.wav"), maxSeconds: 1) {
            capped.withLock { $0 += 1 }
        }
        let source = recorder.makeSource(startSeconds: 0)
        for index in 0..<5 { source.tap(try level(1, frames: 1_000), atSeconds: Double(index)) }
        let result = await recorder.finish()
        #expect(result.frames == 1_000 && result.capped)
        #expect(capped.withLock { $0 } == 1)
    }

    @Test func aFormatChangeStopsTheRecording() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = CaptureRecorder(url: root.appending(path: "f.wav"))
        let source = recorder.makeSource(startSeconds: 0)
        source.tap(try block(500, channels: 2, rate: 48_000, start: 0), atSeconds: 0)
        source.tap(try block(500, channels: 2, rate: 44_100, start: 0), atSeconds: 0.5)
        let result = await recorder.finish()
        #expect(result.frames == 500 && result.formatChanged)
    }

    @Test func noSoundGivesNoFile() async {
        let recorder = CaptureRecorder(url: root.appending(path: "none.wav"))
        let result = await recorder.finish()
        #expect(result.url == nil && result.frames == 0)
    }

    // The writer task is the only thing that ends the capture, and a loaded runner can delay it for seconds. The test
    // waits for the recorder's own stop signal, with no deadline of its own, so that only a lost signal fails it.
    @Test(.timeLimit(.minutes(1)))
    func aFileThatCannotBeWrittenStopsTheTapAndSaysWhy() async throws {
        let calls = Mutex(0)
        let (stopped, signal) = AsyncStream.makeStream(of: Void.self)
        // The folder does not exist, so the file cannot be created.
        let recorder = CaptureRecorder(url: root.appending(path: "missing/w.wav")) {
            calls.withLock { $0 += 1 }
            signal.yield()
        }
        let source = recorder.makeSource(startSeconds: 0)
        source.tap(try level(1, frames: 1_000), atSeconds: 0)
        for await _ in stopped { break }
        #expect(recorder.isStopped)
        source.tap(try level(1, frames: 1_000), atSeconds: 1)
        let result = await recorder.finish()
        #expect(result.url == nil && result.frames == 0 && result.dropped == 0)
        #expect(result.error != nil)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func theSidecarNamesCaseSettingsAndRoute() {
        var fade = LabFadeSettings()
        fade.seek = .silence
        fade.silenceMilliseconds = 70
        fade.outCurve = .equalPower
        let result = CaptureRecorder.Result(
            url: nil, frames: 96_000, rate: 96_000, channels: 2, dropped: 0, capped: false, formatChanged: false)
        let text = CaptureSidecar.text(
            caseTitle: "FLAC 24/96", fade: fade, replayGain: false, throttle: "Off", route: ["Output: USB"],
            result: result, startedAt: Date(timeIntervalSince1970: 0))
        #expect(text.contains("Case: FLAC 24/96"))
        #expect(text.contains("96000 Hz, 2 channels, 96000 frames, 1.00 s"))
        #expect(text.contains("Fade out: Equal power (sin/cos), 100 ms"))
        #expect(text.contains("Seek mode: Silence, silence 70 ms"))
        #expect(text.contains("ReplayGain: off"))
        #expect(text.contains("  Output: USB"))
        #expect(!text.contains("Write error"))
    }

    @Test func theSidecarCarriesTheWriteError() {
        let result = CaptureRecorder.Result(
            url: nil, frames: 10, rate: 48_000, channels: 2, dropped: 4, capped: false, formatChanged: false,
            error: "The disk is full.")
        let text = CaptureSidecar.text(
            caseTitle: "WAV", fade: LabFadeSettings(), replayGain: true, throttle: "Off", route: [],
            result: result, startedAt: Date(timeIntervalSince1970: 0))
        #expect(text.contains("Write error: The disk is full."))
        #expect(text.contains("4 frames dropped"))
    }

    // MARK: Engine

    private func wav(frames: Int, rate: Double = 44_100) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<frames {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 0.37 + 1 + Double(channel)) * 0.5)
            }
        }
        let url = root.appending(path: "tone.wav")
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        try AVAudioFile(forWriting: url, settings: settings).write(from: buffer)
        return url
    }

    /// The interleaved samples that the engine's own pre-mixer tap saw: after the fade stage and the gain.
    private final class Reference: Sendable {
        private let state = Mutex<[[Float]]>([])
        var channels: [[Float]] { state.withLock { $0 } }
        func record(_ buffer: AVReadOnlyAudioPCMBuffer) {
            let frames = Int(buffer.frameLength)
            buffer.withUnsafeAudioBufferList { list in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
                state.withLock { state in
                    if state.isEmpty { state = Array(repeating: [], count: buffers.count) }
                    for (index, audio) in buffers.enumerated() {
                        guard let source = audio.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        state[index].append(contentsOf: UnsafeBufferPointer(start: source, count: frames))
                    }
                }
            }
        }
    }

    /// Plays the tone from `offset` through a real offline graph. `capture` runs the recorder through a window of
    /// the play time, or the whole of it.
    @MainActor private func play(capture: CaptureWindow) async throws -> (reference: [[Float]], captured: [Float]?) {
        let file = try wav(frames: 44_100)
        let reference = Reference()
        let engine = GaplessEngine(
            rendered: { reference.record($0) }, manualRendering: true, gainNode: true, watchesStarvation: false)
        let ended = Mutex(false)
        engine.onEvent = { if case .movementEnded = $0 { ended.withLock { $0 = true } } }
        defer { engine.discard() }
        let url = root.appending(path: "capture-\(UUID().uuidString).wav")
        let recorder = CaptureRecorder(url: url)
        if capture == .whole { engine.setOutputTap { recorder.makeSource(startSeconds: $0) } }
        engine.load([PlaybackTrack(id: "0", duration: 1, suffix: "wav")], from: 0, offset: 0.25) { _ in .file(file) }
        var started = false
        for _ in 0..<1000 where !ended.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(10))
            if capture == .toggled, !started, !reference.channels.isEmpty, reference.channels[0].count > 4_096 {
                started = true
                engine.setOutputTap { recorder.makeSource(startSeconds: $0) }
                try await Task.sleep(for: .milliseconds(20))
                engine.setOutputTap(nil)
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        if capture == .whole { engine.setOutputTap(nil) }
        let result = await recorder.finish()
        guard let written = result.url else { return (reference.channels, nil) }
        return (reference.channels, try samples(of: written))
    }

    enum CaptureWindow { case none, whole, toggled }

    @MainActor @Test func aCaptureOfAPlayEqualsTheEngineOutputSampleForSample() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (reference, captured) = try await play(capture: .whole)
        let samples = try #require(captured)
        let left = reference[0]
        let right = reference[1]
        let frames = samples.count / 2
        #expect(frames > 20_000, "captured only \(frames) frames")
        #expect(abs(frames - left.count) <= 8_192)
        let common = min(frames, left.count)
        for frame in 0..<common {
            guard samples[frame * 2] == left[frame], samples[frame * 2 + 1] == right[frame] else {
                Issue.record("first difference at frame \(frame)")
                return
            }
        }
    }

    @MainActor @Test func startingAndStoppingACaptureLeavesThePlaybackUnchanged() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = try await play(capture: .none)
        let toggled = try await play(capture: .toggled)
        for channel in 0..<2 {
            let a = plain.reference[channel]
            let b = toggled.reference[channel]
            #expect(a.count > 20_000 && b.count > 20_000)
            let common = min(a.count, b.count)
            #expect(abs(a.count - b.count) <= 8_192)
            #expect(Array(a[0..<common]) == Array(b[0..<common]))
        }
    }

    /// One graph's sink in a test: it logs every block that the graph's tap delivers, and passes it on to the
    /// capture.
    private final class LoggingSink: OutputTapSink, Sendable {
        struct Block {
            let seconds: Double
            let samples: [Float]
        }

        private let inner: CaptureSource
        private let log = Mutex<[Block]>([])

        init(_ inner: CaptureSource) { self.inner = inner }

        var blocks: [Block] { log.withLock { $0 } }

        func tap(_ buffer: AVReadOnlyAudioPCMBuffer, atSeconds seconds: Double) {
            let frames = Int(buffer.frameLength)
            buffer.withUnsafeAudioBufferList { list in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
                var interleaved: [Float] = []
                for frame in 0..<frames {
                    for audio in buffers {
                        guard let source = audio.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        let width = Int(audio.mNumberChannels)
                        for channel in 0..<width { interleaved.append(source[frame * width + channel]) }
                    }
                }
                log.withLock { $0.append(Block(seconds: seconds, samples: interleaved)) }
            }
            inner.tap(buffer, atSeconds: seconds)
        }

        func finish() { inner.finish() }
    }

    /// The sinks that an engine asked for, one per graph, in the order of the graphs.
    private final class Graphs: Sendable {
        private let recorder: CaptureRecorder
        private let made = Mutex<[LoggingSink]>([])

        init(_ recorder: CaptureRecorder) { self.recorder = recorder }

        var sinks: [LoggingSink] { made.withLock { $0 } }

        func make(startSeconds: Double) -> LoggingSink {
            let sink = LoggingSink(recorder.makeSource(startSeconds: startSeconds))
            made.withLock { $0.append(sink) }
            return sink
        }
    }

    @MainActor private func waitForSound(_ engine: GaplessEngine) async throws {
        for _ in 0..<500 where !engine.isSounding { try await Task.sleep(for: .milliseconds(10)) }
        try #require(engine.isSounding, "the graph never made sound")
    }

    /// Sums the logged blocks of all graphs on one timeline, each block at its time, the way a listener hears them.
    private func summed(_ sinks: [LoggingSink], rate: Double, channels: Int) -> [Float] {
        let blocks = sinks.flatMap(\.blocks)
        let origin = blocks.map(\.seconds).min() ?? 0
        func place(_ block: LoggingSink.Block) -> Int { Int(((block.seconds - origin) * rate).rounded()) }
        let end = blocks.map { place($0) + $0.samples.count / channels }.max() ?? 0
        var sum = [Float](repeating: 0, count: end * channels)
        for block in blocks {
            let offset = place(block) * channels
            for index in 0..<block.samples.count { sum[offset + index] += block.samples[index] }
        }
        return sum
    }

    private func peak(_ samples: [Float], from start: Double, to end: Double, rate: Double = 44_100) -> Float {
        let range = Int(start * rate) * 2..<Int(end * rate) * 2
        return samples[range].map { abs($0) }.max() ?? 0
    }

    /// A seek with a capture running. The first graph plays 0.5 s and is replaced by a second graph. The file must
    /// hold both graphs on one timeline: the fade-out of the first, the silence before the second, and the fade-in
    /// of the second, equal to the sum of what the two graphs delivered.
    @MainActor @Test(arguments: [SeekMode.today, SeekMode.silence(seconds: 0.05), SeekMode.crossfade])
    func aSeekWithACaptureRunningHoldsEverythingThatSounded(mode: SeekMode) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try wav(frames: 44_100 * 2)
        let engine = GaplessEngine(
            manualRendering: true, gainNode: true, watchesStarvation: false, renderOnDemand: true)
        engine.fadeOptions = FadeOptions(seek: mode)
        defer { engine.discard() }
        let recorder = CaptureRecorder(url: root.appending(path: "seek-\(UUID().uuidString).wav"))
        let graphs = Graphs(recorder)
        engine.setOutputTap { graphs.make(startSeconds: $0) }
        let track = PlaybackTrack(id: "0", duration: 2, suffix: "wav")
        engine.load([track], from: 0, offset: 0) { _ in .file(file) }
        try await waitForSound(engine)
        engine.render(frames: 22_050)
        engine.load([track], from: 0, offset: 1) { _ in .file(file) }
        try await waitForSound(engine)
        engine.render(frames: 22_050)
        // The tap queues deliver the last blocks, and the first graph's tap leaves after its fade.
        try await Task.sleep(for: .milliseconds(600))
        engine.setOutputTap(nil)
        let result = await recorder.finish()
        let url = try #require(result.url)
        let captured = try samples(of: url)

        let sinks = graphs.sinks
        #expect(sinks.count == 2, "each graph feeds its own sink")
        #expect(result.error == nil && result.dropped == 0)
        let expected = summed(sinks, rate: 44_100, channels: 2)
        #expect(captured.count == expected.count)
        for (index, value) in expected.enumerated() where index < captured.count {
            guard abs(captured[index] - value) <= 1e-6 else {
                Issue.record("first difference at frame \(index / 2): \(captured[index]) against \(value)")
                break
            }
        }

        // The first graph delivers its fade-out after the seek, up to the end of the fade, and the file holds it.
        let first = try #require(sinks.first?.blocks.last)
        #expect(first.seconds + Double(first.samples.count / 2) / 44_100 >= 0.6)
        #expect(peak(captured, from: 0.5, to: 0.55) > 0.05)
        // The second graph starts where the engine put it on the timeline.
        let start = try #require(sinks.last?.blocks.first?.seconds)
        let gap = mode == .silence(seconds: 0.05) ? 0.05 : 0
        #expect(abs(start - (0.5 + (gap > 0 ? 0.1 + gap : 0))) < 1e-6)
        #expect(peak(captured, from: start + 0.1, to: start + 0.15) > 0.05)
        if gap > 0 {
            // The fade-out ended at 0.6 s and the fade-in has not begun: the file is silent in between.
            #expect(peak(captured, from: 0.605, to: start - 0.005) == 0)
        }
    }
}
