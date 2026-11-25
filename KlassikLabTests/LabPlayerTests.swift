import Foundation
import KlassikEngine
import Testing

@testable import KlassikLab

struct LabPlayerTests {
    @Test func switchWhilePlayingRestartsTheEngine() {
        #expect(LabPlayer.switchAction(isPlaying: true, hasEngine: true) == .restart)
    }

    @Test func switchWhilePausedDiscardsTheEngine() {
        #expect(LabPlayer.switchAction(isPlaying: false, hasEngine: true) == .discard)
    }

    @Test func switchWithoutEngineDoesNothing() {
        #expect(LabPlayer.switchAction(isPlaying: false, hasEngine: false) == .none)
        #expect(LabPlayer.switchAction(isPlaying: true, hasEngine: false) == .none)
    }

    @Test func theFadeSliderRunsFromZeroTo300AndStartsAt100() {
        #expect(LabPlayer.fadeRange == 0...300)
        #expect(LabPlayer.defaultFade == 100)
        #expect(LabPlayer.fadeSeconds(milliseconds: 100) == 0.1)
        #expect(LabPlayer.fadeSeconds(milliseconds: 0) == 0)
        #expect(LabPlayer.fadeSeconds(milliseconds: 300) == 0.3)
        #expect(LabPlayer.fadeSeconds(milliseconds: 900) == 0.3)
    }

    @Test func theJoinNamesGaplessAndGapAtTheEndOfAMovement() {
        #expect(
            LabPlayer.joinAfterEnd(of: 0, nextScheduled: true)
                == "gapless: movement 2 was scheduled before movement 1 ended")
        #expect(
            LabPlayer.joinAfterEnd(of: 0, nextScheduled: false)
                == "gap: movement 2 was not scheduled when movement 1 ended")
    }

    @Test func aFailedLaterMovementShowsItsOwnJoinState() {
        #expect(
            LabPlayer.joinFailure(next: 1, reason: "Server did not answer")
                == "movement 2 failed: Server did not answer")
        #expect(LabPlayer.joinFailure(next: nil, reason: "x") == "load failed: x")
    }

    @Test func theJoinWaitsForTheEndOfMovementOneWhilePlaying() {
        #expect(LabPlayer.joinWaiting(movement: 0, count: 2) == "waiting for the end of movement 1")
        #expect(LabPlayer.joinWaiting(movement: 1, count: 2) == LabPlayer.notPlayed)
    }

    @MainActor @Test func aCachedFileNamesTheTrackAndItsSuffix() {
        let track = PlaybackTrack(id: "ab12", suffix: "MP3")
        #expect(LabPlayer.cached(track) == LabPlayer.folder.appending(path: "ab12.mp3"))
        #expect(LabPlayer.cached(PlaybackTrack(id: "ab12")) == LabPlayer.folder.appending(path: "ab12"))
    }

    /// Stop, a restart and every switch keep the audio files. A case switch and the app start remove them.
    @MainActor @Test func theCacheSurvivesStopAndGoesOnACaseSwitch() throws {
        let credentials = LabCredentials(url: URL(string: "http://127.0.0.1:1")!, username: "u", password: "p")
        let songs = [
            LabSong(
                id: "a", title: "a", track: 1, discNumber: 1, duration: 60, suffix: "flac", bitRate: nil,
                samplingRate: nil, bitDepth: nil, channelCount: 2, path: nil, works: nil, replayGain: nil),
            LabSong(
                id: "b", title: "b", track: 1, discNumber: 2, duration: 60, suffix: "flac", bitRate: nil,
                samplingRate: nil, bitDepth: nil, channelCount: 2, path: nil, works: nil, replayGain: nil),
        ]
        let cases = LabCase.cases(from: songs)
        let file = LabPlayer.folder.appending(path: "a.flac")
        try FileManager.default.createDirectory(at: LabPlayer.folder, withIntermediateDirectories: true)
        try Data([1]).write(to: file)
        let player = LabPlayer(client: LabClient(credentials: credentials), cases: cases)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try Data([1]).write(to: file)
        player.stop()
        player.fadeMilliseconds = 50
        player.replayGain.toggle()
        #expect(FileManager.default.fileExists(atPath: file.path))
        player.selected = cases[1]
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
