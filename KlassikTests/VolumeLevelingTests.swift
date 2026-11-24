import Testing

@testable import Klassik
@testable import KlassikEngine

struct VolumeLevelingTests {
    /// The ReplayGain of the 1990 fixture recording of the Fifth.
    static let tagged = Song(
        id: "t", title: "t", replayGain: Song.ReplayGain(trackGain: 5, albumGain: 6, trackPeak: 0.7, albumPeak: 0.8))

    @Test func peakLimitsTheBoost() {
        #expect(abs(VolumeLeveling.album.gain(for: Self.tagged.playbackTrack) - 1.938) < 0.001)
        #expect(abs(VolumeLeveling.track.gain(for: Self.tagged.playbackTrack) - 3.098) < 0.001)
    }

    @Test func cutIsNotLimited() {
        let loud = Song(id: "t", title: "t", replayGain: Song.ReplayGain(albumGain: -8, albumPeak: 1.2))
        #expect(VolumeLeveling.album.gain(for: loud.playbackTrack) == -8)
    }

    @Test func missingGainFallsBackToTheOtherThenToFallbackGain() {
        let trackOnly = Song(id: "t", title: "t", replayGain: Song.ReplayGain(trackGain: -3))
        #expect(VolumeLeveling.album.gain(for: trackOnly.playbackTrack) == -3)
        let fallback = Song(id: "t", title: "t", replayGain: Song.ReplayGain(fallbackGain: -2))
        #expect(VolumeLeveling.track.gain(for: fallback.playbackTrack) == -2)
        let empty = Song(id: "t", title: "t", replayGain: Song.ReplayGain())
        #expect(VolumeLeveling.album.gain(for: empty.playbackTrack) == 0)
        #expect(VolumeLeveling.album.gain(for: Song(id: "t", title: "t").playbackTrack) == 0)
    }

    @Test func offIgnoresTags() {
        #expect(VolumeLeveling.off.gain(for: Self.tagged.playbackTrack) == 0)
    }

    @Test func levelingIsAGainStage() {
        let stage: any GainStage = VolumeLeveling.album
        #expect(stage.gain(for: Self.tagged.playbackTrack) == VolumeLeveling.album.gain(for: Self.tagged.playbackTrack))
        #expect(NoGainStage().gain(for: Self.tagged.playbackTrack) == 0)
    }
}
