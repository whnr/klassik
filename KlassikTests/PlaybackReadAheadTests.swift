import Foundation
import Testing

@testable import Klassik

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
        #expect(requests.ids == ["a-1", "a-2", "b-0"])
        try? FileManager.default.removeItem(at: root)
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
        #expect(!engine.isRunning)
        session.resume()
        #expect(engine.loads.count == 2)
        #expect(engine.loads.last?.movement == 0)
        #expect(session.error == nil)
        session.stop()
        store.clearAll()
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Slow-connection line

    @Test func theLineAppearsAfterOneSecondOnASlowConnection() async throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 1))
        engine.report(.waiting(PlaybackWait(kind: .start, slow: true)))
        #expect(session.state.slowLine == nil)
        #expect(session.state.isLoading)
        try await Task.sleep(for: .milliseconds(1200))
        #expect(session.state.slowLine == SlowConnectionLine.startText)
        engine.report(.waiting(nil))
        #expect(session.state.slowLine == nil)
        #expect(!session.state.isLoading)
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
