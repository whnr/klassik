import AVFoundation
import Foundation
import KlassikEngine
import Synchronization

/// A single-producer, single-consumer ring of blocks. Each block is its first frame on the capture's timeline, its
/// sample count, and the samples. The producer is the tap queue of one graph and the consumer is the writer task, so
/// neither waits for the other. A full ring drops the new block and counts its samples.
final class CaptureRing: @unchecked Sendable {
    private static let headerWords = 2
    private let capacity: Int
    private let storage: UnsafeMutablePointer<UInt32>
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)
    private let lost = Atomic<Int>(0)

    /// `capacity` is a power of two, in words of four bytes.
    init(capacity: Int) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0)
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit { storage.deallocate() }

    /// The samples that did not fit.
    var dropped: Int { lost.load(ordering: .relaxed) }

    /// Copies a block in, all or none. Returns false and counts the samples when the block does not fit.
    func push(start: Int, _ source: UnsafePointer<Float>, count: Int) -> Bool {
        let words = Self.headerWords + count
        let write = head.load(ordering: .relaxed)
        let read = tail.load(ordering: .acquiring)
        guard capacity - (write - read) >= words else {
            lost.add(count, ordering: .relaxed)
            return false
        }
        let mask = capacity - 1
        storage[write & mask] = UInt32(truncatingIfNeeded: start)
        storage[(write + 1) & mask] = UInt32(truncatingIfNeeded: count)
        for index in 0..<count { storage[(write + Self.headerWords + index) & mask] = source[index].bitPattern }
        head.store(write + words, ordering: .releasing)
        return true
    }

    /// Copies the oldest block out, or returns nil when there is none. A block with more than `limit` samples is
    /// skipped.
    func pop(into target: UnsafeMutablePointer<Float>, limit: Int) -> (start: Int, count: Int)? {
        let read = tail.load(ordering: .relaxed)
        let write = head.load(ordering: .acquiring)
        guard write - read >= Self.headerWords else { return nil }
        let mask = capacity - 1
        let start = Int(storage[read & mask])
        let count = Int(storage[(read + 1) & mask])
        if count <= limit {
            for index in 0..<count {
                target[index] = Float(bitPattern: storage[(read + Self.headerWords + index) & mask])
            }
        }
        tail.store(read + Self.headerWords + count, ordering: .releasing)
        return count <= limit ? (start, count) : (start, 0)
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

/// What the sources and the writer of one capture share. Only atomics, so the tap never waits.
final class CaptureState: Sendable {
    let maxSeconds: Int
    let rate = Atomic<Int>(0)
    let channels = Atomic<Int>(0)
    /// The seconds of timeline frame 0, as the bits of a Double. All ones until the first block sets it.
    private let originBits = Atomic<UInt64>(.max)
    let capped = Atomic<Bool>(false)
    let formatChanged = Atomic<Bool>(false)
    let failed = Atomic<Bool>(false)
    let finishing = Atomic<Bool>(false)

    init(maxSeconds: Int) { self.maxSeconds = maxSeconds }

    /// False once the cap, a format change, a write error or the end of the capture stops the input.
    var accepting: Bool {
        !capped.load(ordering: .relaxed) && !formatChanged.load(ordering: .relaxed)
            && !failed.load(ordering: .relaxed) && !finishing.load(ordering: .relaxed)
    }

    /// The first block fixes the rate and the channel count. A later block of another format stops the capture.
    func adopt(rate rateNow: Int, channels channelsNow: Int) -> Bool {
        let known = channels.load(ordering: .acquiring)
        if known == 0 {
            rate.store(rateNow, ordering: .relaxed)
            channels.store(channelsNow, ordering: .releasing)
            return true
        }
        guard known == channelsNow, rate.load(ordering: .relaxed) == rateNow else {
            formatChanged.store(true, ordering: .releasing)
            return false
        }
        return true
    }

    /// The seconds of frame 0: the time of the first block that any graph delivered.
    func origin(settingTo seconds: Double) -> Double {
        let result = originBits.compareExchange(expected: .max, desired: seconds.bitPattern, ordering: .relaxed)
        return Double(bitPattern: result.exchanged ? seconds.bitPattern : result.original)
    }

    var originSeconds: Double? {
        let bits = originBits.load(ordering: .relaxed)
        return bits == .max ? nil : Double(bitPattern: bits)
    }
}

/// The feed of one graph into a capture: its own ring, so that no two producers share one. The engine calls `tap` on
/// the graph's tap queue and `finish` when the graph's tap is gone.
final class CaptureSource: OutputTapSink, @unchecked Sendable {
    static let scratchSamples = 1 << 15

    fileprivate let ring: CaptureRing
    /// The seconds at which the graph's tap was installed. No block of the graph is earlier.
    let birth: Double
    private let state: CaptureState
    private let closed = Atomic<Bool>(false)
    /// The one scratch block of the tap, allocated before the tap runs so that the audio path never allocates.
    private let scratch: UnsafeMutablePointer<Float>
    /// The frame after the last block, on the timeline. Only the producer touches it.
    private var expected = -1

    fileprivate init(state: CaptureState, birth: Double, ringWords: Int) {
        self.state = state
        self.birth = birth
        ring = CaptureRing(capacity: ringWords)
        scratch = .allocate(capacity: Self.scratchSamples)
        scratch.initialize(repeating: 0, count: Self.scratchSamples)
    }

    deinit { scratch.deallocate() }

    fileprivate var isClosed: Bool { closed.load(ordering: .acquiring) }

    func finish() { closed.store(true, ordering: .releasing) }

    /// Runs on the graph's tap queue. Copies the block, interleaved, and returns.
    func tap(_ buffer: AVReadOnlyAudioPCMBuffer, atSeconds seconds: Double) {
        buffer.withUnsafeAudioBufferList {
            record(format: buffer.format, frames: Int(buffer.frameLength), list: $0, at: seconds)
        }
    }

    /// The same copy for a buffer that the caller owns.
    func tap(_ buffer: AVAudioPCMBuffer, atSeconds seconds: Double) {
        record(format: buffer.format, frames: Int(buffer.frameLength), list: buffer.audioBufferList, at: seconds)
    }

    private func record(
        format: AVAudioFormat, frames available: Int, list: UnsafePointer<AudioBufferList>, at seconds: Double
    ) {
        guard state.accepting, available > 0, format.commonFormat == .pcmFormatFloat32 else { return }
        let rate = Int(format.sampleRate.rounded())
        let channels = Int(format.channelCount)
        guard state.adopt(rate: rate, channels: channels) else { return }
        let origin = state.origin(settingTo: seconds)
        var place = Int(((seconds - origin) * Double(rate)).rounded())
        // The blocks of one graph follow each other. The clock's jitter must not put a hole or an overlap between them.
        if expected >= 0, abs(place - expected) <= rate / 50 { place = expected }
        expected = place + available
        let limit = state.maxSeconds * rate
        // A block that starts before the timeline's frame 0 loses its first frames.
        let skip = max(0, -place)
        let first = place + skip
        let last = min(place + available, limit)
        if place + available >= limit { state.capped.store(true, ordering: .releasing) }
        guard last > first else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        let block = Self.scratchSamples / channels
        var done = 0
        while done < last - first {
            let part = min(block, last - first - done)
            let from = skip + done
            if buffers.count == 1 && Int(buffers[0].mNumberChannels) == channels {
                guard let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                for index in 0..<(part * channels) { scratch[index] = data[from * channels + index] }
            } else {
                for channel in 0..<channels {
                    guard let data = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { return }
                    for frame in 0..<part { scratch[frame * channels + channel] = data[from + frame] }
                }
            }
            // A block that does not fit is lost and counted; the sidecar warns about the hole.
            _ = ring.push(start: first + done, scratch, count: part * channels)
            done += part
        }
    }
}

/// Sums the blocks of all graphs on one timeline, and releases the frames that no later block can still change.
/// A frame that no block covers is silence. Only the writer task uses it.
struct CaptureMixer {
    let channels: Int
    /// The timeline frame where `buffer` starts: every frame before it has been released.
    private(set) var emitted = 0
    /// Frames that arrived after their time had been released.
    private(set) var late = 0
    private var buffer: [Float] = []

    init(channels: Int) { self.channels = channels }

    /// The frame after the last frame that a block covers.
    var end: Int { emitted + buffer.count / channels }

    mutating func add(start: Int, frames: Int, samples: UnsafePointer<Float>) {
        let skip = min(max(emitted - start, 0), frames)
        late += skip
        let count = frames - skip
        guard count > 0 else { return }
        let offset = (start + skip - emitted) * channels
        let needed = offset + count * channels
        if buffer.count < needed { buffer.append(contentsOf: repeatElement(0, count: needed - buffer.count)) }
        for index in 0..<(count * channels) { buffer[offset + index] += samples[skip * channels + index] }
    }

    /// Hands every frame before `frontier` to `write`, zeros where no block played.
    mutating func release(upTo frontier: Int, write: (UnsafeBufferPointer<Float>) throws -> Void) rethrows {
        guard frontier > emitted else { return }
        let stored = min(frontier, end) - emitted
        if stored > 0 {
            try buffer.withUnsafeBufferPointer { try write(UnsafeBufferPointer(rebasing: $0[0..<(stored * channels)])) }
            buffer.removeFirst(stored * channels)
            emitted += stored
        }
        let step = 1 << 14
        let zeros = [Float](repeating: 0, count: min(frontier - emitted, step) * channels)
        while emitted < frontier {
            let frames = min(frontier - emitted, step)
            try zeros.withUnsafeBufferPointer { try write(UnsafeBufferPointer(rebasing: $0[0..<(frames * channels)])) }
            emitted += frames
        }
    }
}

/// Records the engine's output: the taps copy, a background task mixes and writes. Every graph that sounds has its
/// own source, so the old graph's fade-out, the silence and the new graph's fade-in all reach the file, in the order
/// and the overlap in which they sounded. It never blocks a tap and never grows past `maxSeconds` of timeline.
final class CaptureRecorder: @unchecked Sendable {
    struct Result: Equatable {
        var url: URL?
        var frames: Int
        var rate: Int
        var channels: Int
        /// The frames that the writer could not take in time, or that came after their time had passed.
        var dropped: Int
        var capped: Bool
        var formatChanged: Bool
        /// Why the file could not be written, when a write failed.
        var error: String? = nil
    }

    static let maxSeconds = 60
    /// A graph whose blocks trail the newest block by more than this stops holding the file back.
    private static let lagSeconds = 1
    /// The time before its tap's install that a block may still carry.
    private static let slackSeconds = 0.05
    /// The newest time that stays out of the file. A graph whose tap installs now can still add to it.
    private static let holdSeconds = 0.25

    private let state: CaptureState
    private let url: URL
    private let ringWords: Int
    private let inbox = Mutex<[CaptureSource]>([])
    private var writer: Task<Result, Never>?
    /// Called once, by the writer task and never by a tap, when the cap, a format change or a write error ends the
    /// recording. It runs off the main actor.
    private let onCap: @Sendable () -> Void

    init(
        url: URL, maxSeconds: Int = CaptureRecorder.maxSeconds, ringWords: Int = 1 << 19,
        onCap: @escaping @Sendable () -> Void = {}
    ) {
        self.url = url
        self.ringWords = ringWords
        self.onCap = onCap
        state = CaptureState(maxSeconds: maxSeconds)
        writer = Task.detached(priority: .utility) { [self] in await write() }
    }

    /// True once the cap, a format change or a write error stopped the input.
    var isStopped: Bool {
        state.capped.load(ordering: .acquiring) || state.formatChanged.load(ordering: .acquiring)
            || state.failed.load(ordering: .acquiring)
    }

    /// The source of a graph whose tap starts at `startSeconds`. Allocates, so it runs before the tap does.
    func makeSource(startSeconds: Double) -> CaptureSource {
        let source = CaptureSource(state: state, birth: startSeconds, ringWords: ringWords)
        inbox.withLock { $0.append(source) }
        return source
    }

    /// Stops the input, waits for the writer to mix what the sources delivered, and closes the file.
    func finish() async -> Result {
        state.finishing.store(true, ordering: .releasing)
        let empty = Result(
            url: nil, frames: 0, rate: 0, channels: 0, dropped: 0, capped: false, formatChanged: false)
        return await writer?.value ?? empty
    }

    private final class Tracked {
        let source: CaptureSource
        /// The frame after the last block that the source delivered.
        var end: Int?
        var done = false
        /// True once a drain pass has run for the source. Its blocks may already wait in the ring before that.
        var drained = false
        init(_ source: CaptureSource) { self.source = source }
    }

    private func write() async -> Result {
        var file: FileHandle?
        var failure: String?
        var notified = false
        var written = 0
        var lostSamples = 0
        var active: [Tracked] = []
        var mixer = CaptureMixer(channels: 1)
        var mixing = false
        let chunkBuffer = UnsafeMutablePointer<Float>.allocate(capacity: CaptureSource.scratchSamples)
        defer { chunkBuffer.deallocate() }

        /// Releases the frames before `frontier` into the file.
        func flush(_ frontier: Int, width: Int, rate: Int) {
            guard failure == nil, frontier > mixer.emitted else { return }
            do {
                try mixer.release(upTo: frontier) { chunk in
                    if file == nil {
                        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        file = try FileHandle(forWritingTo: url)
                        try file?.write(contentsOf: CaptureWAV.header(rate: rate, channels: width, frames: 0))
                    }
                    try file?.write(contentsOf: Data(buffer: chunk))
                    written += chunk.count / width
                }
            } catch {
                failure = error.localizedDescription
                state.failed.store(true, ordering: .releasing)
            }
        }

        while true {
            let stopping = state.finishing.load(ordering: .acquiring)
            let width = state.channels.load(ordering: .acquiring)
            let rate = state.rate.load(ordering: .relaxed)
            var progressed = false
            if width > 0, !mixing {
                mixer = CaptureMixer(channels: width)
                mixing = true
            }
            let limit = state.maxSeconds * rate

            /// Moves what a source delivered into the mixer. A source that is closed before the pass has delivered
            /// all it will: drain it, then it is done.
            func drain(_ tracked: Tracked) {
                guard mixing else { return }
                let closed = stopping || tracked.source.isClosed
                while let block = tracked.source.ring.pop(into: chunkBuffer, limit: CaptureSource.scratchSamples) {
                    progressed = true
                    let frames = block.count / width
                    guard frames > 0 else { continue }
                    // No flush here: another source, drained later in this pass, can still hold blocks of that time.
                    mixer.add(start: block.start, frames: frames, samples: chunkBuffer)
                    tracked.end = max(tracked.end ?? 0, block.start + frames)
                }
                tracked.done = closed
                tracked.drained = true
            }

            for tracked in active { drain(tracked) }
            // New sources join after the drain: a block that this pass saw belongs to a graph that was there before
            // it, and the sources of such graphs are in the inbox by now.
            let fresh = inbox.withLock { sources in
                defer { sources = [] }
                return sources.map(Tracked.init)
            }
            active += fresh
            if stopping { for tracked in fresh { drain(tracked) } }
            if mixing {
                // The file may hold every frame that no live graph can still add to. A graph that has not delivered
                // yet starts at its tap's install time. A graph that trails far behind the newest block is stuck, and
                // does not hold the others back.
                let origin = state.originSeconds ?? 0
                let slack = Int(Self.slackSeconds * Double(rate))
                func birth(of source: CaptureSource) -> Int {
                    max(0, Int(((source.birth - origin) * Double(rate)).rounded()) - slack)
                }
                func live() -> [(tracked: Tracked, end: Int)] {
                    active.filter { !$0.done }.map { ($0, $0.end ?? birth(of: $0.source)) }
                }
                var sources = live()
                var newest = max(mixer.end, sources.map { $0.end }.max() ?? 0)
                // The sources were drained one after the other, so a source can trail the others only because its
                // newer blocks came after its drain. It counts as stuck only when a second read finds nothing new.
                var moved = true
                while moved {
                    moved = false
                    for entry in sources where entry.tracked.drained && entry.end < newest - Self.lagSeconds * rate {
                        let before = entry.tracked.end
                        drain(entry.tracked)
                        if entry.tracked.end != before { moved = true }
                    }
                    sources = live()
                    newest = max(mixer.end, sources.map { $0.end }.max() ?? 0)
                }
                // A source that no drain has read yet cannot be called stuck: a slow pass lets the others run ahead
                // of its birth while its first blocks wait in the ring.
                let holding = sources
                    .filter { !$0.tracked.drained || $0.end >= newest - Self.lagSeconds * rate }
                    .map { $0.end }
                let safe = mixer.end - Int(Self.holdSeconds * Double(rate))
                let frontier = stopping ? mixer.end : min(holding.min() ?? mixer.end, safe)
                flush(min(frontier, limit), width: width, rate: rate)
                for tracked in active where tracked.done { lostSamples += tracked.source.ring.dropped }
                active.removeAll { $0.done }
            }
            if !notified,
                state.capped.load(ordering: .acquiring) || state.formatChanged.load(ordering: .acquiring)
                    || failure != nil
            {
                notified = true
                onCap()
            }
            if stopping { break }
            if !progressed { try? await Task.sleep(for: .milliseconds(20)) }
        }
        let width = max(state.channels.load(ordering: .relaxed), 1)
        let sampleRate = state.rate.load(ordering: .relaxed)
        if let file {
            do {
                try file.seek(toOffset: 0)
                try file.write(contentsOf: CaptureWAV.header(rate: sampleRate, channels: width, frames: written))
                try file.close()
            } catch {
                failure = failure ?? error.localizedDescription
            }
        }
        if !notified, failure != nil { onCap() }
        return Result(
            url: file == nil ? nil : url, frames: written, rate: sampleRate,
            channels: state.channels.load(ordering: .relaxed), dropped: lostSamples / width + mixer.late,
            capped: state.capped.load(ordering: .relaxed), formatChanged: state.formatChanged.load(ordering: .relaxed),
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
            "Tap: final output of every graph that sounded, after the fade stage, the gain and the mixer, before "
                + "the hardware. The graphs sit on one time line: where they overlap they are summed, and where none "
                + "sounded the file is silent.",
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
        if result.dropped > 0 { lines.append("Warning: \(result.dropped) frames dropped, the file has holes.") }
        return lines.joined(separator: "\n") + "\n"
    }
}
