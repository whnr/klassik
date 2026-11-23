import Foundation

/// Decides which part of the library is classical. The listener edits its classical rules; they stay on the device.
/// A track matches if any classical rule matches; a classical rule matches if all of its checks match. "Condition"
/// belongs to search only.
struct ClassicalFilter: Codable, Equatable, Sendable {
    /// One test in a classical rule, such as "Genre contains Classical".
    struct Check: Codable, Equatable, Identifiable, Sendable {
        enum Kind: String, Codable, CaseIterable, Sendable {
            case genreContains, genreDoesNotContain, hasWork, hasMovement, hasComposer

            var title: String {
                switch self {
                case .genreContains: "Genre contains"
                case .genreDoesNotContain: "Genre does not contain"
                case .hasWork: "Has a work"
                case .hasMovement: "Has a movement"
                case .hasComposer: "Has a composer"
                }
            }

            var takesText: Bool { self == .genreContains || self == .genreDoesNotContain }
        }

        var id = UUID()
        var kind: Kind
        var text = ""

        static func == (a: Self, b: Self) -> Bool { a.kind == b.kind && a.text == b.text }

        /// Genre text matches anywhere and ignores case: tags such as "Classical > Orchestral" are one value.
        /// An empty text matches no track, so that a half-typed check does not let the whole library in.
        func matches(_ song: Song) -> Bool {
            let needle = text.trimmingCharacters(in: .whitespaces)
            switch kind {
            case .genreContains:
                return !needle.isEmpty && song.allGenres.contains { $0.range(of: needle, options: Self.options) != nil }
            case .genreDoesNotContain:
                return !needle.isEmpty
                    && !song.allGenres.contains { $0.range(of: needle, options: Self.options) != nil }
            case .hasWork:
                return song.works?.isEmpty == false
            case .hasMovement:
                return song.movements?.isEmpty == false
            case .hasComposer:
                return song.displayComposer?.isEmpty == false
                    || song.contributors?.contains { $0.role == "composer" } == true
            }
        }

        private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    }

    /// A classical rule.
    struct Rule: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        var checks: [Check]

        /// The saved rules keep their checks under "conditions", so the key stays and saved rules still load.
        private enum CodingKeys: String, CodingKey {
            case id
            case checks = "conditions"
        }

        static func == (a: Self, b: Self) -> Bool { a.checks == b.checks }

        func matches(_ song: Song) -> Bool {
            !checks.isEmpty && checks.allSatisfy { $0.matches(song) }
        }
    }

    /// Work and composer tags alone also occur outside classical music, so they need a second check.
    var rules = [
        Rule(checks: [Check(kind: .genreContains, text: "Classical")]),
        Rule(checks: [Check(kind: .genreContains, text: "Klassik")]),
        Rule(checks: [Check(kind: .hasWork), Check(kind: .hasMovement)]),
    ]

    func matches(_ song: Song) -> Bool {
        rules.contains { $0.matches(song) }
    }

    /// The classical tracks. An album counts if most of its tracks match, and then all of its tracks count.
    func classical(_ songs: [Song]) -> [Song] {
        let albums = Dictionary(grouping: songs) { $0.albumKey }
        let classicalAlbums = Set(
            albums.compactMap { key, tracks in
                tracks.filter(matches).count * 2 > tracks.count ? key : nil
            })
        return songs.filter { classicalAlbums.contains($0.albumKey) }
    }
}

extension Song {
    /// Groups tracks into albums. A track without an album is an album of its own.
    var albumKey: String { albumId ?? album ?? id }

    /// The server sends the first genre twice: as `genre` and in `genres`.
    var allGenres: [String] {
        var seen = Set<String>()
        return ((genres ?? []).map(\.name) + [genre].compactMap(\.self)).filter { seen.insert($0).inserted }
    }
}
