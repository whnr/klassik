import AVFoundation
import Testing

@testable import Klassik

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

    static func bytes(of song: Song, from client: SubsonicClient) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: client.streamURL(songID: song.id))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        return data
    }

    /// `url` turns on range requests, which the MP3 decoder needs for its look at the end of the file.
    func transfer(_ name: String, length: Int, url: URL? = nil) -> TrackTransfer {
        let transfer = TrackTransfer(
            songID: name, partial: root.appending(path: "\(name).partial"), target: root.appending(path: name),
            url: url)
        transfer.begin(length: Int64(length), validator: nil)
        return transfer
    }

    /// Delivers `data` from `offset` in chunks, with a pause after each, then completes the transfer.
    static func feed(
        _ data: Data, from offset: Int = 0, into transfer: TrackTransfer, chunk: Int = 4096
    ) -> Task<Void, Never> {
        Task.detached {
            var position = offset
            while position < data.count {
                let end = min(position + chunk, data.count)
                transfer.append(data.subdata(in: position..<end))
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

    // MARK: Early start

    /// The early-start gate of ADR 0060 on the production decoder: a resource above 100 MB gives its first PCM from
    /// its first half megabyte, within 500 ms. The MP3 decoder also reads the last 128 bytes, through a range.
    /// The first run also loads the system codec, so the gate takes the faster of two runs and reports both.
    @Test(arguments: ["mp3", "flac"])
    func firstSoundComesBeforeTheFileIsComplete(suffix: String) async throws {
        let (client, songs) = try await Self.album("Early Playback", named: "Early Playback \(suffix.uppercased())")
        let song = try #require(songs.first)
        let data = try await Self.bytes(of: song, from: client)
        #expect(data.count >= 100_000_000)
        let head = 512 * 1024
        var times: [Duration] = []
        for run in 0..<2 {
            let url = client.streamURL(songID: song.id)
            let transfer = self.transfer("early\(run).\(suffix)", length: data.count, url: url)
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
                return (Int(buffer?.frameLength ?? 0), decoder.playable)
            }.value
            times.append(started.duration(to: .now))
            watchdog.cancel()
            print("\(suffix) run \(run + 1): first PCM \(first.0) frames after \(times[run]), resource \(data.count)")
            #expect(first.0 > 0)
            #expect(transfer.snapshot.available == Int64(head))
            #expect(!transfer.snapshot.complete)
            #expect(first.1 != nil, "The header declares the length, so missing bytes never end the track")
            transfer.cancel()
        }
        #expect(times.min()! < .milliseconds(500), "\(times)")
        try? FileManager.default.removeItem(at: root)
    }

    /// A read far past the arrived bytes asks the server for a validated range instead of waiting for the file.
    @Test func aRangeReadsTheEndOfTheFile() async throws {
        let (client, songs) = try await Self.album("Early Playback", named: "Early Playback MP3")
        let song = try #require(songs.first)
        let data = try await Self.bytes(of: song, from: client)
        let transfer = self.transfer("tail.mp3", length: data.count, url: client.streamURL(songID: song.id))
        let tail = try await Task.detached {
            try TrackTransferTests.read(transfer, at: Int64(data.count - 128), count: 128)
        }.value
        #expect(tail == [UInt8](data.suffix(128)))
        #expect(transfer.snapshot.available == 0)
        transfer.cancel()
        try? FileManager.default.removeItem(at: root)
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

    /// Streamed movements scheduled back to back on one node join without a gap, also after a seek.
    @Test(arguments: [("Mendelssohn", "Mendelssohn: Violin Concerto", "mp3"), ("Glide", "Glide in FLAC", "flac")])
    func streamedMovementsJoinWithoutGap(search: String, name: String, suffix: String) async throws {
        let (client, songs) = try await Self.album(search, named: name)
        var movements: [[AVAudioPCMBuffer]] = []
        for (index, song) in songs.enumerated() {
            let data = try await Self.bytes(of: song, from: client)
            let transfer = self.transfer("join\(index).\(suffix)", length: data.count)
            let feeding = Self.feed(data, into: transfer)
            movements.append(try await Self.decode(transfer, suffix: suffix))
            await feeding.value
        }
        let joined = try Self.render(movements.flatMap { $0 })
        let start = GaplessTests.alignment(joined, at: 2048, referenceAt: 2048)
        var join = 0
        let shifts = GaplessTests.movementSamples.dropLast().map { length in
            join += length
            return GaplessTests.alignment(joined, at: start + join + 256, referenceAt: join + 256)
        }
        #expect(shifts == Array(repeating: 0, count: shifts.count), "start \(start), shifts \(shifts)")
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
                        try? await Task.sleep(for: .seconds(7))
                        await Self.feed(data, from: half, into: transfer).value
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
            default: break
            }
        }
        let streams = transfers
        engine.load(songs, from: 0, offset: 0) { song in .stream(streams[song.id]!) }
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

    /// Plays buffers back to back through AVAudioPlayerNode, offline, as the engine schedules them.
    static func render(_ buffers: [AVAudioPCMBuffer]) throws -> [Float] {
        let format = try #require(buffers.first?.format)
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        let total = buffers.reduce(8192) { $0 + Int($1.frameLength) }
        for buffer in buffers { node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil) }
        node.play()
        let output = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096))
        var samples: [Float] = []
        while samples.count < total {
            guard try engine.renderOffline(4096, to: output) == .success else { break }
            samples += UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
        }
        engine.stop()
        return samples
    }
}
