import Foundation
import KlassikEngine

extension Song {
    /// What the playback engine reads of this track.
    var playbackTrack: PlaybackTrack {
        PlaybackTrack(
            id: id, duration: duration, suffix: suffix, bitRate: bitRate, samplingRate: samplingRate,
            bitDepth: bitDepth, channelCount: channelCount,
            replayGain: replayGain.map {
                PlaybackTrack.ReplayGain(
                    trackGain: $0.trackGain, albumGain: $0.albumGain, trackPeak: $0.trackPeak,
                    albumPeak: $0.albumPeak, fallbackGain: $0.fallbackGain)
            })
    }
}

extension ServerTrouble {
    /// The quiet status of a playback failure, or nil when the device failed (ADR 0060). A policy that forbids the
    /// network shows as no answer.
    init?(playback error: any Error) {
        if error is URLError || (error as? TrackStore.Failure) == .offline {
            self = .unreachable
        } else if let failure = error as? TrackTransfer.Failure {
            switch failure {
            case .timedOut, .truncated: self = .unreachable
            case .http: self = .refused
            default: return nil
            }
        } else if error is SubsonicError {
            self = .refused
        } else {
            return nil
        }
    }

    init(engine failure: PlaybackServerFailure) {
        switch failure {
        case .unreachable: self = .unreachable
        case .refused: self = .refused
        }
    }
}

/// Names the server failures that the engine cannot know: the app's own errors.
struct AppFailureMapper: PlaybackFailureMapper {
    func serverFailure(for error: any Error) -> PlaybackServerFailure? {
        switch ServerTrouble(playback: error) {
        case .unreachable: .unreachable
        case .refused: .refused
        case nil: nil
        }
    }
}
