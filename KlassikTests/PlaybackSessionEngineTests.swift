import AVFoundation
import Synchronization
import Testing

@testable import Klassik

/// The session with the real engine, against the fixture server. Held completions stand in for the audio thread.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["KLASSIK_SERVER_URL"] != nil))
@MainActor
struct PlaybackSessionEngineTests {
    private final class Completions: Sendable {
        typealias Callback = @MainActor @Sendable () -> Void
        private let callbacks = Mutex<[Callback]>([])

        var count: Int { callbacks.withLock { $0.count } }

        func hold(_ callback: @escaping Callback) {
            callbacks.withLock { $0.append(callback) }
        }

        @MainActor func deliver() {
            let pending = callbacks.withLock { callbacks in
                let pending = callbacks
                callbacks.removeAll()
                return pending
            }
            for callback in pending { callback() }
        }
    }

    @MainActor private final class DownloadGate {
        private var continuation: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { continuation != nil }

        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    private let client = InMemoryServer()

    private func item(_ id: String, movements: Int = 1) -> QueueItem {
        let songs = (0..<movements).map {
            Song(id: "\(id)-\($0)", title: "Movement \($0 + 1)", duration: 2, suffix: "wav")
        }
        let recording = WorkIndex.Recording(id: id, album: id, songs: songs)
        let work = WorkIndex.Work(id: id, title: id, composer: "Fixture", isTagged: false, recordings: [recording])
        return QueueItem(work: work, recording: recording)
    }

    private func makePlayer(_ completions: Completions, gate: DownloadGate? = nil) async throws -> PlaybackSession {
        let env = ProcessInfo.processInfo.environment
        let server = try #require(env["KLASSIK_SERVER_URL"].flatMap(ServerCredentials.normalizedURL))
        let fixtureClient = SubsonicClient(
            credentials: ServerCredentials(
                url: server, username: env["KLASSIK_USERNAME"] ?? "", password: env["KLASSIK_PASSWORD"] ?? ""))
        let albums = try await fixtureClient.searchAlbums("Glide")
        let album = try #require(albums.first { $0.name == "Glide in FLAC" })
        let songs = try await fixtureClient.album(id: album.id).songs
        let song = try #require(songs.first)
        let (data, response) = try await URLSession.shared.data(from: fixtureClient.streamURL(songID: song.id))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "source.flac")
        try data.write(to: source)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults,
            fetch: { song, _ in
                if song.id == "first-1", let gate { await gate.wait() }
                try Task.checkCancellation()
                return try clip(source, seconds: song.id == "first-0" ? 0.2 : 2)
            })
        let session = PlaybackSession(
            engine: GaplessEngine(deliverCompletion: { completions.hold($0) }), store: store, defaults: defaults)
        session.server = client
        return session
    }

    private func clip(_ source: URL, seconds: Double) throws -> URL {
        let input = try AVAudioFile(forReading: source)
        let url = root.appending(path: "\(UUID().uuidString).wav")
        let format = input.processingFormat
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        try input.read(into: buffer, frameCount: frames)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Session did not reach the expected state")
    }

    @Test(arguments: [false, true], [false, true])
    func pauseBeforeFinalCompletionDelivery(queued: Bool, deliverBeforeResume: Bool) async throws {
        let completions = Completions()
        let player = try await makePlayer(completions)
        defer {
            player.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let first = item("first")
        let second = item("second")
        player.play(queue: queued ? [first, second] : [first])
        try await wait { completions.count == 1 }

        // Hold the audio-thread callback until Pause has reached the main actor.
        player.pause()
        if deliverBeforeResume { completions.deliver() }
        #expect(player.isPaused)
        #expect(player.item?.id == first.id)
        #expect(player.upNext.count == (queued ? 1 : 0))

        player.resume()
        if !deliverBeforeResume { completions.deliver() }
        #expect(player.item?.id == (queued ? second.id : nil))
        #expect(player.upNext.isEmpty)
        #expect(player.isPaused == !queued)
        #expect(player.error == nil)
        if queued {
            try await wait { (player.progress?.elapsed ?? 0) > 0 }
            #expect(player.item?.id == second.id)
        }
    }

    @Test(arguments: [false, true])
    func delayedSecondDownloadKeepsThePendingMovement(skip: Bool) async throws {
        let completions = Completions()
        let gate = DownloadGate()
        let player = try await makePlayer(completions, gate: gate)
        defer {
            player.stop()
            gate.release()
            try? FileManager.default.removeItem(at: root)
        }
        let first = item("first", movements: 3)
        let queued = item("queued")
        player.play(queue: [first, queued])
        try await wait { gate.isWaiting && completions.count == 1 }
        completions.deliver()
        #expect(player.movement == 1)
        #expect(player.progress?.movement == 1)
        #expect(player.progress?.elapsed == 0)

        // The position task must run while the next movement has no scheduled segment.
        try await Task.sleep(for: .milliseconds(600))
        #expect(player.movement == 1)
        #expect(player.progress?.movement == 1)
        player.pause()
        player.resume()
        #expect(player.movement == 1)

        if skip { player.next() }
        gate.release()
        let expected = skip ? 2 : 1
        try await wait { player.progress?.movement == expected && (player.progress?.elapsed ?? 0) > 0 }
        #expect(player.movement == expected)
        #expect(player.item?.id == first.id)
        #expect(player.upNext.map(\.id) == [queued.id])
        #expect(player.error == nil)
    }

    @Test func replacementIgnoresHeldCompletion() async throws {
        let completions = Completions()
        let player = try await makePlayer(completions)
        defer {
            player.stop()
            try? FileManager.default.removeItem(at: root)
        }
        player.play(queue: [item("first")])
        try await wait { completions.count == 1 }
        player.pause()
        let replacement = item("replacement")
        player.play(queue: [replacement])
        completions.deliver()
        #expect(player.item?.id == replacement.id)
        #expect(!player.isPaused)
    }
}
