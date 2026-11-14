import Foundation
import Testing

@testable import Klassik

@Suite(.serialized)
@MainActor
struct PlaybackSessionHistoryTests {
    private func makeSession(_ server: InMemoryServer, defaults: UserDefaults) -> (PlaybackSession, FakeEngine) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults)
        let engine = FakeEngine()
        let session = PlaybackSession(engine: engine, store: store, defaults: defaults)
        session.server = server
        return (session, engine)
    }

    private func item(_ id: String, album: Bool = false) -> QueueItem {
        let songs = (0..<2).map { Song(id: "\(id)-\($0)", title: "Movement \($0)", duration: 10) }
        let recording = WorkIndex.Recording(id: id, album: id, songs: songs, isAlbum: album)
        let work = WorkIndex.Work(id: id, title: id, composer: "Fixture", isTagged: false, recordings: [recording])
        return QueueItem(work: work, recording: recording)
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: UUID().uuidString))
    }

    @Test func relaunchRestoresPausedAndResumeLoadsTheSavedPlace() async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        let (session, engine) = makeSession(server, defaults: defaults)
        let first = item("first")
        let album = item("album", album: true)
        session.play(queue: [first, album], from: 1)
        engine.playing = (1, 3.25)
        session.pause()
        await session.saveQueue()
        let (relaunch, freshEngine) = makeSession(server, defaults: defaults)
        await relaunch.restoreQueue()
        #expect(relaunch.state.item?.id == first.id)
        #expect(relaunch.state.upNext.map(\.id) == [album.id])
        #expect(relaunch.state.upNext.first?.recording.isAlbum == true)
        #expect(relaunch.state.movement == 1)
        #expect(relaunch.state.position == 3.25)
        #expect(relaunch.state.isPaused)
        #expect(freshEngine.loads.isEmpty)
        relaunch.resume()
        #expect(freshEngine.loads.last == FakeEngine.Load(songs: ["first-0", "first-1"], movement: 1, offset: 3.25))
        session.stop()
        relaunch.stop()
    }

    @Test func anUntouchedLaunchDoesNotClearTheServerQueue() async throws {
        let server = InMemoryServer()
        let (session, _) = makeSession(server, defaults: try defaults())
        await session.saveQueue()
        #expect(await server.savedQueues.isEmpty)
    }

    @Test func slowRestoreCannotReplaceNewPlayback() async throws {
        let server = InMemoryServer()
        let (session, _) = makeSession(server, defaults: try defaults())
        await server.suspendRestore()
        let restoring = Task { await session.restoreQueue() }
        while !(await server.isRestoring) { await Task.yield() }
        let chosen = item("chosen")
        session.play(chosen)
        await server.releaseRestore(
            ServerPlayQueue(current: "old", position: 1000, entry: [Song(id: "old", title: "Old", duration: 10)]))
        await restoring.value
        #expect(session.state.item?.id == chosen.id)
        #expect(!session.state.isPaused)
        session.stop()
    }

    @Test func switchingAccountsDiscardsASlowRestore() async throws {
        let server = InMemoryServer()
        let (session, _) = makeSession(server, defaults: try defaults())
        await server.suspendRestore()
        let restoring = Task { await session.restoreQueue() }
        while !(await server.isRestoring) { await Task.yield() }
        let other = InMemoryServer()
        session.server = other
        await server.releaseRestore(
            ServerPlayQueue(current: "old", position: 1000, entry: [Song(id: "old", title: "Old", duration: 10)]))
        await restoring.value
        #expect(session.state.item == nil)
        #expect(await other.savedQueues.isEmpty)
    }

    @Test func accountChangeKeepsTheOldQueueOnItsOwnServer() async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        let (session, engine) = makeSession(server, defaults: defaults)
        session.play(item("first"))
        engine.playing = (0, 3)
        await session.saveQueue()
        let other = InMemoryServer()
        session.server = other
        #expect(session.state.item == nil)
        await session.saveQueue()
        #expect(await other.savedQueues.isEmpty)
        let (relaunch, _) = makeSession(server, defaults: defaults)
        await relaunch.restoreQueue()
        #expect(relaunch.state.item?.recording.id == "first")
        #expect(relaunch.state.position == 3)
    }

    @Test func naturalEndsScrobbleEachMovementAndClearTheQueue() async throws {
        let server = InMemoryServer()
        let (session, engine) = makeSession(server, defaults: try defaults())
        session.play(item("first"))
        engine.end(0)
        engine.end(1)
        await session.saveQueue()
        #expect(await server.scrobbles == ["first-0", "first-1"])
        #expect(await server.queue?.entry?.isEmpty == true)
        #expect(session.state.queueEnded)
    }

    @Test func pauseSeekAndResumeDoNotDuplicateOrInventAPlay() async throws {
        let server = InMemoryServer()
        let (session, engine) = makeSession(server, defaults: try defaults())
        session.play(item("first"))
        engine.playing = (0, 4)
        session.pause()
        await session.saveQueue()
        #expect(await server.scrobbles.isEmpty)
        session.seek(to: 8)
        session.resume()
        engine.playing = (0, 9)
        session.pause()
        await session.saveQueue()
        #expect(await server.scrobbles == ["first-0"])
        session.resume()
        engine.end(0)
        await session.saveQueue()
        #expect(await server.scrobbles == ["first-0"])
        session.stop()
    }

    @Test func disabledScrobblesPersistAndPlaybackStillSaves() async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        let (session, engine) = makeSession(server, defaults: defaults)
        session.scrobblesEnabled = false
        session.play(item("first"))
        engine.end(0)
        engine.playing = (1, 6)
        session.pause()
        await session.saveQueue()
        #expect(await server.scrobbles.isEmpty)
        #expect(await server.queue?.position == 6000)
        let (relaunch, _) = makeSession(server, defaults: defaults)
        #expect(!relaunch.scrobblesEnabled)
        await relaunch.restoreQueue()
        #expect(relaunch.state.position == 6)
        session.stop()
    }

    @Test func restoredTimeDoesNotCountAsPlayback() async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        let (session, _) = makeSession(server, defaults: defaults)
        session.scrobblesEnabled = false
        session.play(item("first"), from: 1, at: 8)
        session.pause()
        await session.saveQueue()
        let (relaunch, engine) = makeSession(server, defaults: defaults)
        await relaunch.restoreQueue()
        relaunch.scrobblesEnabled = true
        relaunch.resume()
        engine.end(1)
        await relaunch.saveQueue()
        #expect(await server.scrobbles.isEmpty)
        session.stop()
    }
}
