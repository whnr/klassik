import Foundation
import MediaPlayer
import Testing
import UIKit

@testable import Klassik
@testable import KlassikEngine

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
        _ requests: Requests = Requests(), server: (any ServerPort)? = InMemoryServer(),
        gainStage: (any GainStage)? = nil
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
        let session = PlaybackSession(engine: engine, store: store, defaults: defaults, gainStage: gainStage)
        session.server = server
        return (session, engine)
    }

    private func item(_ id: String, movements: Int = 1, gains: [Double?] = []) -> QueueItem {
        let songs = (0..<movements).map { index in
            Song(
                id: "\(id)-\(index)", title: "Movement \(index + 1)", duration: 10, suffix: "mp3",
                replayGain: (index < gains.count ? gains[index] : nil).map { Song.ReplayGain(trackGain: $0) })
        }
        let recording = WorkIndex.Recording(id: id, album: id, songs: songs)
        let work = WorkIndex.Work(id: id, title: id, composer: "Fixture", isTagged: false, recordings: [recording])
        return QueueItem(work: work, recording: recording)
    }

    private func load(
        _ id: String, movements: Int = 1, from movement: Int = 0, at offset: Double = 0, following: [String] = []
    )
        -> FakeEngine.Load
    {
        FakeEngine.Load(songs: (0..<movements).map { "\(id)-\($0)" } + following, movement: movement, offset: offset)
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
        #expect(session.coverSong?.id == "a-2")
    }

    @Test func playingCoverFollowsALaterStartAndDiscChange() throws {
        let (session, engine) = try makeSession()
        var playing = item("a", movements: 3)
        playing.recording.songs[0].discNumber = 1
        playing.recording.songs[1].discNumber = 1
        playing.recording.songs[2].discNumber = 2
        session.play(playing, from: 1)
        #expect(session.coverSong?.id == "a-1")
        #expect(session.coverSong?.discNumber == 1)
        engine.end(1)
        #expect(session.coverSong?.id == "a-2")
        #expect(session.coverSong?.discNumber == 2)
    }

    @Test func washFollowsMovementBetweenDifferentlyColouredKeptCovers() async throws {
        let (session, engine) = try makeSession()
        let fixture = CoverArtTests()
        var playing = item("a", movements: 2)
        for index in playing.recording.songs.indices {
            playing.recording.songs[index].albumId = "a"
            playing.recording.songs[index].discNumber = index + 1
            playing.recording.songs[index].coverArt = "disc-\(index)"
        }
        fixture.server.covers = ["disc-0": CoverWashTests.file(.red), "disc-1": CoverWashTests.file(.blue)]
        let store = try fixture.makeStore()
        let covers = fixture.makeCovers(store, songs: playing.recording.songs)
        await covers.idle()
        fixture.server.reset()
        session.play(playing)
        let first = try #require(session.coverSong)
        let firstLoad = CoverWashModifier.Load(song: first, covers: covers)
        let firstWash = await CoverWashModifier.loaded(firstLoad, song: first, store: store)
        engine.end(0)
        let second = try #require(session.coverSong)
        let secondLoad = CoverWashModifier.Load(song: second, covers: covers)
        let secondWash = await CoverWashModifier.loaded(secondLoad, song: second, store: store)
        #expect(firstLoad != secondLoad)
        let red = try #require(firstWash?.pick)
        let blue = try #require(secondWash?.pick)
        #expect(CoverWashTests.distance(red.hue, OKLCH(CoverWashTests.hex(0xff_00_00)).hue) < 5)
        #expect(CoverWashTests.distance(blue.hue, OKLCH(CoverWashTests.hex(0x00_00_ff)).hue) < 5)
        #expect(fixture.server.requests.isEmpty)
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
        #expect(engine.loads.last == load("a", movements: 3, from: 2, following: ["b-0"]))
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
        #expect(engine.loads == [load("a", movements: 3, from: 1, following: ["b-0"])])
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
        #expect(engine.loads.last == load("c", following: ["d-0"]))
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
        #expect(session.coverSong?.id == "a-1")
    }

    @Test func theLastMovementEndStartsTheNextItem() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a", movements: 2), item("b")])
        engine.end(0)
        engine.end(1)
        #expect(session.state.item?.recording.id == "b")
        #expect(session.state.upNext.isEmpty)
        #expect(session.state.movement == 0)
        #expect(engine.loads == [load("a", movements: 2, following: ["b-0"])])
        engine.end(2)
        #expect(session.state.queueEnded)
    }

    /// A recording whose movements differ in rate: the engine ends its load at the join and the session loads again
    /// at the movement that needs the new format, from its start.
    @Test func aFormatBreakInsideARecordingLoadsAgainAtThatMovement() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a", movements: 3), item("b")])
        engine.end(0)
        engine.report(.formatChanged(1))
        #expect(
            engine.loads == [
                load("a", movements: 3, following: ["b-0"]),
                load("a", movements: 3, from: 1, following: ["b-0"]),
            ])
        #expect(session.state.movement == 1)
        #expect(session.state.position == 0)
        #expect(session.state.isPaused == false)
    }

    /// The first movement of the next recording has another format: the old engine ends with the last movement,
    /// and the reload takes the next recording as its first one.
    @Test func aFormatBreakAtARecordingBoundaryLoadsTheNextRecording() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a"), item("b", movements: 2), item("c")])
        engine.end(0)
        #expect(session.state.item?.recording.id == "b")
        #expect(engine.loads.count == 1)
        engine.report(.formatChanged(1))
        #expect(engine.loads.count == 2)
        #expect(engine.loads.last == load("b", movements: 2, following: ["c-0"]))
        #expect(session.state.item?.recording.id == "b")
        #expect(session.state.movement == 0)
        #expect(session.state.upNext.map(\.recording.id) == ["c"])
    }

    /// A paused session builds no graph: it drops the engine, and Resume loads at the movement that needs it.
    @Test func aFormatBreakWhilePausedWaitsForResume() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a", movements: 2)])
        engine.end(0)
        session.pause()
        engine.report(.formatChanged(1))
        #expect(engine.loads.count == 1)
        #expect(engine.calls.last == .discard)
        #expect(!engine.isRunning)
        session.resume()
        #expect(engine.loads.count == 2)
        #expect(engine.loads.last == load("a", movements: 2, from: 1))
        #expect(session.state.movement == 1)
    }

    @Test func renderPositionCrossesRecordingsBeforeCompletionDelivery() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a"), item("b", movements: 2), item("c")])
        engine.playing = (2, 4)
        session.pause()
        #expect(session.state.item?.recording.id == "b")
        #expect(session.state.movement == 1)
        #expect(session.state.position == 4)
        engine.end(0)
        #expect(session.state.item?.recording.id == "b")
        session.resume()
        engine.end(2)
        #expect(session.state.item?.recording.id == "c")
        #expect(engine.loads.count == 1)
        engine.end(3)
        #expect(session.state.queueEnded)
    }

    /// A queue edit keeps the sound: the engine takes the new tracks after the ones it already asked for.
    @Test func queueEditsKeepTheSoundAndReplaceLaterTracks() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a", movements: 2), item("b")])
        engine.playing = (0, 4)
        session.playNext(item("c"))
        session.addToQueue(item("d"))
        session.moveInQueue(from: IndexSet(integer: 2), to: 1)
        session.removeFromQueue(at: IndexSet(integer: 2))
        #expect(engine.loads.count == 1)
        // Play itself discards before its load; nothing after the load may discard.
        let afterLoad = engine.calls.drop { call in
            if case .load = call { false } else { true }
        }
        #expect(!afterLoad.contains(.discard))
        #expect(engine.calls.last == .replace(["a-0", "a-1", "c-0", "d-0"]))
        engine.end(0)
        engine.end(1)
        #expect(session.state.item?.recording.id == "c")
        #expect(session.state.upNext.map(\.recording.id) == ["d"])
    }

    /// Only an edit of a track that the engine already asked for loads again, from the audible place.
    @Test func anEditOfAnAlreadyScheduledTrackLoadsAgain() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a"), item("b")])
        engine.playing = (0, 4)
        engine.requested = 1
        session.addToQueue(item("d"))
        #expect(engine.loads.count == 1)
        session.playNext(item("c"))
        #expect(engine.loads.last == load("a", at: 4, following: ["c-0", "b-0", "d-0"]))
        engine.end(0)
        #expect(session.state.item?.recording.id == "c")
        #expect(session.state.upNext.map(\.recording.id) == ["b", "d"])
    }

    /// A paused edit keeps the paused engine, so Resume plays on without a seek.
    @Test func aPausedQueueEditKeepsTheEngine() throws {
        let (session, engine) = try makeSession()
        session.play(queue: [item("a", movements: 2), item("b")])
        session.pause()
        session.addToQueue(item("c"))
        session.resume()
        #expect(engine.loads.count == 1)
        #expect(engine.calls.last == .resume)
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

    /// A scrub on the timeline ends in any movement of the playing item.
    @Test func seekToAnotherMovementMovesThereAtOnce() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        session.seek(movement: 2, to: 4)
        #expect(session.state.movement == 2)
        #expect(session.state.position == 4)
        #expect(!session.state.isPaused)
        #expect(engine.loads.last == load("a", movements: 3, from: 2, at: 4))
    }

    @Test func aPausedSeekToAnotherMovementStaysPaused() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        session.pause()
        session.seek(movement: 2, to: 4)
        #expect(session.state.isPaused)
        #expect(session.state.movement == 2)
        #expect(session.state.position == 4)
        #expect(engine.loads.count == 1)
    }

    @Test func seekToAMovementThatTheItemDoesNotHaveChangesNothing() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 3))
        session.seek(movement: 3, to: 4)
        #expect(session.state.movement == 0)
        #expect(engine.loads.count == 1)
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

    // MARK: System players

    /// The system holds the artwork and calls it from its own thread, as this box lets the test do.
    private struct Handed: @unchecked Sendable {
        let artwork: MPMediaItemArtwork
    }

    @MainActor private final class Kept {
        var image: UIImage?
    }

    private static func cover(_ colour: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { context in
            colour.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    @Test func theSystemPlayersShowTheCoverOfEachTrack() async throws {
        let (session, _) = try makeSession()
        let covers = ["a-0": Self.cover(.red), "a-1": Self.cover(.green)]
        session.coverImage = { covers[$0.id] }
        session.coverKey = { $0.id }
        session.play(item("a", movements: 3))
        try await settle { session.nowPlayingArtwork?.key == "a-0" }
        #expect(session.nowPlayingArtwork?.key == "a-0")
        let artwork = Handed(artwork: try #require(session.nowPlayingArtwork?.artwork))
        // The system asks for the image on a thread of its own; a main-actor handler would trap there.
        let image = await Task.detached { artwork.artwork.image(at: CGSize(width: 4, height: 4)) }.value
        #expect(image === covers["a-0"])

        session.next()
        try await settle { session.nowPlayingArtwork?.key == "a-1" }
        #expect(session.nowPlayingArtwork?.key == "a-1")

        // A track without a kept cover shows none, never the cover of the track before.
        session.next()
        try await settle { session.nowPlayingArtwork == nil }
        #expect(session.nowPlayingArtwork == nil)
    }

    @Test func theArtworkStaysWhileMovementsShareOneCover() async throws {
        let (session, _) = try makeSession()
        let shared = Self.cover(.red)
        session.coverImage = { _ in shared }
        session.coverKey = { _ in "disc" }
        session.play(item("a", movements: 3))
        try await settle { session.nowPlayingArtwork != nil }
        let before = try #require(session.nowPlayingArtwork?.artwork)

        session.next()
        // The artwork never goes nil between the movements, so the lock screen does not flicker.
        #expect(session.nowPlayingArtwork?.artwork === before)
        try await Task.sleep(for: .milliseconds(20))
        #expect(session.nowPlayingArtwork?.artwork === before)
    }

    @Test func aCoverThatArrivesDuringPlaybackReachesTheSystemPlayers() async throws {
        let (session, _) = try makeSession()
        let kept = Kept()
        session.coverImage = { _ in kept.image }
        session.coverKey = { $0.id }
        session.play(item("a"))
        try await Task.sleep(for: .milliseconds(20))
        #expect(session.nowPlayingArtwork == nil)
        kept.image = Self.cover(.blue)
        session.coverChanged()
        try await settle { session.nowPlayingArtwork != nil }
        #expect(session.nowPlayingArtwork?.key == "a-0")
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

    /// A server failure pauses without a notice. The cause joins the one server status until the next sound.
    @Test func aServerFailurePausesQuietly() throws {
        let (session, engine) = try makeSession()
        session.play(item("a", movements: 2))
        engine.report(.serverFailed(.unreachable))
        #expect(session.state.isPaused)
        #expect(session.state.error == nil)
        #expect(session.playbackTrouble == .unreachable)
        session.resume()
        #expect(session.playbackTrouble == .unreachable)
        engine.report(.waiting(nil))
        #expect(session.playbackTrouble == nil)
    }

    @Test func playbackFailuresMapToTheQuietStatus() {
        #expect(ServerTrouble(playback: URLError(.notConnectedToInternet)) == .unreachable)
        #expect(ServerTrouble(playback: TrackTransfer.Failure.timedOut) == .unreachable)
        #expect(ServerTrouble(playback: TrackTransfer.Failure.truncated) == .unreachable)
        #expect(ServerTrouble(playback: TrackStore.Failure.offline) == .unreachable)
        #expect(ServerTrouble(playback: TrackTransfer.Failure.http(404)) == .refused)
        #expect(ServerTrouble(playback: TrackTransfer.Failure.storage) == nil)
        #expect(ServerTrouble(playback: StreamDecoder.Failure.status(-1)) == nil)
        // A device failure still explains itself; no failure shows a type name.
        let failures: [any Error] = [
            TrackTransfer.Failure.cancelled, TrackTransfer.Failure.invalidRead, StreamDecoder.Failure.unsupported,
            StreamDecoder.Failure.prematureEnd(expected: 2, actual: 1), TrackStore.Failure.offline,
        ]
        for failure in failures { #expect(!failure.localizedDescription.contains("Klassik."), "\(failure)") }
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

    @Test func aGainStageReplacesTheLeveling() throws {
        let (session, engine) = try makeSession(gainStage: NoGainStage())
        session.leveling = .track
        session.play(item("a", movements: 2, gains: [-3, -6]))
        #expect(engine.gain == 0)
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

    private func path(gainStage: Bool, rate: Double = 44_100, hardware: Double = 44_100) -> PlaybackSignalPath {
        let outputs = PlaybackOutputFormats(
            mixerRate: rate, mixerChannels: 2, hardwareRate: hardware, hardwareChannels: 2)
        return PlaybackSignalPath(engineRate: rate, engineChannels: 2, outputs: outputs, gainStage: gainStage)
    }

    /// ReplayGain off builds the next graph without a gain stage, and a graph that has one reloads at the checkpoint.
    @Test func replayGainOffReloadsTheGraphWithoutAGainStage() throws {
        let (session, engine) = try makeSession()
        #expect(engine.gainStageRequests == [true])
        session.play(item("a", movements: 2))
        engine.signalPath = path(gainStage: true)
        session.leveling = .off
        #expect(engine.gainStageRequests == [true, false])
        #expect(engine.loads.count == 2)
        engine.signalPath = path(gainStage: false)
        session.leveling = .album
        #expect(engine.gainStageRequests == [true, false, true])
        #expect(engine.loads.count == 3)
    }

    @Test func aChangeThatLeavesTheGraphAloneReloadsNothing() throws {
        let (session, engine) = try makeSession()
        session.play(item("a"))
        engine.signalPath = path(gainStage: true)
        session.leveling = .track
        #expect(engine.loads.count == 1)
    }

    @Test func theQualityLineFollowsTheSettingAndTheEngine() throws {
        let (session, engine) = try makeSession()
        session.play(item("a"))
        engine.signalPath = path(gainStage: false)
        #expect(session.qualityLine == nil)
        session.showsAudioQuality = true
        #expect(session.qualityLine == "MP3 44.1 kHz, output 44.1 kHz, lossy source, bit-perfect not verified")
        session.showsAudioQuality = false
        #expect(session.qualityLine == nil)
    }

    /// A paused session discards its graph on a ReplayGain change, so the line must drop the old stage reason at once.
    @Test func theQualityLineDropsTheGainStageReasonWhenReplayGainChangesWhilePaused() throws {
        let (session, engine) = try makeSession()
        session.play(item("a"))
        engine.signalPath = path(gainStage: true)
        session.showsAudioQuality = true
        #expect(session.qualityLine?.contains("ReplayGain stage in the path") == true)
        session.pause()
        session.leveling = .off
        #expect(session.qualityLine?.contains("ReplayGain") == false)
    }

    @Test func theEngineGetsItsFilesThroughTheServer() async throws {
        let requests = Requests()
        let (session, engine) = try makeSession(requests)
        let queued = item("a", movements: 2)
        session.play(queued)
        let file = try #require(engine.file)
        _ = try await file(queued.recording.songs[1].playbackTrack)
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
