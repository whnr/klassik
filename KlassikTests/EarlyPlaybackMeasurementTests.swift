import AVFoundation
import Synchronization
import Testing

@testable import Klassik

/// The ADR 0060 measurements against the fixture server: first sound and starvation across throughput ratios, a
/// seek inside a stream that is still arriving, and the ReplayGain change at a recording boundary.
/// Each test prints one report line per case; the build report keeps them.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["KLASSIK_SERVER_URL"] != nil))
struct EarlyPlaybackMeasurementTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "measure-\(UUID().uuidString)")

    /// What the render tap heard, and when it first heard sound.
    final class Tap: Sendable {
        private struct State {
            var heard: ContinuousClock.Instant?
            var samples: [Float] = []
        }

        private let state = Mutex(State())
        private let keep: Bool

        init(keep: Bool = false) { self.keep = keep }

        var heard: ContinuousClock.Instant? { state.withLock { $0.heard } }
        var samples: [Float] { state.withLock { $0.samples } }

        func record(_ buffer: AVReadOnlyAudioPCMBuffer) {
            guard buffer.format.commonFormat == .pcmFormatFloat32 else { return }
            buffer.withUnsafeAudioBufferList { list in
                guard let source = list.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else { return }
                let frames = UnsafeBufferPointer(start: source, count: Int(buffer.frameLength))
                state.withLock { state in
                    if state.heard == nil, frames.contains(where: { abs($0) > 0.001 }) { state.heard = .now }
                    if keep, state.samples.count < 2_000_000 { state.samples.append(contentsOf: frames) }
                }
            }
        }
    }

    /// The engine's own events: sound allowed, waits, ends and failures, with their times.
    @MainActor final class Timeline {
        var sounds: [ContinuousClock.Instant] = []
        var waits: [(at: ContinuousClock.Instant, wait: PlaybackWait)] = []
        var ended: [Int] = []
        var failures: [String] = []

        func observe(_ engine: GaplessEngine) {
            engine.onEvent = { [weak self] event in
                guard let self else { return }
                switch event {
                case .waiting(let wait):
                    if let wait { waits.append((.now, wait)) } else { sounds.append(.now) }
                case .movementEnded(let index): ended.append(index)
                case .failed(let text), .problem(let text): failures.append(text)
                default: break
                }
            }
        }
    }

    /// Delivers `data` at `ratio` times `bitrate` after `latency`. Seeded jitter moves each chunk by up to 40 % of
    /// its interval without changing the mean rate. About sixteen chunks arrive per second.
    static func pace(
        _ data: Data, into transfer: TrackTransfer, bitrate: Double, ratio: Double, latency: Duration
    ) -> Task<Void, Never> {
        let rate = bitrate * ratio / 8
        let chunk = max(1024, Int(rate / 16))
        return Task.detached {
            var seed: UInt64 = 0x5EED
            try? await Task.sleep(for: latency)
            let started = ContinuousClock.now
            var offset = 0
            while offset < data.count, !Task.isCancelled {
                let end = min(offset + chunk, data.count)
                let bytes = data.subdata(in: offset..<end)
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        transfer.append(bytes)
                        continuation.resume()
                    }
                }
                offset = end
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let jitter = (Double(seed >> 11) / Double(1 << 53) - 0.5) * 0.8 * Double(chunk) / rate
                let due = started + .seconds(Double(offset) / rate + jitter)
                try? await Task.sleep(until: due, clock: .continuous)
            }
            if !Task.isCancelled { transfer.finish(nil) }
        }
    }

    func stream(_ name: String, data: Data, validator: String?, url: URL?) -> TrackTransfer {
        let transfer = TrackTransfer(
            songID: name, partial: root.appending(path: "\(name).partial"), target: root.appending(path: name),
            url: url)
        transfer.begin(length: Int64(data.count), validator: validator)
        return transfer
    }

    static func seconds(_ duration: Duration) -> Double { duration / .seconds(1) }

    // MARK: Throughput ratios

    /// ADR 0060 runs ratios 4, 2, 1, 0.75 and 0.5 with latency and jitter. Each run reports the chosen target, the
    /// delay from threshold readiness to rendered sound, the bytes at first sound, and starvation against the
    /// predicted exhaustion of the bounded buffer. Ratio 2 also changes the network path during playback.
    @MainActor @Test func throughputRatiosFollowTheStartRule() async throws {
        let (client, songs) = try await StreamingPlaybackTests.album("Early Playback", named: "Early Playback MP3")
        let song = try #require(songs.first)
        let (data, validator) = try await StreamingPlaybackTests.resource(of: song, from: client)
        #expect(data.count >= 100_000_000)
        // The fixture is constant 320 kbit/s, the same as the MP3 estimate before packet timing.
        let bitrate = AudioBitrate.initial(song)
        let duration = Double(data.count) * 8 / bitrate
        defer { try? FileManager.default.removeItem(at: root) }
        for ratio in [4.0, 2.0, 1.0, 0.75, 0.5] {
            try await measure(
                ratio: ratio, song: song, data: data, validator: validator, url: client.streamURL(songID: song.id),
                bitrate: bitrate, duration: duration)
        }
    }

    @MainActor private func measure(
        ratio: Double, song: Song, data: Data, validator: String?, url: URL, bitrate: Double, duration: Double
    ) async throws {
        let transfer = stream("ratio-\(ratio).mp3", data: data, validator: validator, url: url)
        let tap = Tap()
        let engine = GaplessEngine(rendered: { tap.record($0) })
        let timeline = Timeline()
        timeline.observe(engine)
        let target = try #require(
            StartThreshold.seconds(bitrate: bitrate, throughput: bitrate * ratio, remaining: duration))
        let requested = ContinuousClock.now
        let feeder = Self.pace(data, into: transfer, bitrate: bitrate, ratio: ratio, latency: .milliseconds(150))
        engine.load([song], from: 0, offset: 0) { _ in .stream(transfer) }
        func cleanUp() async {
            engine.discard()
            feeder.cancel()
            transfer.cancel()
            await feeder.value
        }
        let startLimit = Duration.seconds(target / ratio + 15)
        while tap.heard == nil, timeline.failures.isEmpty, requested.duration(to: .now) < startLimit {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let heard = tap.heard, let ready = timeline.sounds.first else {
            await cleanUp()
            Issue.record("ratio \(ratio): no sound, failures \(timeline.failures)")
            return
        }
        let atSound = transfer.snapshot
        let measured = transfer.throughput
        if ratio == 2 { transfer.restartMeasurement() }
        // At r < 1 the buffer drains at 1 - r seconds per second, from the target it held at first sound.
        let predicted = ratio < 1 ? target / (1 - ratio) : nil
        let observe = Duration.seconds(predicted.map { $0 * 1.5 + 3 } ?? 4)
        let recover = ratio == 0.75
        func starvation() -> ContinuousClock.Instant? {
            timeline.waits.first { $0.at > ready && $0.wait.kind == .resume }?.at
        }
        func recovery() -> ContinuousClock.Instant? {
            guard let starved = starvation() else { return nil }
            return timeline.sounds.first { $0 > starved }
        }
        let limit = observe + (recover ? .seconds(target / ratio + 15) : .zero)
        // Decoded audio stays bounded; the rest of the buffer waits encoded in the transfer.
        var peak = 0.0
        while timeline.failures.isEmpty, heard.duration(to: .now) < limit {
            peak = max(peak, engine.bufferedSeconds ?? 0)
            if ratio < 1, starvation() != nil, !recover || recovery() != nil { break }
            if ratio >= 1, heard.duration(to: .now) >= observe { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let starved = starvation()
        let recovered = recovery()
        await cleanUp()
        let starvedAfter = starved.map { Self.seconds(heard.duration(to: $0)) }
        var refill: Double?
        if let starved, let recovered { refill = Self.seconds(starved.duration(to: recovered)) }
        let report = [
            "ratio=\(ratio)", "target=\(target)s",
            "request-to-sound=\(Self.seconds(requested.duration(to: heard)))s",
            "ready-to-render=\(Self.seconds(ready.duration(to: heard)))s",
            "bytes-at-sound=\(atSound.available)", "resource=\(data.count)",
            "throughput=\(measured.map { String(Int($0)) } ?? "none")", "bitrate=\(Int(bitrate))",
            "predicted-exhaustion=\(predicted.map { "\($0)s" } ?? "none")",
            "peak-decoded=\(peak)s", "starvation=\(starvedAfter.map { "\($0)s" } ?? "none")",
            "recovery=\(refill.map { "\($0)s" } ?? "none")",
        ]
        print("throughput matrix: " + report.joined(separator: ", "))
        #expect(timeline.failures.isEmpty, "ratio \(ratio): \(timeline.failures)")
        #expect(!atSound.complete, "ratio \(ratio): sound must come before the download completes")
        #expect(atSound.available < Int64(data.count / 10), "ratio \(ratio)")
        #expect(peak <= GaplessEngine.aheadSeconds + GaplessEngine.chunkSeconds, "ratio \(ratio): decoded audio")
        if ratio >= 2 {
            #expect(ready.duration(to: heard) < .milliseconds(500), "ratio \(ratio)")
            #expect(starved == nil, "ratio \(ratio): a sustainable connection must not starve")
        }
        if let predicted {
            let offset = try #require(starvedAfter, "ratio \(ratio): a bounded buffer must run dry at r < 1")
            #expect(offset >= predicted * 0.6, "ratio \(ratio): the buffer ran dry before its prediction")
            if recover { #expect(recovered != nil, "ratio \(ratio): playback must continue after a refill") }
        }
    }

    // MARK: Seeks

    /// A seek inside a stream that is still arriving starts at the chosen sample and joins the next movement
    /// without inserted or missing frames.
    @MainActor
    @Test(arguments: [("Mendelssohn", "Mendelssohn: Violin Concerto", "mp3"), ("Glide", "Glide in FLAC", "flac")])
    func aSeekInsideAStreamJoinsExactly(search: String, name: String, suffix: String) async throws {
        let (client, songs) = try await StreamingPlaybackTests.album(search, named: name)
        let played = Array(songs.prefix(2))
        var transfers: [String: TrackTransfer] = [:]
        var feeders: [Task<Void, Never>] = []
        for (index, song) in played.enumerated() {
            let (data, validator) = try await StreamingPlaybackTests.resource(of: song, from: client)
            let transfer = stream(
                "seek\(index).\(suffix)", data: data, validator: validator, url: client.streamURL(songID: song.id))
            transfers[song.id] = transfer
            feeders.append(StreamingPlaybackTests.feed(data, into: transfer))
        }
        let tap = Tap(keep: true)
        let engine = GaplessEngine(rendered: { tap.record($0) })
        let timeline = Timeline()
        timeline.observe(engine)
        let streams = transfers
        defer {
            engine.discard()
            for feeder in feeders { feeder.cancel() }
            for transfer in streams.values { transfer.cancel() }
            try? FileManager.default.removeItem(at: root)
        }
        let seconds = 1.0
        engine.load(played, from: 0, offset: seconds) { .stream(streams[$0.id]!) }
        for _ in 0..<300 where !timeline.ended.contains(1) && timeline.failures.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(timeline.failures.isEmpty, "\(timeline.failures)")
        #expect(timeline.ended == [0, 1])
        let rendered = tap.samples
        let first = try #require(rendered.firstIndex { abs($0) > 0.01 })
        let skip = Int(seconds * GaplessTests.sampleRate)
        let seek = GaplessTests.alignment(rendered, at: first + 2048, referenceAt: skip + 2048)
        let join = GaplessTests.movementSamples[0]
        let shift = GaplessTests.alignment(
            rendered, at: first + seek + (join - skip) + 256, referenceAt: join + 256)
        print("stream seek \(suffix): first=\(first), seek-shift=\(seek), join-shift=\(shift)")
        #expect(shift == 0, "The join after a seek must keep every frame")
        #expect(engine.duration(of: 1) == Double(GaplessTests.movementSamples[1]) / GaplessTests.sampleRate)
    }

    // MARK: ReplayGain

    /// The gain stage follows the audible recording. The report gives how far after the join the new gain starts;
    /// the join itself keeps every frame (ADR 0007, ADR 0060).
    @MainActor @Test func theRecordingGainChangesAtTheJoin() async throws {
        let (client, songs) = try await StreamingPlaybackTests.album("Glide", named: "Glide in FLAC")
        var resources: [String: Data] = [:]
        for song in songs { resources[song.id] = try await StreamingPlaybackTests.bytes(of: song, from: client) }
        let data = resources
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults,
            transport: { song, _, transfer in
                let bytes = data[song.id]!
                transfer.begin(length: Int64(bytes.count), validator: nil)
                _ = StreamingPlaybackTests.feed(bytes, into: transfer)
            })
        let tap = Tap(keep: true)
        let engine = GaplessEngine(rendered: { tap.record($0) })
        let player = PlaybackSession(engine: engine, store: store, defaults: defaults)
        player.server = InMemoryServer()
        player.leveling = .album
        let quiet = -6.0
        func leveled(_ song: Song, _ gain: Double) -> Song {
            var song = song
            song.replayGain = Song.ReplayGain(albumGain: gain)
            return song
        }
        let groups = [songs.prefix(2).map { leveled($0, quiet) }, songs.suffix(1).map { leveled($0, 0) }]
        let recordings = groups.enumerated().map { index, tracks in
            let recording = WorkIndex.Recording(id: "gain-\(index)", album: "Fixture", songs: tracks)
            let work = WorkIndex.Work(
                id: "gain-work-\(index)", title: "Fixture", composer: "Fixture", isTagged: false,
                recordings: [recording])
            return QueueItem(work: work, recording: recording)
        }
        defer {
            player.stop()
            store.clearAll()
            try? FileManager.default.removeItem(at: root)
        }
        player.play(queue: recordings)
        for _ in 0..<1500 where !player.queueEnded && player.error == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(player.error == nil)
        #expect(player.queueEnded)
        let rendered = tap.samples
        let first = try #require(rendered.firstIndex { abs($0) > 0.01 })
        let start = first + GaplessTests.alignment(rendered, at: first + 2048, referenceAt: 2048)
        let join = GaplessTests.movementSamples[0] + GaplessTests.movementSamples[1]
        let shift = GaplessTests.alignment(rendered, at: start + join + 22_050, referenceAt: join + 22_050)
        func level(_ frames: Range<Int>) -> Double {
            let pairs = frames.filter { start + $0 < rendered.count }
            let signal = pairs.reduce(0.0) { $0 + Double(rendered[start + $1] * rendered[start + $1]) }
            let reference = pairs.reduce(0.0) { $0 + Double(GaplessTests.glide[$1] * GaplessTests.glide[$1]) }
            return reference > 0 ? 20 * log10((signal / reference).squareRoot()) : -.infinity
        }
        let before = level((join - 13_230)..<(join - 4_410))
        let after = level((join + 13_230)..<(join + 22_050))
        // The first 10 ms window after the join whose level is nearer the new gain than the old one.
        let step = 441
        let lag = stride(from: join, to: join + 22_050, by: step).first { frame in
            level(frame..<(frame + step)) > quiet / 2
        }.map { Double($0 - join) / GaplessTests.sampleRate }
        let delay = lag.map { "\($0)s" } ?? "none"
        print("replaygain join: before=\(before)dB, after=\(after)dB, lag=\(delay), shift=\(shift)")
        #expect(shift == 0, "The recording join must keep every frame")
        #expect(abs(before - quiet) < 0.5)
        #expect(abs(after) < 0.5)
        let measuredLag = try #require(lag, "The new recording must reach its own gain")
        #expect(measuredLag < 0.25, "The new recording's gain must follow its first audible samples")
    }
}
