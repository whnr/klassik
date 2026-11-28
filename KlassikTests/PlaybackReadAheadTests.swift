import Foundation
import Testing

@testable import Klassik
@testable import KlassikEngine

/// The session prepares the tracks of ADR 0060 and shows the slow-connection line at its events.
@Suite(.serialized)
@MainActor
struct PlaybackReadAheadTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    @MainActor private final class Requests {
        var ids: [String] = []
    }

    private func makeSession(_ requests: Requests = Requests()) throws -> (PlaybackSession, FakeEngine) {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults,
            fetch: { song, _ in
                requests.ids.append(song.id)
                let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                try Data(count: 10).write(to: file)
                return file
            })
        let engine = FakeEngine()
        let session = PlaybackSession(engine: engine, store: store, defaults: defaults)
        session.server = InMemoryServer()
        return (session, engine)
    }

    private func item(_ id: String, movements: Int) -> QueueItem {
        let songs = (0..<movements).map { Song(id: "\(id)-\($0)", title: "Movement \($0 + 1)", duration: 10) }
        let recording = WorkIndex.Recording(id: id, album: id, songs: songs)
        let work = WorkIndex.Work(id: id, title: id, composer: "Fixture", isTagged: false, recordings: [recording])
        return QueueItem(work: work, recording: recording)
    }

    /// Lets the read-ahead task run until the requests stop growing.
    private func settle(_ requests: Requests) async throws {
        var seen = -1
        while seen != requests.ids.count {
            seen = requests.ids.count
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func normalModePreparesTheRecordingAndTheNextWork() async throws {
        let requests = Requests()
        let (session, _) = try makeSession(requests)
        session.play(queue: [item("a", movements: 3), item("b", movements: 2), item("c", movements: 1)])
        try await settle(requests)
        #expect(requests.ids == ["a-1", "a-2", "b-0", "b-1"])
        try? FileManager.default.removeItem(at: root)
    }

    /// From Wi-Fi to cellular, the speculative transfers beyond the next track stop at once.
    @Test func cellularStopsTransfersBeyondTheNextTrack() async throws {
        let (session, _, store) = try makeStreamingSession(MusicStorageTests.Started())
        defer {
            session.stop()
            store.clearAll()
            try? FileManager.default.removeItem(at: root)
        }
        session.play(queue: [item("a", movements: 3), item("b", movements: 2)])
        let client = InMemoryServer()
        let later = ["a-2", "b-0", "b-1"].map { id in
            store.transfer(for: Song(id: id, title: id, duration: 10, suffix: "mp3"), client: client)
        }
        session.dataMode = .constrained
        for transfer in later { #expect(store.transfers[transfer.songID] == nil, "\(transfer.songID)") }
        #expect(store.wanted.isSuperset(of: ["a-0", "a-1"]))
        #expect(store.wanted.isDisjoint(with: ["a-2", "b-0", "b-1"]))
    }

    @Test func lowDataModePreparesOnlyTheNextTrack() async throws {
        let requests = Requests()
        let (session, _) = try makeSession(requests)
        session.dataMode = .constrained
        session.play(queue: [item("a", movements: 3), item("b", movements: 2)])
        try await settle(requests)
        #expect(requests.ids == ["a-1"])
        try? FileManager.default.removeItem(at: root)
    }

    /// On the last movement, the next audible track is the first track of the next work.
    @Test func theNextWorkIsReadyAcrossTheBoundary() async throws {
        let requests = Requests()
        let (session, engine) = try makeSession(requests)
        session.dataMode = .constrained
        session.play(queue: [item("a", movements: 2), item("b", movements: 2)])
        try await settle(requests)
        engine.end(0)
        try await settle(requests)
        #expect(requests.ids == ["a-1", "b-0"])
        try? FileManager.default.removeItem(at: root)
    }

    @Test func aQueueEditMovesTheNextTrack() async throws {
        let requests = Requests()
        let (session, _) = try makeSession(requests)
        session.dataMode = .constrained
        session.play(queue: [item("a", movements: 1), item("b", movements: 2)])
        try await settle(requests)
        session.playNext(item("n", movements: 1))
        try await settle(requests)
        #expect(requests.ids == ["b-0", "n-0"])
        try? FileManager.default.removeItem(at: root)
    }

    @Test func leavingLowDataModeAddsTheRestOfTheSet() async throws {
        let requests = Requests()
        let (session, _) = try makeSession(requests)
        session.dataMode = .constrained
        session.play(queue: [item("a", movements: 3), item("b", movements: 1)])
        try await settle(requests)
        session.dataMode = .normal
        try await settle(requests)
        #expect(requests.ids == ["a-1", "a-2", "b-0"])
        try? FileManager.default.removeItem(at: root)
    }

    @Test func pauseAndOfflineStartNoPreparation() async throws {
        let requests = Requests()
        let (session, _) = try makeSession(requests)
        session.dataMode = .offline
        session.play(queue: [item("a", movements: 3)])
        try await settle(requests)
        #expect(requests.ids.isEmpty)
        session.pause()
        session.dataMode = .normal
        try await settle(requests)
        #expect(requests.ids.isEmpty)
        session.resume()
        try await settle(requests)
        #expect(requests.ids == ["a-1", "a-2"])
        try? FileManager.default.removeItem(at: root)
    }

    @Test(arguments: [false, true])
    func pauseKeepsOnlyCurrentPlaybackAndExplicitDownloads(explicitNext: Bool) async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults, transport: { _, _, _ in })
        let engine = FakeEngine()
        let session = PlaybackSession(engine: engine, store: store, defaults: defaults)
        let client = InMemoryServer()
        session.server = client
        session.dataMode = .constrained
        let playing = item("a", movements: 3)
        session.play(playing)
        let current = store.transfer(for: playing.recording.songs[0], client: client)
        let next = store.transfer(for: playing.recording.songs[1], client: client)
        if explicitNext {
            let recording = WorkIndex.Recording(id: "download", album: "Fixture", songs: [playing.recording.songs[1]])
            store.download(recording, title: "Fixture", client: client)
        }
        session.pause()
        #expect(store.pinned == [playing.recording.songs[0].id])
        #expect(store.transfers[playing.recording.songs[0].id] === current)
        #expect((store.transfers[playing.recording.songs[1].id] === next) == explicitNext)
        #expect(session.isPaused)
        // Only a cancelled next transfer can break the engine's decoder; a download keeps it.
        #expect(engine.isRunning == explicitNext)
        session.resume()
        #expect(engine.loads.count == (explicitNext ? 1 : 2))
        #expect(engine.loads.last?.movement == 0)
        #expect(session.error == nil)
        session.stop()
        store.clearAll()
        try? FileManager.default.removeItem(at: root)
    }

    /// A download of another recording leaves the paused engine in place, so Resume needs no seek.
    @Test func pauseKeepsTheEngineBesideAnUnrelatedDownload() async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults, transport: { _, _, _ in })
        let engine = FakeEngine()
        let session = PlaybackSession(engine: engine, store: store, defaults: defaults)
        let client = InMemoryServer()
        session.server = client
        defer {
            session.stop()
            store.clearAll()
            try? FileManager.default.removeItem(at: root)
        }
        session.play(item("a", movements: 1))
        let other = item("other", movements: 2).recording
        store.download(other, title: "Other", client: client)
        try await wait { store.transfers[other.songs[0].id] != nil }
        session.pause()
        #expect(engine.isRunning)
        #expect(store.transfers[other.songs[0].id] != nil)
        session.resume()
        #expect(engine.loads.count == 1)
        #expect(engine.calls.last == .resume)
    }

    private typealias Streaming = (session: PlaybackSession, engine: FakeEngine, store: TrackStore)

    private func makeStreamingSession(_ started: MusicStorageTests.Started) throws -> Streaming {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults, transport: { song, _, _ in started.ids.append(song.id) })
        let engine = FakeEngine()
        let session = PlaybackSession(engine: engine, store: store, defaults: defaults)
        session.server = InMemoryServer()
        return (session, engine, store)
    }

    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    /// The next opening starts before the current transfer ends only when the current track nears its end, and
    /// it waits while current playback has less than two playable seconds (ADR 0060). The fake engine holds no
    /// more decoded audio than the real one, so the arrived encoded audio decides.
    @Test func theNextOpeningStartsWhenTheCurrentTrackNeedsIt() async throws {
        let started = MusicStorageTests.Started()
        let (session, engine, store) = try makeStreamingSession(started)
        defer {
            session.stop()
            store.clearAll()
            try? FileManager.default.removeItem(at: root)
        }
        session.dataMode = .constrained
        let playing = item("a", movements: 2)
        session.play(playing)
        #expect(started.ids == ["a-0"])
        let current = try #require(store.transfers["a-0"])
        engine.decodedSeconds = 3
        engine.encodedSeconds = 1
        try await Task.sleep(for: .milliseconds(600))
        #expect(started.ids == ["a-0"])
        engine.encodedSeconds = 0
        engine.playing = (0, 7)
        try await Task.sleep(for: .milliseconds(600))
        #expect(started.ids == ["a-0"], "The decoded audio alone never reaches two seconds")
        engine.encodedSeconds = 1
        try await wait { started.ids.count == 2 }
        #expect(started.ids == ["a-0", "a-1"])
        let opening = try #require(store.transfers["a-1"])
        #expect(!opening.isHeld)
        engine.encodedSeconds = 0
        try await wait { opening.isHeld }
        #expect(opening.isHeld)
        current.begin(length: 1, validator: nil)
        current.append(Data([1]))
        current.finish(nil)
        try await wait { !opening.isHeld }
        #expect(!opening.isHeld)
        #expect(store.transfers["a-1"] === opening)
    }

    @Test func theOpeningHoldEndsWhenTheEngineAsksForTheOpening() async throws {
        let started = MusicStorageTests.Started()
        let (session, engine, store) = try makeStreamingSession(started)
        defer {
            session.stop()
            store.clearAll()
            try? FileManager.default.removeItem(at: root)
        }
        session.dataMode = .constrained
        session.play(item("a", movements: 2))
        engine.decodedSeconds = 3
        engine.encodedSeconds = 1
        engine.playing = (0, 7)
        try await wait { started.ids.count == 2 }
        let opening = try #require(store.transfers["a-1"])
        engine.encodedSeconds = 0
        try await wait { opening.isHeld }
        // The decoder of a-0 ended before a-0's transfer did: the engine now reads the opening's transfer.
        engine.requested = 1
        try await wait { !opening.isHeld }
        #expect(!opening.isHeld, "A held transfer starves the join")
    }

    @Test func clearMusicPausesPlaybackAndRefillsOnlyOnResume() async throws {
        let started = MusicStorageTests.Started()
        let (session, engine, store) = try makeStreamingSession(started)
        defer {
            session.stop()
            store.clearAll()
            try? FileManager.default.removeItem(at: root)
        }
        session.play(item("a", movements: 3))
        #expect(started.ids == ["a-0"])
        let current = try #require(store.transfers["a-0"])
        current.begin(length: 4, validator: nil)
        current.append(Data([1, 2]))
        store.clearCache()
        #expect(session.isPaused)
        #expect(!engine.isRunning)
        #expect(engine.calls.last == .discard)
        await #expect(throws: TrackTransfer.Failure.cancelled) { try await current.finished() }
        #expect(store.transfers.isEmpty)
        #expect(store.cacheBytes == 0)
        session.dataMode = .constrained
        try await Task.sleep(for: .milliseconds(300))
        #expect(started.ids == ["a-0"])
        #expect(store.transfers.isEmpty)
        session.resume()
        #expect(engine.loads.count == 2)
        #expect(engine.loads.last?.movement == 0)
        #expect(started.ids == ["a-0", "a-0"])
        #expect(session.error == nil)
    }

    // MARK: Slow-connection line

    @Test func theLineAppearsAfterOneSecondOnASlowConnection() async throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 1))
        engine.report(.waiting(PlaybackWait(kind: .start, slow: true)))
        #expect(session.state.slowLine == nil)
        try await Task.sleep(for: .milliseconds(1200))
        #expect(session.state.slowLine == SlowConnectionLine.startText)
        engine.report(.waiting(nil))
        #expect(session.state.slowLine == nil)
    }

    @Test func aFastConnectionWaitsWithoutALine() async throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 1))
        engine.report(.waiting(PlaybackWait(kind: .start, slow: false)))
        try await Task.sleep(for: .milliseconds(1200))
        #expect(session.state.slowLine == nil)
    }

    @Test func theRecoveryLineFollowsALaterWait() async throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 1))
        engine.report(.waiting(nil))
        engine.report(.waiting(PlaybackWait(kind: .resume, slow: true)))
        try await Task.sleep(for: .milliseconds(1200))
        #expect(session.state.slowLine == SlowConnectionLine.resumeText)
    }

    @Test(arguments: ["pause", "stop", "replace"])
    func pauseStopAndANewSelectionRemoveTheLine(action: String) async throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 1))
        engine.report(.waiting(PlaybackWait(kind: .start, slow: true)))
        try await Task.sleep(for: .milliseconds(1200))
        #expect(session.state.slowLine != nil)
        switch action {
        case "pause": session.pause()
        case "stop": session.stop()
        default: session.play(item("b", movements: 1))
        }
        #expect(session.state.slowLine == nil)
    }
}
