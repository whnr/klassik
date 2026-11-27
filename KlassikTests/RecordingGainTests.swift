import Testing

@testable import Klassik
@testable import KlassikEngine

/// One gain for a recording, from the track gains of its tracks.
struct RecordingGainTests {
    private func track(
        _ id: String, seconds: Int? = 100, gain: Double? = nil, peak: Double? = nil, albumGain: Double? = nil,
        albumPeak: Double? = nil
    ) -> PlaybackTrack {
        PlaybackTrack(
            id: id, duration: seconds,
            replayGain: PlaybackTrack.ReplayGain(
                trackGain: gain, albumGain: albumGain, trackPeak: peak, albumPeak: albumPeak))
    }

    @Test func equalGainsGiveThatGain() {
        let tracks = [track("a", gain: -3), track("b", seconds: 250, gain: -3)]
        #expect(abs(RecordingGain.gain(of: tracks)! - -3) < 0.001)
    }

    /// The mean is of the power, not of the decibels: a quiet movement adds less than a loud one.
    @Test func meansTheLoudnessInThePowerDomain() {
        let tracks = [track("a", gain: 0), track("b", gain: -6)]
        #expect(abs(RecordingGain.gain(of: tracks)! - -3.963) < 0.001)
    }

    @Test func weighsByDuration() {
        let tracks = [track("a", seconds: 300, gain: 0), track("b", seconds: 100, gain: -6)]
        #expect(abs(RecordingGain.gain(of: tracks)! - -2.419) < 0.001)
    }

    @Test func aTrackWithoutADurationWeighsAsTheAverage() {
        let unknown = [track("a", seconds: 0, gain: 0), track("b", seconds: 100, gain: -6)]
        let average = [track("a", seconds: 100, gain: 0), track("b", seconds: 100, gain: -6)]
        #expect(abs(RecordingGain.gain(of: unknown)! - RecordingGain.gain(of: average)!) < 0.001)
        let none = [track("a", seconds: nil, gain: 0), track("b", seconds: nil, gain: -6)]
        #expect(abs(RecordingGain.gain(of: none)! - RecordingGain.gain(of: average)!) < 0.001)
    }

    /// A track without a gain leaves the mean to the others, and plays at the result.
    @Test func aTrackWithoutAGainAddsNothing() {
        let tracks = [track("a", gain: -2), track("b"), track("c", gain: -8)]
        #expect(abs(RecordingGain.gain(of: tracks)! - -5.963) < 0.001)
        #expect(abs(VolumeLeveling.work.gain(for: tracks[1], in: tracks) - -5.963) < 0.001)
    }

    @Test func noTrackGainGivesNothing() {
        #expect(RecordingGain.gain(of: [track("a"), track("b", albumGain: -5)]) == nil)
        #expect(RecordingGain.gain(of: []) == nil)
        let untagged = PlaybackTrack(id: "u")
        #expect(RecordingGain.gain(of: [untagged]) == nil)
    }

    /// An album gain describes other tracks, so it never enters the mean.
    @Test func ignoresTheAlbumGain() {
        let tracks = [track("a", gain: -4, albumGain: 9), track("b", gain: -4, albumGain: 9)]
        #expect(abs(RecordingGain.gain(of: tracks)! - -4) < 0.001)
    }

    /// The highest peak of any movement limits the one gain.
    @Test func theHighestPeakLimitsTheBoost() {
        let tracks = [track("a", gain: 5, peak: 0.5), track("b", gain: 5, peak: 0.9)]
        #expect(abs(RecordingGain.gain(of: tracks)! - 0.915) < 0.001)
        #expect(abs(VolumeLeveling.work.gain(for: tracks[0], in: tracks) - 0.915) < 0.001)
    }

    @Test func aPeakOnATrackWithoutAGainStillLimits() {
        let tracks = [track("a", gain: 5, peak: 0.5), track("b", peak: 0.8)]
        #expect(abs(RecordingGain.gain(of: tracks)! - 1.938) < 0.001)
    }

    @Test func aTrackWithoutAPeakUsesTheAlbumPeak() {
        let tracks = [track("a", gain: 5, albumPeak: 0.8), track("b", gain: 5)]
        #expect(abs(RecordingGain.gain(of: tracks)! - 1.938) < 0.001)
    }

    @Test func aCutIsNotLimited() {
        let tracks = [track("a", gain: -8, peak: 1.2), track("b", gain: -8, peak: 0.4)]
        #expect(abs(RecordingGain.gain(of: tracks)! - -8) < 0.001)
    }

    @Test func aRecordingWithoutTrackGainsPlaysAtTheAlbumGain() {
        let tracks = [track("a", albumGain: -5), track("b", albumGain: -5)]
        #expect(VolumeLeveling.work.gain(for: tracks[0], in: tracks) == -5)
        let fallback = PlaybackTrack(id: "f", replayGain: PlaybackTrack.ReplayGain(fallbackGain: -2))
        #expect(VolumeLeveling.work.gain(for: fallback, in: [fallback]) == -2)
        #expect(VolumeLeveling.work.gain(for: PlaybackTrack(id: "n"), in: [PlaybackTrack(id: "n")]) == 0)
    }

    @Test func otherSettingsIgnoreTheRecording() {
        let tracks = [track("a", gain: -2), track("b", gain: -8)]
        #expect(VolumeLeveling.track.gain(for: tracks[1], in: tracks) == -8)
        #expect(VolumeLeveling.off.gain(for: tracks[1], in: tracks) == 0)
    }

    @Test func aTrackAloneIsItsOwnRecording() {
        let only = track("a", gain: 5, peak: 0.7)
        #expect(VolumeLeveling.work.gain(for: only) == VolumeLeveling.track.gain(for: only))
    }

    /// A whole album holds several works. Each work keeps its own level, and tracks without a work tag share one.
    @Test func aWholeAlbumLevelsEachWorkApart() {
        func song(_ id: String, work: String?, gain: Double) -> Song {
            Song(
                id: id, title: id, album: "Disc", albumId: "d", duration: 100,
                works: work.map { [Song.Work(name: $0)] }, replayGain: Song.ReplayGain(trackGain: gain))
        }
        let songs = [
            song("a1", work: "A", gain: -2), song("a2", work: "A", gain: -4),
            song("b1", work: "B", gain: -10), song("u1", work: nil, gain: -6),
        ]
        let album = WorkIndex.Recording(id: "r", album: "Disc", songs: songs, isAlbum: true)
        #expect(album.levelGroup(of: 0).map(\.id) == ["a1", "a2"])
        #expect(album.levelGroup(of: 1).map(\.id) == ["a1", "a2"])
        #expect(album.levelGroup(of: 2).map(\.id) == ["b1"])
        #expect(album.levelGroup(of: 3).map(\.id) == ["u1"])
        let recording = WorkIndex.Recording(id: "r", album: "Disc", songs: songs)
        #expect(recording.levelGroup(of: 2).count == 4)
    }
}
