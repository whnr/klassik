import Foundation
import MediaPlayer
import Testing

@testable import Klassik

/// A seek event with a fixed position.
private final class PositionEvent: MPChangePlaybackPositionCommandEvent {
    override var positionTime: TimeInterval { 4 }
}

/// MediaPlayer raises an exception when code calls `init` on a command event. The system makes the events,
/// so a test allocates one without `init`. The subclasses above keep no stored state.
private func allocated<Event: MPRemoteCommandEvent>(_ type: Event.Type) -> Event {
    let object = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
    return unsafeDowncast(object.unsafelyUnwrapped, to: Event.self)
}

/// The queue rules, the transport and the audio-session events, through the session interface.
/// A fake engine stands in for the audio, and an in-memory server for the network.
@Suite(.serialized)
@MainActor
struct PlaybackSessionTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    @MainActor private final class Requests {
        var urls: [URL] = []
    }

    private func makeSession(
        _ requests: Requests = Requests(), server: (any ServerPort)? = InMemoryServer()
    ) throws -> (session: PlaybackSession, engine: FakeEngine) {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults,
            fetch: { song, server in
                requests.urls.append(server.streamURL(songID: song.id))
                let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                try Data(count: 10).write(to: file)
                return file
            })
        let engine = FakeEngine()
        let session = PlaybackSession(engine: engine, store: store, defaults: defaults)
        session.server = server
        return (session, engine)
    }

    private func item(_ id: String, movements: Int = 1, gains: [Double?] = []) -> QueueItem {
        let songs = (0..<movements).map { index in
            Song(
                id: "\(id)-\(index)", title: "Movement \(index + 1)", duration: 10, suffix: "mp3",
                replayGain: (index < gains.count ? gains[index] : nil).map { Song.ReplayGain(trackGain: $0) })
        }
        let recording = WorkIndex.Recording(id: id, album: id, performers: "Fixture", songs: songs)
        let work = WorkIndex.Work(id: id, title: id, composer: "Fixture", isTagged: false, recordings: [recording])
        return QueueItem(work: work, recording: recording)
    }

    private func load(_ id: String, movements: Int = 1, from movement: Int = 0, at offset: Double = 0)
        -> FakeEngine.Load
    {
        FakeEngine.Load(songs: (0..<movements).map { "\(id)-\($0)" }, movement: movement, offset: offset)
    }

    // MARK: Play

    @Test func playStartsTheFirstMovement() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        #expect(engine.loads == [load("a", movements: 3)])
        let state = session.state
        #expect(state.item?.recording.id == "a")
        #expect(state.movement == 0)
        #expect(state.position == 0)
        #expect(state.segments == [10, 10, 10])
        #expect(!state.isPaused)
        #expect(!state.isLoading)
        #expect(!state.queueEnded)
        #expect(state.error == nil)
    }

    @Test func playStartsFromAMovementAndAPosition() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3), from: 2, at: 12.5)
        #expect(engine.loads == [load("a", movements: 3, from: 2, at: 12.5)])
        #expect(session.state.movement == 2)
        #expect(session.state.position == 12.5)
    }

    @Test func playingAnotherItemReplacesTheQueue() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a"), item("b"), item("c")])
        #expect(session.state.upNext.map(\.recording.id) == ["b", "c"])
        session.play(item("d"))
        #expect(session.state.item?.recording.id == "d")
        #expect(session.state.upNext.isEmpty)
        #expect(engine.loads.last == load("d"))
    }

    @Test func aMovementOfThePlayingItemOnlyMovesThePosition() throws {
        let (session, engine) = try makeSession()
        let playing = item("a", movements: 3)
        session.play(queue: [playing, item("b")])
        session.play(item("a", movements: 3), from: 2)
        #expect(session.state.item?.id == playing.id)
        #expect(session.state.upNext.map(\.recording.id) == ["b"])
        #expect(session.state.movement == 2)
        #expect(engine.loads.last == load("a", movements: 3, from: 2))
    }

    @Test func playOnThePlayingItemPausesAndResumesIt() throws {
        let (session, engine) = try makeSession()
        let playing = item("a", movements: 3)
        session.play(queue: [playing, item("b")], from: 1)
        engine.playing = (1, 4)
        session.play(item("a", movements: 3))
        #expect(session.state.isPaused)
        #expect(engine.calls.last == .pause)
        session.play(item("a", movements: 3))
        #expect(!session.state.isPaused)
        #expect(engine.calls.last == .resume)
        #expect(engine.loads == [load("a", movements: 3, from: 1)])
        #expect(session.state.item?.id == playing.id)
        #expect(session.state.movement == 1)
        #expect(session.state.upNext.map(\.recording.id) == ["b"])
    }

    @Test func playNextAndAddToQueueFillTheQueue() throws {
        let (session, _) = try makeSession()
        session.play(item("a"))
        session.addToQueue(item("b"))
        session.addToQueue(item("c"))
        session.playNext(item("d"))
        #expect(session.state.item?.recording.id == "a")
        #expect(session.state.upNext.map(\.recording.id) == ["d", "b", "c"])
    }

    @Test(arguments: [false, true])
    func addingToAnEmptyQueuePlaysAtOnce(next: Bool) throws {
        let (session, engine) = try makeSession()
        if next { session.playNext(item("a")) } else { session.addToQueue(item("a")) }
        #expect(session.state.item?.recording.id == "a")
        #expect(engine.loads == [load("a")])
    }

    @Test func playedQueueItemDropsTheItemsBeforeIt() throws {
        let (session, engine) = try makeSession()
        let third = item("c")
        session.play(queue: [item("a"), item("b"), third, item("d")])
        session.playQueued(third.id)
        #expect(session.state.item?.recording.id == "c")
        #expect(session.state.upNext.map(\.recording.id) == ["d"])
        #expect(engine.loads.last == load("c"))
    }

    @Test func queueEditsKeepThePlayingItem() throws {
        let (session, _) = try makeSession()
        session.play(queue: [item("a"), item("b"), item("c"), item("d")])
        session.removeFromQueue(at: IndexSet(integer: 0))
        session.moveInQueue(from: IndexSet(integer: 1), to: 0)
        #expect(session.state.item?.recording.id == "a")
        #expect(session.state.upNext.map(\.recording.id) == ["d", "c"])
    }

    @Test func nothingPlaysWithoutAServer() throws {
        let (session, engine) = try makeSession(server: nil)
        session.play(item("a"))
        session.play(queue: [item("a"), item("b")])
        session.addToQueue(item("c"))
        #expect(engine.loads.isEmpty)
        #expect(session.state.item == nil)
    }

    // MARK: Movements and items end

    @Test func aMovementEndMovesToTheNextMovement() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        engine.end(0)
        #expect(session.state.movement == 1)
        #expect(session.state.position == 0)
        #expect(engine.loads.count == 1)
    }

    @Test func theLastMovementEndStartsTheNextItem() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a", movements: 2), item("b")])
        engine.end(0)
        engine.end(1)
        #expect(session.state.item?.recording.id == "b")
        #expect(session.state.upNext.isEmpty)
        #expect(session.state.movement == 0)
        #expect(engine.loads.last == load("b"))
    }

    @Test func theEndOfTheQueueStopsAndReportsIt() throws {
        let (session, engine) = try makeSession()
        session.play(item("a"))
        engine.end(0)
        let state = session.state
        #expect(state.item == nil)
        #expect(state.queueEnded)
        #expect(state.error == nil)
        #expect(engine.calls.last == .discard)
        session.play(item("b"))
        #expect(!session.state.queueEnded)
    }

    @Test func aStopByTheListenerIsNotTheEndOfTheQueue() throws {
        let (session, _) = try makeSession()
        session.play(queue: [item("a"), item("b")])
        session.stop()
        #expect(session.state.item == nil)
        #expect(session.state.upNext.isEmpty)
        #expect(!session.state.queueEnded)
    }

    @Test(arguments: [false, true])
    func pauseBeforeTheFinalMovementEndKeepsTheItem(queued: Bool) throws {
        let (session, engine) = try makeSession()
        session.play(queue: queued ? [item("a"), item("b")] : [item("a")])
        // The engine's callback can reach the main actor after Pause.
        session.pause()
        engine.end(0)
        #expect(session.state.isPaused)
        #expect(session.state.item?.recording.id == "a")
        #expect(session.state.upNext.count == (queued ? 1 : 0))

        session.resume()
        #expect(session.state.item?.recording.id == (queued ? "b" : nil))
        #expect(session.state.queueEnded == !queued)
        #expect(session.state.isPaused == !queued)
        #expect(session.state.error == nil)
    }

    // MARK: Transport

    @Test func nextGoesToTheNextMovement() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        session.next()
        #expect(session.state.movement == 1)
        #expect(engine.loads.last == load("a", movements: 3, from: 1))
    }

    @Test func nextOnTheLastMovementGoesToTheNextItem() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a", movements: 2), item("b")])
        session.next()
        session.next()
        #expect(session.state.item?.recording.id == "b")
        #expect(engine.loads.last == load("b"))
    }

    @Test func nextOnTheLastMovementOfTheLastItemChangesNothing() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 2), from: 1)
        session.next()
        #expect(session.state.item?.recording.id == "a")
        #expect(session.state.movement == 1)
        #expect(engine.loads.count == 1)
    }

    @Test func nextExistsUntilTheLastMovementOfTheLastItem() throws {
        let (session, _) = try makeSession()
        #expect(!session.hasNext)
        session.play(item("a", movements: 2))
        #expect(session.hasNext)
        session.next()
        #expect(!session.hasNext)
        session.addToQueue(item("b"))
        #expect(session.hasNext)
        session.removeFromQueue(at: IndexSet(integer: 0))
        #expect(!session.hasNext)
    }

    @Test func nextExistsOnTheLastMovementWhenAnotherItemWaits() throws {
        let (session, _) = try makeSession()
        session.play(queue: [item("a", movements: 2), item("b")], from: 1)
        #expect(session.hasNext)
        session.next()
        #expect(session.state.item?.recording.id == "b")
        #expect(!session.hasNext)
    }

    @Test func theLockScreenNextFollowsTheSession() throws {
        let command = MPRemoteCommandCenter.shared().nextTrackCommand
        let (session, _) = try makeSession()
        #expect(!command.isEnabled)
        session.play(item("a", movements: 2))
        #expect(command.isEnabled)
        session.next()
        #expect(!command.isEnabled)
        session.addToQueue(item("b"))
        #expect(command.isEnabled)
        session.stop()
        #expect(!command.isEnabled)
    }

    @Test func previousRestartsAMovementThatHasPlayedForAWhile() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3), from: 1)
        engine.playing = (1, 5)
        session.previous()
        #expect(engine.loads.last == load("a", movements: 3, from: 1))
    }

    @Test func previousGoesBackFromAMovementThatJustBegan() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3), from: 1)
        engine.playing = (1, 1)
        session.previous()
        #expect(engine.loads.last == load("a", movements: 3, from: 0))
    }

    @Test func previousOnTheFirstMovementRestartsIt() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        engine.playing = (0, 1)
        session.previous()
        #expect(engine.loads.last == load("a", movements: 3))
        #expect(session.state.movement == 0)
    }

    @Test func seekMovesThePositionAtOnce() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3), from: 1)
        session.seek(to: 4)
        #expect(session.state.position == 4)
        #expect(!session.state.isPaused)
        #expect(engine.loads.last == load("a", movements: 3, from: 1, at: 4))
    }

    @Test func aPausedSeekStaysPausedUntilResume() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3), from: 1)
        session.pause()
        session.seek(to: 4)
        #expect(session.state.isPaused)
        #expect(session.state.position == 4)
        #expect(engine.loads.count == 1)
        session.resume()
        #expect(!session.state.isPaused)
        #expect(engine.loads.last == load("a", movements: 3, from: 1, at: 4))
    }

    @Test func pauseAndResumeKeepTheEngine() throws {
        let (session, engine) = try makeSession()
        session.play(item("a"))
        session.pause()
        #expect(session.state.isPaused)
        session.resume()
        #expect(!session.state.isPaused)
        #expect(engine.calls.suffix(2) == [.pause, .resume])
        #expect(engine.loads.count == 1)
    }

    @Test func aFailedResumeShowsTheError() throws {
        struct Refusal: LocalizedError {
            var errorDescription: String? { "The audio session did not start." }
        }
        let (session, engine) = try makeSession()
        session.play(item("a"))
        session.pause()
        engine.resumeError = Refusal()
        session.resume()
        #expect(session.state.isPaused)
        #expect(session.state.error == "The audio session did not start.")
        engine.resumeError = nil
        session.resume()
        #expect(!session.state.isPaused)
        #expect(session.state.error == nil)
    }

    // MARK: State from the engine

    @Test func positionAndSegmentsFollowTheEngine() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        engine.playing = (1, 4.5)
        engine.lengths = [1: 9.5]
        // Pause saves the place that the engine reports.
        session.pause()
        let state = session.state
        #expect(state.movement == 1)
        #expect(state.position == 4.5)
        #expect(state.segments == [10, 9.5, 10])
        let progress = try #require(session.progress)
        #expect(progress.movement == 1)
        #expect(progress.workElapsed == 14.5)
        #expect(progress.workDuration == 29.5)
    }

    @Test func aScheduledMovementShowsItsExactLength() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 2))
        engine.lengths = [0: 9.75]
        engine.report(.scheduled(0))
        #expect(session.state.segments == [9.75, 10])
    }

    @Test func loadingFollowsTheEngine() throws {
        let (session, engine) = try makeSession()
        session.play(item("a"))
        engine.report(.loading(true))
        #expect(session.state.isLoading)
        engine.report(.loading(false))
        #expect(!session.state.isLoading)
        engine.report(.loading(true))
        session.stop()
        #expect(!session.state.isLoading)
    }

    @Test func aProblemShowsWhilePlaybackGoesOn() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 2))
        engine.report(.problem("Movement 2 has a different audio format."))
        #expect(session.state.error == "Movement 2 has a different audio format.")
        #expect(!session.state.isPaused)
    }

    @Test func aFailurePausesAndPlayRetries() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 2))
        engine.playing = (1, 3)
        engine.report(.failed("The file is damaged."))
        #expect(session.state.isPaused)
        #expect(session.state.error == "The file is damaged.")
        session.resume()
        #expect(!session.state.isPaused)
        #expect(session.state.error == nil)
        #expect(engine.loads.last == load("a", movements: 2, from: 1, at: 3))
    }

    @Test func gainFollowsTheMovementAndTheLeveling() throws {
        let (session, engine) = try makeSession()
        session.leveling = .track
        session.play(item("a", movements: 2, gains: [-3, -6]))
        #expect(engine.gain == -3)
        engine.end(0)
        #expect(engine.gain == -6)
        session.leveling = .off
        #expect(engine.gain == 0)
    }

    @Test func theEngineGetsItsFilesThroughTheServer() async throws {
        let requests = Requests()
        let (session, engine) = try makeSession(requests)
        let queued = item("a", movements: 2)
        session.play(queued)
        let file = try #require(engine.file)
        _ = try await file(queued.recording.songs[1])
        #expect(requests.urls == [InMemoryServer().streamURL(songID: "a-1")])
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Interruptions and route changes

    @Test(arguments: [false, true])
    func anInterruptionPausesAndResumesFromTheSamePlace(shouldResume: Bool) throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        engine.playing = (2, 6)
        session.handle(.interruptionBegan)
        #expect(session.state.isPaused)
        #expect(engine.calls.last == .discard)
        session.handle(.interruptionEnded(shouldResume: shouldResume))
        #expect(session.state.isPaused == !shouldResume)
        if shouldResume {
            #expect(engine.loads.last == load("a", movements: 3, from: 2, at: 6))
        } else {
            #expect(engine.loads.count == 1)
            session.resume()
            #expect(engine.loads.last == load("a", movements: 3, from: 2, at: 6))
        }
    }

    @Test func playWorksWhenTheInterruptionNeverEnds() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        engine.playing = (1, 2)
        session.handle(.interruptionBegan)
        session.resume()
        #expect(!session.state.isPaused)
        #expect(engine.loads.last == load("a", movements: 3, from: 1, at: 2))
    }

    @Test func mediaServicesComeBackWithTheMusicThatWasPlaying() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        engine.playing = (1, 8)
        session.handle(.mediaServicesLost)
        #expect(session.state.isPaused)
        session.handle(.mediaServicesReset)
        #expect(!session.state.isPaused)
        #expect(engine.loads.last == load("a", movements: 3, from: 1, at: 8))
    }

    @Test func headphonesRemovedPauseUntilPlay() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        engine.playing = (1, 5)
        session.handle(.routeChanged(oldDeviceUnavailable: true, headphonesRemoved: true))
        #expect(session.state.isPaused)
        #expect(engine.calls.last == .discard)
        session.handle(.routeChanged(oldDeviceUnavailable: false, headphonesRemoved: false))
        #expect(session.state.isPaused)
        #expect(session.state.position == 5)
    }

    // MARK: sz-b170: Bluetooth output disconnects

    /// The output that went away leaves a dead graph in the engine. Play must build a new engine at the same place,
    /// and must not wake the old one.
    @Test func playBuildsANewEngineAfterBluetoothDisconnects() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        engine.playing = (1, 7.5)
        session.handle(.routeChanged(oldDeviceUnavailable: true, headphonesRemoved: true))
        #expect(session.state.isPaused)
        #expect(!engine.isRunning)
        session.handle(.configurationChanged)
        session.resume()
        #expect(!session.state.isPaused)
        #expect(session.state.error == nil)
        #expect(engine.calls.contains(.resume) == false)
        #expect(engine.loads.last == load("a", movements: 3, from: 1, at: 7.5))
    }

    /// The engine can report its change first. It restarts on the speaker, and the route change then drops it.
    @Test func playBuildsANewEngineWhenTheEngineRestartedBeforeTheRouteChange() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        engine.playing = (1, 7.5)
        session.handle(.configurationChanged)
        session.handle(.routeChanged(oldDeviceUnavailable: true, headphonesRemoved: true))
        #expect(session.state.isPaused)
        #expect(!engine.isRunning)
        session.resume()
        #expect(!session.state.isPaused)
        #expect(engine.calls.contains(.resume) == false)
        #expect(engine.loads.last == load("a", movements: 3, from: 1, at: 7.5))
    }

    /// The system calls the handlers that `addTarget` gets from a thread of its own. A handler that expects the main
    /// actor traps there, before it reaches the session.
    @Test func lockScreenHandlersWorkOnAnotherThread() async throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        let handlers = PlaybackSession.remoteHandlers(for: session)
        let paused = await Task.detached { handlers.pause(allocated(MPRemoteCommandEvent.self)) == .success }.value
        #expect(paused)
        try await settle { session.state.isPaused }
        #expect(engine.calls.contains(.pause))
        await Task.detached { _ = handlers.play(allocated(MPRemoteCommandEvent.self)) }.value
        try await settle { !session.state.isPaused }
        await Task.detached { _ = handlers.next(allocated(MPRemoteCommandEvent.self)) }.value
        try await settle { session.state.movement == 1 }
        await Task.detached { _ = handlers.previous(allocated(MPRemoteCommandEvent.self)) }.value
        try await settle { session.state.movement == 0 }
        let sought = await Task.detached { handlers.seek(allocated(PositionEvent.self)) == .success }.value
        #expect(sought)
        try await settle { session.state.position == 4 }
        let refused = await Task.detached { handlers.seek(allocated(MPRemoteCommandEvent.self)) == .commandFailed }
            .value
        #expect(refused)
        await Task.detached { _ = handlers.toggle(allocated(MPRemoteCommandEvent.self)) }.value
        try await settle { session.state.isPaused }
    }

    private func settle(until condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "The session did not reach the expected state")
    }
}
