import Foundation

/// Decides which part of the library is classical. The listener can edit the rules; they stay on the device.
/// A track matches if any rule matches; a rule matches if all of its conditions match.
struct ClassicalFilter: Codable, Equatable, Sendable {
    struct Condition: Codable, Equatable, Identifiable, Sendable {
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
        /// An empty text matches no track, so that a half-typed condition does not let the whole library in.
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

    struct Rule: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        var conditions: [Condition]

        static func == (a: Self, b: Self) -> Bool { a.conditions == b.conditions }

        func matches(_ song: Song) -> Bool {
            !conditions.isEmpty && conditions.allSatisfy { $0.matches(song) }
        }
    }

    /// Work and composer tags alone also occur outside classical music, so they need a second condition.
    var rules = [
        Rule(conditions: [Condition(kind: .genreContains, text: "Classical")]),
        Rule(conditions: [Condition(kind: .genreContains, text: "Klassik")]),
        Rule(conditions: [Condition(kind: .hasWork), Condition(kind: .hasMovement)]),
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

    var allGenres: [String] { (genres ?? []).map(\.name) + [genre].compactMap(\.self) }
}
