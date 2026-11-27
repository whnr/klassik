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

extension WorkIndex.Recording {
    /// The tracks that play at one level with a movement. A recording is one work, so all its tracks do. A whole
    /// album holds several works: its tracks that name the same work do, and the tracks without a work tag do.
    func levelGroup(of movement: Int) -> [PlaybackTrack] {
        guard isAlbum, songs.indices.contains(movement) else { return songs.map(\.playbackTrack) }
        let key = Self.levelKey(songs[movement])
        return songs.filter { Self.levelKey($0) == key }.map(\.playbackTrack)
    }

    private static func levelKey(_ song: Song) -> String {
        song.works?.first == nil ? "" : WorkIndex.workKey(song)
    }
}

extension ServerTrouble {
    /// The quiet status of a playback failure, or nil when the device failed (ADR 0060). A policy that forbids the
    /// network shows as no answer.
    init?(playback error: any Error) {
        if (error as? TrackStore.Failure) == .offline {
            self = .unreachable
        } else if error is SubsonicError {
            self = .refused
        } else if let failure = TransferFailureMapper().serverFailure(for: error) {
            self.init(engine: failure)
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
