import Foundation

extension Song {
    /// True when the disc and track numbers cannot order these tracks: two tracks share both numbers
    /// but differ in title or folder. A file that the server holds twice has the same title and folder.
    static func collides(_ songs: [Song]) -> Bool {
        var first: [String: Song] = [:]
        for song in songs {
            let key = "\(song.discNumber ?? 0)|\(song.track ?? 0)"
            guard let other = first[key] else {
                first[key] = song
                continue
            }
            if other.title != song.title || other.folder != song.folder { return true }
        }
        return false
    }

    /// Disc and track order. Where the disc tags collide, such as a box with every disc tagged Disc 1,
    /// the file path orders the tracks, because the folders and file names of a box keep its real order.
    /// The server's own order breaks a tie, so a track without a path keeps its place.
    static func playOrder(_ songs: [Song]) -> [Song] {
        let indexed = songs.enumerated().map { (index: $0.offset, song: $0.element) }
        if collides(songs), songs.contains(where: { $0.path != nil }) {
            return indexed.sorted { left, right in
                let a = left.song.path ?? "", b = right.song.path ?? ""
                let result = a.compare(b, options: [.numeric, .caseInsensitive])
                if result != .orderedSame { return result == .orderedAscending }
                return (left.index, left.song.id) < (right.index, right.song.id)
            }.map(\.song)
        }
        return indexed.sorted {
            ($0.song.discNumber ?? 0, $0.song.track ?? 0, $0.song.id, $0.index)
                < ($1.song.discNumber ?? 0, $1.song.track ?? 0, $1.song.id, $1.index)
        }.map(\.song)
    }

    private var folder: String {
        guard let path else { return "" }
        return (path as NSString).deletingLastPathComponent
    }
}
