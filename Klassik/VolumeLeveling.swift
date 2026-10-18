import Foundation

/// Which ReplayGain value sets the playback volume.
enum VolumeLeveling: String, CaseIterable, Identifiable, Sendable {
    /// One gain for the whole album keeps the loudness steps between movements.
    case album
    case track
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .album: "Album"
        case .track: "Track"
        case .off: "Off"
        }
    }

    /// The gain for one track, in decibels. The peak limits a boost, so that no sample clips.
    func gain(for song: Song) -> Float {
        guard self != .off, let tags = song.replayGain else { return 0 }
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
