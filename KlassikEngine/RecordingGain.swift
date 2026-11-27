import Foundation

/// One gain for all movements of a recording, so that they keep the loudness steps that the composer and the
/// performers made.
public enum RecordingGain {
    /// The gain of the recording in decibels, or nil when no track has a track gain.
    ///
    /// A track gain is the level that brings the loudness of its track to the reference. The loudness of the whole
    /// recording is the duration-weighted mean of the track loudnesses in the power domain, the way a scan measures
    /// an album. A track without a gain adds nothing to the mean and still plays at the result. A track gain and
    /// its peak are the only inputs: an album gain describes another set of tracks. The highest peak of any track
    /// limits the result, so that the loudest movement does not clip.
    public static func gain(of tracks: [PlaybackTrack]) -> Float? {
        let measured = tracks.compactMap { track -> (gain: Double, seconds: Double)? in
            guard let gain = track.replayGain?.trackGain, gain.isFinite else { return nil }
            return (gain, Double(track.duration ?? 0))
        }
        guard !measured.isEmpty else { return nil }
        // A track without a duration weighs as much as the average of the others.
        let known = measured.map(\.seconds).filter { $0 > 0 }
        let unknownWeight = known.isEmpty ? 1 : known.reduce(0, +) / Double(known.count)
        var weights = 0.0
        var power = 0.0
        for (gain, seconds) in measured {
            let weight = seconds > 0 ? seconds : unknownWeight
            weights += weight
            power += weight * pow(10, -gain / 10)
        }
        let gain = -10 * log10(power / weights)
        guard let peak = highestPeak(of: tracks) else { return Float(gain) }
        return Float(min(gain, -20 * log10(peak)))
    }

    /// The highest peak of the tracks. A track without its own peak counts with the peak of its album, which no
    /// track of that album exceeds.
    private static func highestPeak(of tracks: [PlaybackTrack]) -> Double? {
        var highest: Double?
        for track in tracks {
            guard let tags = track.replayGain, let peak = tags.trackPeak ?? tags.albumPeak else { continue }
            if peak > 0, peak.isFinite, peak > (highest ?? 0) { highest = peak }
        }
        return highest
    }
}
