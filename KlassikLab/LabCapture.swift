import AVFoundation
import Foundation
import Synchronization

/// A single-producer, single-consumer ring of samples. The producer is the engine's tap queue and the consumer is
/// the writer task, so neither waits for the other. A full ring drops the new samples and counts them.
final class CaptureRing: @unchecked Sendable {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)
    private let lost = Atomic<Int>(0)

    /// `capacity` is a power of two, in samples.
    init(capacity: Int) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0)
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit { storage.deallocate() }

    /// The samples that did not fit.
    var dropped: Int { lost.load(ordering: .relaxed) }

    /// Copies `count` samples in, all or none. Returns false and counts them when they do not fit.
    func push(_ source: UnsafePointer<Float>, count: Int) -> Bool {
        let write = head.load(ordering: .relaxed)
        let read = tail.load(ordering: .acquiring)
        guard capacity - (write - read) >= count else {
            lost.add(count, ordering: .relaxed)
            return false
        }
        for index in 0..<count { storage[(write + index) & (capacity - 1)] = source[index] }
        head.store(write + count, ordering: .releasing)
        return true
    }

    /// Copies up to `limit` samples out. Returns how many.
    func pop(into target: UnsafeMutablePointer<Float>, limit: Int) -> Int {
        let read = tail.load(ordering: .relaxed)
        let write = head.load(ordering: .acquiring)
        let count = min(write - read, limit)
        for index in 0..<count { target[index] = storage[(read + index) & (capacity - 1)] }
        tail.store(read + count, ordering: .releasing)
        return count
    }

    var isEmpty: Bool { head.load(ordering: .acquiring) == tail.load(ordering: .acquiring) }
}

/// The header of a 32-bit float WAV file.
enum CaptureWAV {
    static let headerSize = 58

    static func header(rate: Int, channels: Int, frames: Int) -> Data {
        let bytes = frames * channels * 4
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: Array(value.utf8)) }
        func word(_ value: Int, _ size: Int) {
            for shift in 0..<size { data.append(UInt8((value >> (8 * shift)) & 0xff)) }
        }
        text("RIFF")
        word(headerSize - 8 + bytes, 4)
        text("WAVE")
        text("fmt ")
        word(18, 4)
        word(3, 2)  // IEEE float
        word(channels, 2)
        word(rate, 4)
        word(rate * channels * 4, 4)
        word(channels * 4, 2)
        word(32, 2)
        word(0, 2)
        text("fact")
        word(4, 4)
        word(frames, 4)
        text("data")
        word(bytes, 4)
        return data
    }
}

/// Records the engine's output: the tap copies, a background task writes. It never blocks the tap and never grows
/// past `maxSeconds` of audio.
final class CaptureRecorder: @unchecked Sendable {
    struct Result: Equatable {
        var url: URL?
        var frames: Int
        var rate: Int
        var channels: Int
        /// The samples that the writer could not take in time.
        var dropped: Int
        var capped: Bool
        var formatChanged: Bool
        /// Why the file could not be written, when a write failed.
        var error: String? = nil
    }

    static let maxSeconds = 60

    private let ring: CaptureRing
    private let url: URL
    private let maxSeconds: Int
    private let rate = Atomic<Int>(0)
    private let channels = Atomic<Int>(0)
    private let pushed = Atomic<Int>(0)
    private let capFlag = Atomic<Bool>(false)
    private let formatFlag = Atomic<Bool>(false)
    private let finishing = Atomic<Bool>(false)
    private let failFlag = Atomic<Bool>(false)
    /// The tap's one scratch block, allocated before the tap runs so that the audio path never allocates.
    private let scratch: UnsafeMutablePointer<Float>
    private static let scratchSamples = 1 << 15
    private var writer: Task<Result, Never>?
    /// Called once, by the writer task and never by the tap, when the cap, a format change or a write error ends
    /// the recording. It runs off the main actor.
    private let onCap: @Sendable () -> Void

    init(
        url: URL, maxSeconds: Int = CaptureRecorder.maxSeconds, ringSamples: Int = 1 << 21,
        onCap: @escaping @Sendable () -> Void = {}
    ) {
        self.url = url
        self.maxSeconds = maxSeconds
        self.onCap = onCap
        ring = CaptureRing(capacity: ringSamples)
        scratch = .allocate(capacity: Self.scratchSamples)
        scratch.initialize(repeating: 0, count: Self.scratchSamples)
        writer = Task.detached(priority: .utility) { [self] in await write() }
    }

    deinit { scratch.deallocate() }

    /// Runs on the engine's tap queue. Copies the block, interleaved, and returns.
    func tap(_ buffer: AVReadOnlyAudioPCMBuffer) {
        buffer.withUnsafeAudioBufferList { record(format: buffer.format, frames: Int(buffer.frameLength), list: $0) }
    }

    /// The same copy for a buffer that the caller owns.
    func tap(_ buffer: AVAudioPCMBuffer) {
        record(format: buffer.format, frames: Int(buffer.frameLength), list: buffer.audioBufferList)
    }

    private func record(format: AVAudioFormat, frames available: Int, list: UnsafePointer<AudioBufferList>) {
        guard !capFlag.load(ordering: .relaxed), !formatFlag.load(ordering: .relaxed),
            !failFlag.load(ordering: .relaxed)
        else { return }
        guard format.commonFormat == .pcmFormatFloat32 else { return }
        let rateNow = Int(format.sampleRate.rounded())
        let channelsNow = Int(format.channelCount)
        let known = channels.load(ordering: .relaxed)
        if known == 0 {
            rate.store(rateNow, ordering: .relaxed)
            channels.store(channelsNow, ordering: .relaxed)
        } else if known != channelsNow || rate.load(ordering: .relaxed) != rateNow {
            formatFlag.store(true, ordering: .releasing)
            return
        }
        let limit = maxSeconds * rateNow
        let done = pushed.load(ordering: .relaxed)
        let frames = min(available, limit - done)
        guard frames > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        let out = scratch
        let block = Self.scratchSamples / channelsNow
        var start = 0
        while start < frames {
            let part = min(block, frames - start)
            if buffers.count == 1 && Int(buffers[0].mNumberChannels) == channelsNow {
                guard let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                for index in 0..<(part * channelsNow) { out[index] = data[start * channelsNow + index] }
            } else {
                for channel in 0..<channelsNow {
                    guard let data = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { return }
                    for frame in 0..<part { out[frame * channelsNow + channel] = data[start + frame] }
                }
            }
            // A block that does not fit is lost and counted; the sidecar warns about the hole.
            _ = ring.push(out, count: part * channelsNow)
            start += part
        }
        pushed.store(done + frames, ordering: .relaxed)
        if done + frames >= limit { capFlag.store(true, ordering: .releasing) }
    }

    /// Stops the tap's input, waits for the writer to drain the ring, and closes the file.
    func finish() async -> Result {
        finishing.store(true, ordering: .releasing)
        let empty = Result(
            url: nil, frames: 0, rate: 0, channels: 0, dropped: 0, capped: false, formatChanged: false)
        return await writer?.value ?? empty
    }

    private func write() async -> Result {
        var handle: FileHandle?
        var frames = 0
        var failure: String?
        var notified = false
        let chunk = 1 << 14
        let chunkBuffer = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        defer { chunkBuffer.deallocate() }
        while true {
            let stopping = finishing.load(ordering: .acquiring)
            if !notified,
                capFlag.load(ordering: .acquiring) || formatFlag.load(ordering: .acquiring) || failure != nil
            {
                notified = true
                onCap()
            }
            var wrote = false
            let width = channels.load(ordering: .acquiring)
            if width > 0, !ring.isEmpty {
                if handle == nil {
                    do {
                        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        handle = try FileHandle(forWritingTo: url)
                        let first = rate.load(ordering: .relaxed)
                        try handle?.write(contentsOf: CaptureWAV.header(rate: first, channels: width, frames: 0))
                    } catch {
                        failure = error.localizedDescription
                        failFlag.store(true, ordering: .releasing)
                    }
                }
                // Whole frames only, so that the file never holds half a frame.
                let take = (chunk / width) * width
                let count = ring.pop(into: chunkBuffer, limit: take)
                if count > 0, failure == nil {
                    do {
                        try handle?.write(contentsOf: Data(bytes: chunkBuffer, count: count * 4))
                        frames += count / width
                    } catch {
                        failure = error.localizedDescription
                        failFlag.store(true, ordering: .releasing)
                    }
                }
                if count > 0 { wrote = true }
            }
            if stopping, ring.isEmpty { break }
            if !wrote { try? await Task.sleep(for: .milliseconds(20)) }
        }
        let width = channels.load(ordering: .relaxed)
        let sampleRate = rate.load(ordering: .relaxed)
        if let handle {
            do {
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: CaptureWAV.header(rate: sampleRate, channels: width, frames: frames))
                try handle.close()
            } catch {
                failure = failure ?? error.localizedDescription
            }
        }
        if !notified, failure != nil { onCap() }
        return Result(
            url: handle == nil ? nil : url, frames: frames, rate: sampleRate, channels: width, dropped: ring.dropped,
            capped: capFlag.load(ordering: .relaxed), formatChanged: formatFlag.load(ordering: .relaxed),
            error: failure)
    }
}

/// The text next to the WAV: what the capture holds and how the Lab was set.
enum CaptureSidecar {
    static func text(
        caseTitle: String, fade: LabFadeSettings, replayGain: Bool, throttle: String, route: [String],
        result: CaptureRecorder.Result, startedAt: Date
    ) -> String {
        let seconds = result.rate > 0 ? Double(result.frames) / Double(result.rate) : 0
        var lines = [
            "Playback Lab capture",
            "Case: \(caseTitle)",
            "Started: \(ISO8601DateFormatter().string(from: startedAt))",
            "File: 32-bit float WAV, \(result.rate) Hz, \(result.channels) channels, \(result.frames) frames, "
                + String(format: "%.2f s", seconds),
            "Tap: final output of the engine, after the fade stage, the gain and the mixer, before the hardware",
            "Fade out: \(fade.outCurve.title), \(Int(fade.outMilliseconds)) ms",
            "Fade in: \(fade.inCurve.title), \(Int(fade.inMilliseconds)) ms",
            "Seek mode: \(fade.seek.title)"
                + (fade.seek == .silence ? ", silence \(Int(fade.silenceMilliseconds)) ms" : ""),
            "ReplayGain: \(replayGain ? "on" : "off")",
            "Network throttle: \(throttle)",
            "Route:",
        ]
        lines += route.map { "  \($0)" }
        if result.capped { lines.append("Stopped at the \(CaptureRecorder.maxSeconds) s cap.") }
        if result.formatChanged { lines.append("Stopped when the output rate or channel count changed.") }
        if let error = result.error { lines.append("Write error: \(error)") }
        if result.dropped > 0 { lines.append("Warning: \(result.dropped) samples dropped, the file has holes.") }
        return lines.joined(separator: "\n") + "\n"
    }
}
