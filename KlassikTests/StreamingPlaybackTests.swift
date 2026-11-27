import AVFoundation
import Synchronization
import Testing

@testable import Klassik
@testable import KlassikEngine

/// The production decoder path of ADR 0060 against the fixture server: sound before the file is complete, the same
/// samples as a complete file, and exact joins. Bytes arrive in small chunks, so the decoder waits as on a slow line.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["KLASSIK_SERVER_URL"] != nil))
struct StreamingPlaybackTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "streaming-\(UUID().uuidString)")

    static func client() throws -> SubsonicClient {
        let env = ProcessInfo.processInfo.environment
        let url = try #require(env["KLASSIK_SERVER_URL"].flatMap(ServerCredentials.normalizedURL))
        return SubsonicClient(
            credentials: ServerCredentials(
                url: url, username: env["KLASSIK_USERNAME"] ?? "", password: env["KLASSIK_PASSWORD"] ?? ""))
    }

    static func album(_ search: String, named name: String) async throws -> (SubsonicClient, [Song]) {
        let client = try client()
        let found = try await client.searchAlbums(search).first { $0.name == name }
        return (client, try await client.album(id: try #require(found).id).songs)
    }

    static func resource(of song: Song, from client: SubsonicClient) async throws -> (Data, String?) {
        let (data, response) = try await URLSession.shared.data(from: client.streamURL(songID: song.id))
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        return (data, TrackTransfer.validator(of: http))
    }

    static func bytes(of song: Song, from client: SubsonicClient) async throws -> Data {
        try await resource(of: song, from: client).0
    }

    /// `url` turns on range requests, which the MP3 decoder needs for its look at the end of the file.
    func transfer(
        _ name: String, length: Int, url: URL? = nil, validator: String? = nil, capacity: Int64? = nil,
        budget: AudioStorageBudget? = nil
    ) -> TrackTransfer {
        let transfer = TrackTransfer(
            songID: name, partial: root.appending(path: "\(name).partial"), target: root.appending(path: name),
            url: url, capacity: capacity, budget: budget)
        transfer.begin(length: Int64(length), validator: validator)
        return transfer
    }

    /// Delivers `data` from `offset` in chunks, with a pause after each, then completes the transfer.
    static func feed(
        _ data: Data, from offset: Int = 0, into transfer: TrackTransfer, chunk: Int = 4096
    ) -> Task<Void, Never> {
        Task.detached {
            var position = offset
            while position < data.count, !Task.isCancelled {
                let end = min(position + chunk, data.count)
                let bytes = data.subdata(in: position..<end)
                // Storage backpressure must leave the cooperative executor available for cancellation and timers.
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        transfer.append(bytes)
                        continuation.resume()
                    }
                }
                position = end
                try? await Task.sleep(for: .milliseconds(1))
            }
            transfer.finish(nil)
        }
    }

    /// Decodes a whole streamed track, as the engine does, and returns its buffers.
    static func decode(_ transfer: TrackTransfer, suffix: String) async throws -> [AVAudioPCMBuffer] {
        try await Task.detached {
            let decoder = try StreamDecoder(transfer: transfer, suffix: suffix, cancelled: CancelFlag())
            var buffers: [AVAudioPCMBuffer] = []
            while let buffer = try decoder.read(frames: 11_025) { buffers.append(buffer) }
            return Buffers(buffers)
        }.value.buffers
    }

    struct Buffers: @unchecked Sendable {
        var buffers: [AVAudioPCMBuffer]
        init(_ buffers: [AVAudioPCMBuffer]) { self.buffers = buffers }
    }

    /// The decoder crosses repeated storage wraps without changing source samples or requesting a complete file.
    @Test(arguments: ["mp3", "flac"])
    func aBoundedWindowMatchesTheCompleteFilePrefix(suffix: String) async throws {
        let (client, songs) = try await Self.album("Early Playback", named: "Early Playback \(suffix.uppercased())")
        let song = try #require(songs.first)
        let (data, validator) = try await Self.resource(of: song, from: client)
        // The window exceeds measured opening reads and still forces repeated wraps.
        let capacity: Int64 = 1 << 20
        let budget = AudioStorageBudget(limit: capacity)
        let transfer = transfer(
            "bounded.\(suffix)", length: data.count, url: client.streamURL(songID: song.id), validator: validator,
            capacity: capacity, budget: budget)
        let feeder = Self.feed(data, into: transfer)
        defer {
            feeder.cancel()
            transfer.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        let decoded: Buffers = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let decoder = try StreamDecoder(transfer: transfer, suffix: suffix, cancelled: CancelFlag())
                    var buffers: [AVAudioPCMBuffer] = []
                    var remaining = Int(decoder.sampleRate * 40)
                    while remaining > 0 {
                        guard let buffer = try decoder.read(frames: AVAudioFrameCount(min(remaining, 11_025))) else {
                            throw StreamDecoder.Failure.prematureEnd(expected: Int64(remaining), actual: 0)
                        }
                        remaining -= Int(buffer.frameLength)
                        buffers.append(buffer)
                    }
                    continuation.resume(returning: Buffers(buffers))
                } catch { continuation.resume(throwing: error) }
            }
        }
        let actual = Self.samples(decoded.buffers)
        let whole = self.transfer("whole.\(suffix)", length: data.count)
        whole.append(data)
        whole.finish(nil)
        let unbounded = try await Self.prefix(of: whole, suffix: suffix, frames: actual.count)
        #expect(actual == unbounded, "The window changes no sample")
        let local = root.appending(path: "reference.\(suffix)")
        try data.write(to: local)
        let file = try AVAudioFile(forReading: local)
        let complete: Range<Int64>? =
            suffix == "mp3" ? MP3GaplessInfo.parse(data)?.playableRange(decodedLength: file.length) : 0..<file.length
        file.framePosition = complete?.lowerBound ?? 0
        let expected = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(actual.count)))
        try file.read(into: expected, frameCount: expected.frameCapacity)
        #expect(actual == Self.samples([expected]))
        // The stream cuts the same frames as the complete-file path, which keeps both on one timeline.
        let declared = try StreamDecoder(transfer: whole, suffix: suffix, cancelled: CancelFlag()).playable
        #expect(declared == complete)
        #expect(transfer.snapshot.available > capacity)
        #expect(transfer.snapshot.available < data.count)
        #expect(budget.storedBytes <= capacity)
        #expect(try Data(contentsOf: transfer.partial).count <= capacity)
        #expect(!transfer.hasCompleteFile)
        print(
            "bounded \(suffix): received=\(transfer.snapshot.available), stored=\(budget.storedBytes), frames=\(actual.count)"
        )
    }

    /// The first `frames` decoded frames of a stream.
    static func prefix(of transfer: TrackTransfer, suffix: String, frames: Int) async throws -> [Float] {
        let buffers = try await Task.detached {
            let decoder = try StreamDecoder(transfer: transfer, suffix: suffix, cancelled: CancelFlag())
            var buffers: [AVAudioPCMBuffer] = []
            var remaining = frames
            while remaining > 0, let buffer = try decoder.read(frames: AVAudioFrameCount(min(remaining, 11_025))) {
                remaining -= Int(buffer.frameLength)
                buffers.append(buffer)
            }
            return Buffers(buffers)
        }.value.buffers
        return Array(samples(buffers).prefix(frames))
    }

    static func samples(_ buffers: [AVAudioPCMBuffer]) -> [Float] {
        buffers.flatMap { UnsafeBufferPointer(start: $0.floatChannelData![0], count: Int($0.frameLength)) }
    }

    /// The samples that the complete-file path schedules for this file: AVAudioFile, cut to the playable range.
    func reference(_ data: Data, suffix: String) throws -> [Float] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let local = root.appending(path: "\(UUID().uuidString).\(suffix)")
        try data.write(to: local)
        let file = try AVAudioFile(forReading: local)
        let all = try GaplessTests.read(file)
        let range =
            suffix == "mp3"
            ? (MP3GaplessInfo.parse(data)?.playableRange(decodedLength: file.length) ?? 0..<file.length)
            : 0..<file.length
        return Array(all[Int(range.lowerBound)..<Int(range.upperBound)])
    }

    /// A complete transfer can still contain fewer decoded samples than its timing header declares.
    @Test func aDecoderEndBeforeTheDeclaredSampleCountFails() async throws {
        let (client, songs) = try await Self.album("Glide", named: "Glide in FLAC")
        let song = try #require(songs.first)
        var data = try await Self.bytes(of: song, from: client)
        let info = try #require(FLACStreamInfo.parse(Array(data.prefix(42))))
        let declared = info.totalSamples + 1000
        var packed = data[18..<26].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        packed = (packed & ~UInt64(0xF_FFFF_FFFF)) | UInt64(declared)
        for index in 0..<8 { data[18 + index] = UInt8(truncatingIfNeeded: packed >> (56 - index * 8)) }
        let transfer = self.transfer("truncated-samples.flac", length: data.count)
        transfer.append(data)
        transfer.finish(nil)
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: (any Error).self) {
            _ = try await Self.decode(transfer, suffix: "flac")
        }
    }

    // MARK: Early start

    /// The early-start gate of ADR 0060 on the production decoder: a resource above 100 MB gives its first PCM from
    /// its first half megabyte, within 500 ms. The MP3 decoder also reads the last 128 bytes, through a range.
    /// The first run also loads the system codec, so the gate takes the faster of two runs and reports both.
    @Test(arguments: ["mp3", "flac"])
    func firstSoundComesBeforeTheFileIsComplete(suffix: String) async throws {
        let (client, songs) = try await Self.album("Early Playback", named: "Early Playback \(suffix.uppercased())")
        let song = try #require(songs.first)
        let (data, validator) = try await Self.resource(of: song, from: client)
        #expect(data.count >= 100_000_000)
        let head = 512 * 1024
        var times: [Duration] = []
        for run in 0..<2 {
            let url = client.streamURL(songID: song.id)
            let transfer = self.transfer("early\(run).\(suffix)", length: data.count, url: url, validator: validator)
            transfer.append(data.prefix(head))
            let flag = CancelFlag()
            // A decoder that wants the whole file would wait; the flag ends that wait as a failure.
            let watchdog = Task.detached {
                try? await Task.sleep(for: .seconds(10))
                flag.set()
            }
            let started = ContinuousClock.now
            let first = try await Task.detached {
                let decoder = try StreamDecoder(transfer: transfer, suffix: suffix, cancelled: flag)
                let buffer = try decoder.read(frames: 11_025)
                return (Int(buffer?.frameLength ?? 0), decoder.playable, decoder.consumed)
            }.value
            times.append(started.duration(to: .now))
            watchdog.cancel()
            print("\(suffix) run \(run + 1): first PCM \(first.0) frames after \(times[run]), resource \(data.count)")
            #expect(first.0 > 0)
            #expect(first.2 < Int64(head), "Tail metadata must not consume the buffered audio estimate")
            #expect(transfer.snapshot.available == Int64(head))
            #expect(!transfer.snapshot.complete)
            #expect(first.1 != nil, "The header declares the length, so missing bytes never end the track")
            transfer.cancel()
        }
        if LatencyLimits.enforced {
            #expect(times.min()! < .milliseconds(500), "\(times)")
        }
        try? FileManager.default.removeItem(at: root)
    }

    private final class FirstSound: @unchecked Sendable {
        private let lock = NSLock()
        private var heard: ContinuousClock.Instant?
        var instant: ContinuousClock.Instant? { lock.withLock { heard } }
        func record(_ buffer: AVReadOnlyAudioPCMBuffer) {
            guard buffer.frameLength > 0, buffer.format.commonFormat == .pcmFormatFloat32 else { return }
            let audible = buffer.withUnsafeAudioBufferList { list in
                guard let samples = list.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
                    return false
                }
                return (0..<buffer.frameLength).contains { abs(samples[$0]) > 0.001 }
            }
            guard audible else { return }
            lock.withLock { if heard == nil { heard = .now } }
        }
    }

    /// A render tap establishes sound separately from decoder output and scheduling events.
    @MainActor @Test(arguments: ["mp3", "flac"])
    func theEngineRendersBeforeLargeResourcesFinish(suffix: String) async throws {
        let (client, songs) = try await Self.album("Early Playback", named: "Early Playback \(suffix.uppercased())")
        let song = try #require(songs.first)
        let (data, validator) = try await Self.resource(of: song, from: client)
        let transfer = self.transfer(
            "render.\(suffix)", length: data.count, url: client.streamURL(songID: song.id), validator: validator)
        let first = FirstSound()
        let engine = GaplessEngine(rendered: { first.record($0) }, fadeSeconds: 0)
        let bitrate = AudioBitrate.initial(song.playbackTrack)
        let chunk = 32 * 1024
        let interval = Double(chunk) * 8 / (bitrate * 2)
        let started = ContinuousClock.now
        let feeder = Task.detached {
            var offset = 0
            while offset < data.count, !Task.isCancelled {
                let end = min(offset + chunk, data.count)
                transfer.append(data.subdata(in: offset..<end))
                offset = end
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
            if !Task.isCancelled { transfer.finish(nil) }
        }
        defer {
            engine.discard()
            feeder.cancel()
            transfer.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        engine.load([song.playbackTrack], from: 0, offset: 0) { _ in .stream(transfer) }
        for _ in 0..<1000 where first.instant == nil { try await Task.sleep(for: .milliseconds(10)) }
        let rendered = try #require(first.instant, "The engine must render audible samples from partial bytes")
        let snapshot = transfer.snapshot
        print(
            "render \(suffix): elapsed=\(started.duration(to: rendered)), bytes=\(snapshot.available), resource=\(data.count), ratio=2"
        )
        #expect(!snapshot.complete)
        #expect(snapshot.available < Int64(data.count / 10))
        if LatencyLimits.enforced {
            #expect(started.duration(to: rendered) < .seconds(3))
        }
    }

    /// A read far past the arrived bytes asks the server for a validated range instead of waiting for the file.
    @Test func aRangeReadsTheEndOfTheFile() async throws {
        let (client, songs) = try await Self.album("Early Playback", named: "Early Playback MP3")
        let song = try #require(songs.first)
        let (data, validator) = try await Self.resource(of: song, from: client)
        #expect(validator != nil, "The fixture server must identify its range responses")
        let transfer = self.transfer(
            "tail.mp3", length: data.count, url: client.streamURL(songID: song.id), validator: validator)
        let tail = try await Task.detached {
            try TrackTransferTests.read(transfer, at: Int64(data.count - 128), count: 128)
        }.value
        #expect(tail == [UInt8](data.suffix(128)))
        #expect(transfer.snapshot.available == 0)
        transfer.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    /// The tap's samples, one array for each channel of the node format.
    private final class RenderedAudio: Sendable {
        private let storage = Mutex<[[Float]]>([])
        var samples: [Float] { channel(0) }
        var channels: Int { storage.withLock { $0.count } }

        func channel(_ index: Int) -> [Float] {
            storage.withLock { $0.indices.contains(index) ? $0[index] : [] }
        }

        func record(_ buffer: AVReadOnlyAudioPCMBuffer) {
            guard buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved else { return }
            let frames = Int(buffer.frameLength)
            buffer.withUnsafeAudioBufferList { list in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
                storage.withLock { channels in
                    if channels.isEmpty { channels = Array(repeating: [], count: buffers.count) }
                    guard channels[0].count < 1_000_000 else { return }
                    for (index, audio) in buffers.enumerated() where index < channels.count {
                        guard let source = audio.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        channels[index].append(contentsOf: UnsafeBufferPointer(start: source, count: frames))
                    }
                }
            }
        }
    }

    /// Writes a 32-bit float WAV file with `channels[n]` as channel n.
    func wav(_ name: String, rate: Double, channels: [[Float]]) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels.count)))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(channels[0].count)))
        buffer.frameLength = buffer.frameCapacity
        for (index, samples) in channels.enumerated() {
            for (frame, sample) in samples.enumerated() { buffer.floatChannelData![index][frame] = sample }
        }
        let url = root.appending(path: name)
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
        return url
    }

    static func tone(_ count: Int, rate: Double, from start: Int = 0) -> [Float] {
        (start..<(start + count)).map { Float(sin(Double($0) * 2 * .pi * 440 / rate) * 0.25) }
    }

    /// Plays local files through the real engine until the last one ends or the engine fails.
    @MainActor private func render(
        _ files: [URL], output: RenderedAudio, gainNode: Bool = true, decibels: Float = 0
    ) async throws -> [String] {
        let events = Events()
        let engine = GaplessEngine(rendered: { output.record($0) }, gainNode: gainNode, fadeSeconds: 0)
        engine.setGain(decibels)
        engine.onEvent = { event in
            switch event {
            case .movementEnded(let index): events.log.append("end \(index)")
            case .failed(let text), .problem(let text): events.log.append("failed \(text)")
            case .serverFailed(let trouble): events.log.append("failed server \(trouble)")
            default: break
            }
        }
        defer { engine.discard() }
        let songs = files.indices.map { Song(id: String($0), title: "Tone", duration: 1, suffix: "wav") }
        engine.load(songs.map(\.playbackTrack), from: 0, offset: 0) { .file(files[Int($0.id)!]) }
        let last = "end \(files.count - 1)"
        for _ in 0..<500 where !events.log.contains(last) && !events.log.contains(where: { $0.hasPrefix("failed") }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        // The tap delivers whole blocks, so its last block can arrive after the end event.
        try await Task.sleep(for: .milliseconds(600))
        return events.log
    }

    /// A host that builds the engine without a gain node plays at the file's level, whatever gain the session sets.
    @MainActor @Test func anEngineWithoutAGainNodeIgnoresTheGain() async throws {
        let count = 22_050
        let file = try wav("level.wav", rate: 44_100, channels: [Self.tone(count, rate: 44_100)])
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = RenderedAudio()
        _ = try await render([file], output: plain, gainNode: false, decibels: -20)
        let leveled = RenderedAudio()
        _ = try await render([file], output: leveled, decibels: -20)
        #expect(plain.channel(0).map { abs($0) }.max() ?? 0 > 0.2, "Without the node the tone keeps its level")
        #expect(leveled.channel(0).map { abs($0) }.max() ?? 1 < 0.05, "With the node the gain lowers it")
    }

    /// A server that goes away during playback pauses quietly: no notice, only the one server status.
    @MainActor @Test func aServerThatGoesAwayPausesQuietly() async throws {
        let (client, songs) = try await Self.album("Glide", named: "Glide in FLAC")
        let song = try #require(songs.first)
        let data = try await Self.bytes(of: song, from: client)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults,
            transport: { _, _, transfer in
                transfer.begin(length: Int64(data.count), validator: nil)
                Task.detached {
                    transfer.append(data.prefix(data.count / 3))
                    try? await Task.sleep(for: .milliseconds(500))
                    transfer.finish(.truncated)
                }
            })
        let player = PlaybackSession(engine: GaplessEngine(), store: store, defaults: defaults)
        player.server = InMemoryServer()
        defer {
            player.stop()
            store.clearAll()
            try? FileManager.default.removeItem(at: root)
        }
        let recording = WorkIndex.Recording(id: "recording", album: "Fixture", songs: [song])
        let work = WorkIndex.Work(
            id: "work", title: "Fixture", composer: "Fixture", isTagged: false, recordings: [recording])
        player.play(QueueItem(work: work, recording: recording))
        for _ in 0..<200 where !player.isPaused { try await Task.sleep(for: .milliseconds(50)) }
        #expect(player.isPaused)
        #expect(player.error == nil)
        #expect(player.playbackTrouble == .unreachable)
    }

    /// A server that stops sending shows no slow-connection line: the line is for a slow transfer only.
    @MainActor @Test func aStalledServerShowsNoSlowLine() async throws {
        let (client, songs) = try await Self.album("Glide", named: "Glide in FLAC")
        let song = try #require(songs.first)
        let data = try await Self.bytes(of: song, from: client)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults,
            transport: { _, _, transfer in
                transfer.begin(length: Int64(data.count), validator: nil)
                transfer.append(data.prefix(4096))
            })
        let player = PlaybackSession(engine: GaplessEngine(), store: store, defaults: defaults)
        player.server = InMemoryServer()
        defer {
            player.stop()
            store.clearAll()
            try? FileManager.default.removeItem(at: root)
        }
        let recording = WorkIndex.Recording(id: "recording", album: "Fixture", songs: [song])
        let work = WorkIndex.Work(
            id: "work", title: "Fixture", composer: "Fixture", isTagged: false, recordings: [recording])
        player.play(QueueItem(work: work, recording: recording))
        try await Task.sleep(for: .milliseconds(2_500))
        #expect(player.slowLine == nil)
    }

    /// Both recordings share the production node. The tap measures each join against the continuous fixture glide.
    @MainActor
    @Test(arguments: [("Mendelssohn", "Mendelssohn: Violin Concerto", "mp3"), ("Glide", "Glide in FLAC", "flac")])
    func renderedJoinsSpanRecordings(search: String, name: String, suffix: String) async throws {
        let (client, songs) = try await Self.album(search, named: name)
        var resources: [String: Data] = [:]
        for song in songs { resources[song.id] = try await Self.bytes(of: song, from: client) }
        let data = resources
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults,
            transport: { song, _, transfer in
                let bytes = data[song.id]!
                transfer.begin(length: Int64(bytes.count), validator: nil)
                _ = Self.feed(bytes, into: transfer)
            })
        let output = RenderedAudio()
        let engine = GaplessEngine(rendered: { output.record($0) }, manualRendering: true, fadeSeconds: 0)
        let player = PlaybackSession(engine: engine, store: store, defaults: defaults)
        player.server = InMemoryServer()
        player.leveling = .off
        let recordings = [Array(songs.prefix(2)), Array(songs.suffix(1))].enumerated().map { index, tracks in
            let recording = WorkIndex.Recording(id: "recording-\(index)", album: "Fixture", songs: tracks)
            let work = WorkIndex.Work(
                id: "work-\(index)", title: "Fixture", composer: "Fixture", isTagged: false, recordings: [recording])
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
        let rendered = output.samples
        #expect(player.error == nil, "error=\(String(describing: player.error))")
        let expected = GaplessTests.movementSamples.reduce(0, +)
        let state = "rendered=\(rendered.count) of \(expected)"
        #expect(player.queueEnded, Comment(rawValue: state))
        let firstAudible = try #require(rendered.firstIndex { abs($0) > 0.01 })
        let start = firstAudible + GaplessTests.alignment(rendered, at: firstAudible + 2048, referenceAt: 2048)
        var join = 0
        let shifts = GaplessTests.movementSamples.dropLast().map { length in
            join += length
            return GaplessTests.alignment(rendered, at: start + join + 256, referenceAt: join + 256)
        }
        print("rendered \(suffix) recording joins: start=\(start), frames=\(rendered.count), shifts=\(shifts)")
        #expect(
            shifts == [0, 0],
            "shifts=\(shifts) start=\(start) frames=\(rendered.count) joins=\(GaplessTests.movementSamples)")
    }

    // MARK: Sample-exact output

    /// Streamed decoding gives the samples that the complete-file path plays, encoder delay and padding cut.
    @Test(arguments: [("Mendelssohn", "Mendelssohn: Violin Concerto", "mp3"), ("Glide", "Glide in FLAC", "flac")])
    func streamedTracksMatchTheCompleteFile(search: String, name: String, suffix: String) async throws {
        let (client, songs) = try await Self.album(search, named: name)
        #expect(songs.count == GaplessTests.movementSamples.count)
        for (index, song) in songs.enumerated() {
            let data = try await Self.bytes(of: song, from: client)
            let transfer = self.transfer("\(index).\(suffix)", length: data.count)
            let feeding = Self.feed(data, into: transfer)
            let streamed = Self.samples(try await Self.decode(transfer, suffix: suffix))
            await feeding.value
            let expected = try reference(data, suffix: suffix)
            #expect(streamed.count == GaplessTests.movementSamples[index], "Movement \(index + 1)")
            #expect(streamed == expected, "Movement \(index + 1)")
        }
        try? FileManager.default.removeItem(at: root)
    }

    /// Streamed movements back to back join without a gap: the glide runs on across each join.
    @Test(arguments: [("Mendelssohn", "Mendelssohn: Violin Concerto", "mp3"), ("Glide", "Glide in FLAC", "flac")])
    func streamedMovementsJoinWithoutGap(search: String, name: String, suffix: String) async throws {
        let (client, songs) = try await Self.album(search, named: name)
        var joined: [Float] = []
        for (index, song) in songs.enumerated() {
            let data = try await Self.bytes(of: song, from: client)
            let transfer = self.transfer("join\(index).\(suffix)", length: data.count)
            let feeding = Self.feed(data, into: transfer)
            joined += Self.samples(try await Self.decode(transfer, suffix: suffix))
            await feeding.value
        }
        let start = GaplessTests.alignment(joined, at: 2048, referenceAt: 2048)
        var join = 0
        let shifts = GaplessTests.movementSamples.dropLast().map { length in
            join += length
            return GaplessTests.alignment(joined, at: start + join + 256, referenceAt: join + 256)
        }
        #expect(shifts == Array(repeating: 0, count: shifts.count), "start \(start), shifts \(shifts)")
        try? FileManager.default.removeItem(at: root)
    }

    /// Pause can reach the engine while its first callback waits. Resuming must still start that same load.
    @MainActor @Test func pauseBeforeTheFirstBytesKeepsTheLoad() async throws {
        let (client, songs) = try await Self.album("Glide", named: "Glide in FLAC")
        let song = try #require(songs.first)
        let data = try await Self.bytes(of: song, from: client)
        let transfer = self.transfer("paused.flac", length: data.count)
        let events = Events()
        let engine = GaplessEngine()
        engine.onEvent = { event in
            if case .movementEnded(let index) = event { events.log.append("end \(index)") }
            if case .failed(let text) = event { events.log.append("failed \(text)") }
        }
        engine.load([song.playbackTrack], from: 0, offset: 0) { _ in .stream(transfer) }
        defer { engine.discard() }
        try await Task.sleep(for: .milliseconds(200))
        engine.pause()
        transfer.append(data)
        transfer.finish(nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(events.log.isEmpty)
        try engine.resume()
        for _ in 0..<100 where !events.log.contains("end 0") { try await Task.sleep(for: .milliseconds(100)) }
        #expect(events.log == ["end 0"])
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor final class Events {
        var log: [String] = []
        var waits: [PlaybackWait] = []
    }

    /// The real engine plays three streamed movements in order. A stall in the second one makes the node run dry;
    /// the engine waits quietly, reports the slow connection, and plays on from the next sample.
    @MainActor @Test func theEngineStartsFromAStreamAndRecoversFromAStall() async throws {
        let (client, songs) = try await Self.album("Glide", named: "Glide in FLAC")
        var transfers: [String: TrackTransfer] = [:]
        var feeders: [Task<Void, Never>] = []
        for (index, song) in songs.enumerated() {
            let data = try await Self.bytes(of: song, from: client)
            let transfer = self.transfer("engine\(index).flac", length: data.count)
            transfers[song.id] = transfer
            if index == 1 {
                let half = data.count / 2
                transfer.append(data.prefix(half))
                feeders.append(
                    Task.detached {
                        // A trickle far below the bitrate: the node runs dry on a slow connection, not a dead one.
                        var position = half
                        let stall = ContinuousClock.now + .seconds(7)
                        while ContinuousClock.now < stall, !Task.isCancelled {
                            transfer.append(data.subdata(in: position..<(position + 512)))
                            position += 512
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        await Self.feed(data, from: position, into: transfer).value
                    })
            } else {
                feeders.append(Self.feed(data, into: transfer))
            }
        }
        let events = Events()
        let engine = GaplessEngine()
        engine.onEvent = { event in
            switch event {
            case .waiting(let wait):
                events.log.append(wait == nil ? "sound" : "wait")
                if let wait { events.waits.append(wait) }
            case .movementEnded(let movement): events.log.append("end \(movement)")
            case .failed(let text), .problem(let text): events.log.append("failed \(text)")
            case .serverFailed(let trouble): events.log.append("failed server \(trouble)")
            default: break
            }
        }
        let streams = transfers
        engine.load(songs.map(\.playbackTrack), from: 0, offset: 0) { song in .stream(streams[song.id]!) }
        defer { engine.discard() }
        for _ in 0..<300 where !events.log.contains("end 2") { try await Task.sleep(for: .milliseconds(100)) }
        for feeder in feeders { feeder.cancel() }
        #expect(events.log.filter { $0.hasPrefix("end") } == ["end 0", "end 1", "end 2"], "\(events.log)")
        #expect(!events.log.contains { $0.hasPrefix("failed") }, "\(events.log)")
        #expect(events.log.first == "wait", "\(events.log)")
        #expect(events.waits.first?.kind == .start)
        #expect(events.waits.contains { $0.kind == .resume && $0.slow }, "\(events.waits)")
        // Each movement keeps its exact length on the timeline, also across the dry spell.
        for (index, length) in GaplessTests.movementSamples.enumerated() {
            #expect(engine.duration(of: index) == Double(length) / GaplessTests.sampleRate)
        }
        try? FileManager.default.removeItem(at: root)
    }

    /// The next recording opens while the current one still decodes. A slow open then finishes before the join
    /// and cannot run the node dry. The tail of movement 1 is withheld, so only an early open passes.
    @MainActor @Test func theNextRecordingOpensBeforeTheCurrentOneEnds() async throws {
        let (client, songs) = try await Self.album("Glide", named: "Glide in FLAC")
        var transfers: [String: TrackTransfer] = [:]
        var tail: (data: Data, offset: Int)?
        var feeders: [Task<Void, Never>] = []
        for (index, song) in songs.enumerated() {
            let data = try await Self.bytes(of: song, from: client)
            let transfer = self.transfer("early\(index).flac", length: data.count)
            transfers[song.id] = transfer
            if index == 0 {
                // Four fifths hold more audio than the lookahead of the engine.
                let held = data.count * 4 / 5
                transfer.append(data.prefix(held))
                tail = (data, held)
            } else {
                feeders.append(Self.feed(data, into: transfer))
            }
        }
        let events = Events()
        let engine = GaplessEngine()
        engine.onEvent = { event in
            switch event {
            case .movementEnded(let movement): events.log.append("end \(movement)")
            case .failed(let text), .problem(let text): events.log.append("failed \(text)")
            case .serverFailed(let trouble): events.log.append("failed server \(trouble)")
            default: break
            }
        }
        let streams = transfers
        let opens = OpenLog()
        engine.load(songs.map(\.playbackTrack), from: 0, offset: 0) { song in
            opens.ids.append(song.id)
            // A recording that opens slowly, as under load.
            if song.id != songs[0].id { try await Task.sleep(for: .milliseconds(300)) }
            return .stream(streams[song.id]!)
        }
        defer {
            engine.discard()
            for feeder in feeders { feeder.cancel() }
            try? FileManager.default.removeItem(at: root)
        }
        for _ in 0..<100 where !opens.ids.contains(songs[1].id) { try await Task.sleep(for: .milliseconds(50)) }
        #expect(opens.ids == [songs[0].id, songs[1].id], "Movement 2 opened late: \(opens.ids)")
        let rest = try #require(tail)
        feeders.append(Self.feed(rest.data, from: rest.offset, into: transfers[songs[0].id]!))
        for _ in 0..<300 where !events.log.contains("end 2") { try await Task.sleep(for: .milliseconds(100)) }
        #expect(events.log.filter { $0.hasPrefix("end") } == ["end 0", "end 1", "end 2"], "\(events.log)")
        #expect(!events.log.contains { $0.hasPrefix("failed") }, "\(events.log)")
    }

    @MainActor final class OpenLog {
        var ids: [String] = []
    }
}
