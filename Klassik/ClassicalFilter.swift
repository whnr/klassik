import Foundation

/// Decides which part of the library is classical. The listener can edit the rule; it stays on the device.
struct ClassicalFilter: Codable, Equatable, Sendable {
    /// Matches anywhere in a genre and ignores case: tags such as "Classical > Orchestral" are one value.
    var genre = "Classical"
    var work = true
    var composer = true

    /// A track matches if any enabled rule matches.
    func matches(_ song: Song) -> Bool {
        let needle = genre.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            let genres = (song.genres ?? []).map(\.name) + [song.genre].compactMap(\.self)
            if genres.contains(where: { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                return true
            }
        }
        if work, song.works?.isEmpty == false { return true }
        if composer, song.displayComposer?.isEmpty == false || song.contributors?.contains(where: { $0.role == "composer" }) == true {
            return true
        }
        return false
    }

    /// The classical tracks. An album counts if most of its tracks match, and then all of its tracks count.
    func classical(_ songs: [Song]) -> [Song] {
        let albums = Dictionary(grouping: songs) { $0.albumKey }
        let classicalAlbums = Set(albums.compactMap { key, tracks in
            tracks.filter(matches).count * 2 > tracks.count ? key : nil
        })
        return songs.filter { classicalAlbums.contains($0.albumKey) }
    }
}

extension Song {
    /// Groups tracks into albums. A track without an album is an album of its own.
    var albumKey: String { albumId ?? album ?? id }
}
