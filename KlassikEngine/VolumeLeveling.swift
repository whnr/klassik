import Foundation

/// Which ReplayGain value sets the playback volume.
public enum VolumeLeveling: String, CaseIterable, Identifiable, Sendable, GainStage {
    /// One gain for the whole album keeps the loudness steps between movements.
    case album
    /// One gain for the whole recording: every movement plays at the level of the recording.
    case work
    case track
    case off

    public var id: Self { self }

    public var title: String {
        switch self {
        case .album: "Album"
        case .work: "Work"
        case .track: "Track"
        case .off: "Off"
        }
    }

    /// The gain of one track within its recording, in decibels. Only `work` reads the other tracks.
    /// A recording without any track gain plays at the album gain of the track.
    public func gain(for track: PlaybackTrack, in recording: [PlaybackTrack]) -> Float {
        guard self == .work else { return gain(for: track) }
        return RecordingGain.gain(of: recording) ?? Self.album.gain(for: track)
    }

    /// The gain for one track alone, in decibels. The peak limits a boost, so that no sample clips.
    public func gain(for track: PlaybackTrack) -> Float {
        if self == .work { return gain(for: track, in: [track]) }
        guard self != .off, let tags = track.replayGain else { return 0 }
        let album = (gain: tags.albumGain, peak: tags.albumPeak)
        let track = (gain: tags.trackGain, peak: tags.trackPeak)
        let (preferred, other) = self == .album ? (album, track) : (track, album)
        let chosen =
            preferred.gain != nil ? preferred : other.gain != nil ? other : (gain: tags.fallbackGain, peak: nil)
        guard let gain = chosen.gain else { return 0 }
        guard let peak = chosen.peak, peak > 0 else { return Float(gain) }
        return Float(min(gain, -20 * log10(peak)))
    }
}
