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

    @Test func theRingKeepsOrderAcrossTheWrap() {
        let ring = CaptureRing(capacity: 8)
        var out = [Float](repeating: 0, count: 8)
        var seen: [Float] = []
        for round in 0..<5 {
            let block = (0..<5).map { Float(round * 5 + $0) }
            #expect(block.withUnsafeBufferPointer { ring.push($0.baseAddress!, count: 5) })
            let count = out.withUnsafeMutableBufferPointer { ring.pop(into: $0.baseAddress!, limit: 8) }
            seen += out[0..<count]
        }
        #expect(seen == (0..<25).map(Float.init))
        #expect(ring.dropped == 0)
    }

    @Test func aFullRingDropsAndCountsInsteadOfWaiting() {
        let ring = CaptureRing(capacity: 4)
        let block: [Float] = [1, 2, 3]
        #expect(block.withUnsafeBufferPointer { ring.push($0.baseAddress!, count: 3) })
        #expect(!block.withUnsafeBufferPointer { ring.push($0.baseAddress!, count: 3) })
        #expect(ring.dropped == 3)
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

    @Test func theRecorderWritesTheSamplesInterleavedAndExact() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "a.wav")
        let recorder = CaptureRecorder(url: url)
        for index in 0..<4 { recorder.tap(try block(1_000, channels: 2, rate: 48_000, start: index * 1_000)) }
        let result = await recorder.finish()
        #expect(result.frames == 4_000 && result.rate == 48_000 && result.channels == 2 && result.dropped == 0)
        let data = try Data(contentsOf: url)
        #expect(data.count == CaptureWAV.headerSize + 4_000 * 8)
        let floats = data.dropFirst(CaptureWAV.headerSize).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        for frame in [0, 1, 999, 1_000, 3_999] {
            #expect(floats[frame * 2] == Float(frame) * 0.001)
            #expect(floats[frame * 2 + 1] == Float(frame) * 0.001 + 1)
        }
    }

    @Test func theCapEndsTheRecordingAtTheLimit() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let capped = Mutex(0)
        let recorder = CaptureRecorder(url: root.appending(path: "c.wav"), maxSeconds: 1) {
            capped.withLock { $0 += 1 }
        }
        for index in 0..<5 { recorder.tap(try block(1_000, channels: 1, rate: 1_000, start: index * 1_000)) }
        let result = await recorder.finish()
        #expect(result.frames == 1_000 && result.capped)
        #expect(capped.withLock { $0 } == 1)
    }

    @Test func aFormatChangeStopsTheRecording() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = CaptureRecorder(url: root.appending(path: "f.wav"))
        recorder.tap(try block(500, channels: 2, rate: 48_000, start: 0))
        recorder.tap(try block(500, channels: 2, rate: 44_100, start: 0))
        let result = await recorder.finish()
        #expect(result.frames == 500 && result.formatChanged)
    }

    @Test func noSoundGivesNoFile() async {
        let recorder = CaptureRecorder(url: root.appending(path: "none.wav"))
        let result = await recorder.finish()
        #expect(result.url == nil && result.frames == 0)
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
        if capture == .whole { engine.setOutputTap { recorder.tap($0) } }
        engine.load([PlaybackTrack(id: "0", duration: 1, suffix: "wav")], from: 0, offset: 0.25) { _ in .file(file) }
        var started = false
        for _ in 0..<1000 where !ended.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(10))
            if capture == .toggled, !started, !reference.channels.isEmpty, reference.channels[0].count > 4_096 {
                started = true
                engine.setOutputTap { recorder.tap($0) }
                try await Task.sleep(for: .milliseconds(20))
                engine.setOutputTap(nil)
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        if capture == .whole { engine.setOutputTap(nil) }
        let result = await recorder.finish()
        guard let written = result.url else { return (reference.channels, nil) }
        let data = try Data(contentsOf: written).dropFirst(CaptureWAV.headerSize)
        return (reference.channels, data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) })
    }

    enum CaptureWindow { case none, whole, toggled }

    @MainActor @Test func aCaptureOfASeekEqualsTheEngineOutputSampleForSample() async throws {
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

    /// Every block that reached the tap, in arrival order, and whether two blocks ever ran at once.
    private final class Delivery: Sendable {
        private let state = Mutex<[Float]>([])
        private let inFlight = Atomic<Int>(0)
        private let overlap = Atomic<Bool>(false)
        var samples: [Float] { state.withLock { $0 } }
        var overlapped: Bool { overlap.load(ordering: .acquiring) }

        func record(_ buffer: AVReadOnlyAudioPCMBuffer, into recorder: CaptureRecorder) {
            if inFlight.add(1, ordering: .acquiringAndReleasing).newValue > 1 { overlap.store(true, ordering: .releasing) }
            defer { inFlight.subtract(1, ordering: .acquiringAndReleasing) }
            let frames = Int(buffer.frameLength)
            buffer.withUnsafeAudioBufferList { list in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
                state.withLock { state in
                    for frame in 0..<frames {
                        for audio in buffers {
                            guard let source = audio.mData?.assumingMemoryBound(to: Float.self) else { continue }
                            let width = Int(audio.mNumberChannels)
                            for channel in 0..<width { state.append(source[frame * width + channel]) }
                        }
                    }
                }
            }
            recorder.tap(buffer)
        }
    }

    @MainActor @Test(arguments: [SeekMode.today, SeekMode.crossfade])
    func twoSeeksWithACaptureRunningLeaveTheCaptureEqualToTheOutput(mode: SeekMode) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try wav(frames: 44_100 * 2)
        let engine = GaplessEngine(manualRendering: true, gainNode: true, watchesStarvation: false)
        engine.fadeOptions = FadeOptions(seek: mode)
        defer { engine.discard() }
        let recorder = CaptureRecorder(url: root.appending(path: "seek-\(UUID().uuidString).wav"))
        let delivery = Delivery()
        engine.setOutputTap { delivery.record($0, into: recorder) }
        let track = PlaybackTrack(id: "0", duration: 2, suffix: "wav")
        engine.load([track], from: 0, offset: 0) { _ in .file(file) }
        for offset in [0.5, 1.0] {
            try await Task.sleep(for: .milliseconds(300))
            engine.load([track], from: 0, offset: offset) { _ in .file(file) }
        }
        try await Task.sleep(for: .milliseconds(900))
        engine.setOutputTap(nil)
        let result = await recorder.finish()
        let url = try #require(result.url)
        let data = try Data(contentsOf: url).dropFirst(CaptureWAV.headerSize)
        let captured = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let delivered = delivery.samples
        #expect(!delivery.overlapped, "two engines fed the tap at once")
        #expect(result.dropped == 0)
        #expect(captured.count > 20_000)
        #expect(captured == delivered)
    }
}
