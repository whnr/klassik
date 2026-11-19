import Foundation

/// The search of the Search place over the work index (ADR 0025, 0029). It finds works, people and albums by word
/// starts, with case and diacritics folded. It knows no catalogue prefixes and no aliases (ADR 0025): "op67" does
/// not find "Op. 67", and "K. 626" does not find "KV 626".
struct Search: Sendable {
    /// A composer or performer, with one count for each role, the biggest first (ADR 0031).
    struct Person: Identifiable, Sendable, Equatable {
        struct Role: Sendable, Equatable {
            /// "composer", or a role label as tagged, such as "conductor" or "violin".
            var label: String
            var count: Int
            /// True for the composer role, which counts works. Every other role counts recordings.
            var countsWorks: Bool

            var text: String {
                countsWorks
                    ? "\(label) of \(WorkIndex.Recording.count(count, "work"))"
                    : "\(label) on \(WorkIndex.Recording.count(count, "recording"))"
            }
        }

        var name: String
        var roles: [Role]
        /// The recordings that name the person in any role. People who are in more of the library come first.
        var recordings: Int
        var id: String { name }

        /// True when the index holds works of the person, so the row opens the composer page.
        var composes: Bool { roles.contains(where: \.countsWorks) }

        /// "Conductor on 212 recordings, composer of 30 works and violin on 3 recordings".
        func counts(locale: Locale = .current) -> String {
            let text = Roles.Line.list(roles.map(\.text), locale: locale)
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }

    /// The results in their sections, in the order of the page: works, people, albums.
    struct Results: Sendable {
        var works: [WorkIndex.Work] = []
        var people: [Person] = []
        var albums: [WorkIndex.Album] = []

        var isEmpty: Bool { works.isEmpty && people.isEmpty && albums.isEmpty }
    }

    private struct Entry<Item: Sendable>: Sendable {
        var item: Item
        var words: [String]
    }

    private struct WorkEntry: Sendable {
        var work: WorkIndex.Work
        /// The words of the title, the composer and the set.
        var words: [String]
        var titleWords: [String]
        var title: String
    }

    private let works: [WorkEntry]
    private let people: [Entry<Person>]
    private let albums: [Entry<WorkIndex.Album>]

    init(index: WorkIndex) {
        // A work without a composer tag is found by its title. The stand-in name finds nothing.
        let composers = index.composers.filter { $0.name != Song.unknownComposer }
        // An untagged work stands for an album. The Albums section holds it.
        works = index.composers.flatMap(\.works).filter(\.isTagged).map { work in
            let composer = work.composer == Song.unknownComposer ? "" : work.composer
            return WorkEntry(
                work: work,
                words: Self.words(of: [work.title, composer, work.grouping ?? ""].joined(separator: " ")),
                titleWords: Self.words(of: work.title), title: Self.fold(work.title))
        }

        // The composer role sorts before every role kind when two counts are equal.
        var roles: [String: [String: (count: Int, order: Int)]] = [:]
        var recordings: [String: Set<String>] = [:]
        for composer in composers {
            roles[composer.name, default: [:]]["composer"] = (composer.works.count, -1)
            recordings[composer.name, default: []].formUnion(composer.works.flatMap(\.recordings).map(\.id))
        }
        for work in index.composers.flatMap(\.works) {
            for recording in work.recordings {
                for line in recording.principalNames {
                    for name in line.names {
                        roles[name, default: [:]][line.label, default: (0, line.kind.rawValue)].count += 1
                        recordings[name, default: []].insert(recording.id)
                    }
                }
            }
        }
        people = roles.map { name, roles in
            let ordered = roles.sorted {
                ($1.value.count, $0.value.order, $0.key) < ($0.value.count, $1.value.order, $1.key)
            }
            let person = Person(
                name: name,
                roles: ordered.map {
                    Person.Role(label: $0.key, count: $0.value.count, countsWorks: $0.value.order < 0)
                },
                recordings: recordings[name]?.count ?? 0)
            return Entry(item: person, words: Self.words(of: name))
        }
        .sorted {
            $0.item.recordings != $1.item.recordings
                ? $0.item.recordings > $1.item.recordings
                : $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending
        }

        albums = index.albums.map { album in
            let artist = Self.artist(of: album) ?? ""
            let titles = album.tracks.map(\.title)
            return Entry(item: album, words: Self.words(of: ([album.title, artist] + titles).joined(separator: " ")))
        }
    }

    /// The results for a text. An empty text finds nothing; the page then shows its hint.
    func results(for text: String) -> Results {
        let tokens = Self.words(of: text, unique: false)
        guard !tokens.isEmpty else { return Results() }
        // A title that starts with the text comes first, then a title that holds every word, then a match on the
        // composer or the set only (search.html).
        let ranked: [(work: WorkIndex.Work, rank: Int)] = works.filter { Self.matches(tokens, $0.words) }
            .map { entry in (entry.work, Self.rank(of: entry, for: tokens)) }
        let found = ranked.sorted { lhs, rhs in
            lhs.rank != rhs.rank
                ? lhs.rank < rhs.rank
                : lhs.work.title.localizedStandardCompare(rhs.work.title) == .orderedAscending
        }
        return Results(
            works: found.map { $0.work },
            people: people.filter { Self.matches(tokens, $0.words) }.map(\.item),
            albums: albums.filter { Self.matches(tokens, $0.words) }.map(\.item))
    }

    private static func rank(of entry: WorkEntry, for tokens: [String]) -> Int {
        if entry.title.hasPrefix(tokens[0]) { return 0 }
        return matches(tokens, entry.titleWords) ? 1 : 2
    }

    /// The name under the album title: the album artist, else the track artist.
    static func artist(of album: WorkIndex.Album) -> String? {
        let first = album.tracks.first
        return [first?.displayAlbumArtist, first?.artist].lazy.compactMap { $0 }.first { !$0.isEmpty }
    }

    /// Lower case without diacritics. Letters that do not decompose fold by hand, so "Dvořák" meets "dvorak" and
    /// "Søren" meets "soren".
    static func fold(_ text: String) -> String {
        var folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        for (letter, plain) in [("ø", "o"), ("ł", "l"), ("đ", "d"), ("ß", "ss"), ("æ", "ae"), ("œ", "oe")] {
            folded = folded.replacingOccurrences(of: letter, with: plain)
        }
        return folded
    }

    /// The folded words of a text. Every character that is not a letter or a digit splits two words.
    static func words(of text: String, unique: Bool = true) -> [String] {
        let words = fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard unique else { return words }
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }

    /// True when each token starts a word.
    static func matches(_ tokens: [String], _ words: [String]) -> Bool {
        tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
    }
}
