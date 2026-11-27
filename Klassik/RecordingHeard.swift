import Foundation

extension Song {
    /// `played` as a date. The server sends nanoseconds; a second is exact enough for "last heard".
    var lastPlayed: Date? {
        guard let played else { return nil }
        return try? Date(played.replacing(/\.\d+/, with: ""), strategy: .iso8601)
    }
}

extension WorkIndex.Recording {
    /// Heard when more than half the movements have a server play count. The server counts a play only when the
    /// listener heard the track, so Scrobbles off leaves no new plays and this keeps showing the server state.
    var isHeard: Bool {
        let played = songs.filter { ($0.playCount ?? 0) > 0 }.count
        return played * 2 > songs.count
    }

    /// The newest `played` of the tracks.
    var lastHeard: Date? { songs.compactMap(\.lastPlayed).max() }
}
