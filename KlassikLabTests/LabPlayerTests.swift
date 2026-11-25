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

    @Test func theFadeSlidersRunFromZeroTo300AndStartAt100() {
        #expect(LabFadeSettings.durationRange == 0...300)
        #expect(LabFadeSettings.defaultDuration == 100)
        #expect(LabFadeSettings.seconds(100, in: LabFadeSettings.durationRange) == 0.1)
        #expect(LabFadeSettings.seconds(0, in: LabFadeSettings.durationRange) == 0)
        #expect(LabFadeSettings.seconds(300, in: LabFadeSettings.durationRange) == 0.3)
        #expect(LabFadeSettings.seconds(900, in: LabFadeSettings.durationRange) == 0.3)
    }

    @Test func theLabStartsWithTheOptionsOfTheApp() {
        #expect(LabFadeSettings().options == FadeOptions())
    }

    @Test func eachLabSettingReachesTheEngineOptions() {
        var settings = LabFadeSettings()
        settings.outCurve = .equalPower
        settings.inCurve = .decibelLinear
        settings.outMilliseconds = 40
        settings.inMilliseconds = 250
        #expect(
            settings.options
                == FadeOptions(outCurve: .equalPower, inCurve: .decibelLinear, outSeconds: 0.04, inSeconds: 0.25))
    }

    @Test func theSeekPickerGivesEachSeekMode() {
        var settings = LabFadeSettings()
        settings.silenceMilliseconds = 70
        #expect(settings.options.seek == .today)
        settings.seek = .silence
        #expect(settings.options.seek == .silence(seconds: 0.07))
        settings.silenceMilliseconds = 400
        #expect(settings.options.seek == .silence(seconds: 0.1))
        settings.seek = .crossfade
        #expect(settings.options.seek == .crossfade)
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
        try FileManager.default.createDirectory(at: LabPlayer.folder, withIntermediateDirectories: true)
        try Data([1]).write(to: file)
        player.stop()
        player.fade.outMilliseconds = 50
        player.replayGain.toggle()
        #expect(FileManager.default.fileExists(atPath: file.path))
        player.selected = cases[1]
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
