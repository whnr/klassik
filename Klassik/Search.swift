import Foundation
import Observation

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

    /// The results of the text, by kind: composers, performers, works, then albums (ADR 0067). A recording shows
    /// only inside its work.
    struct Results: Sendable {
        var works: [WorkIndex.Work] = []
        var people: [Person] = []
        var albums: [WorkIndex.Album] = []
        /// The track title that found a work or an album whose own words do not match, by the ID of the result.
        /// The row shows it, so the listener sees why the result is there.
        var workTracks: [String: String] = [:]
        var albumTracks: [String: String] = [:]

        var composers: [Person] { people.filter(\.composes) }
        var performers: [Person] { people.filter { !$0.composes } }

        var isEmpty: Bool { works.isEmpty && people.isEmpty && albums.isEmpty }
    }

    private struct Entry<Item: Sendable>: Sendable {
        var item: Item
        var words: [String]
    }

    /// A track title with its words.
    private struct Track: Sendable {
        var title: String
        var words: [String]
    }

    /// A work or an album with its own words and the titles of the tracks that it answers for.
    private struct Tracked<Item: Sendable>: Sendable {
        var item: Item
        var words: [String]
        var tracks: [Track]
        /// The words of every track, for a fast test before the search for the one track that matches.
        var trackWords: [String]

        init(item: Item, words: [String], titles: [String]) {
            self.item = item
            self.words = words
            var seen = Set<String>()
            tracks = titles.filter { seen.insert($0).inserted }.map { Track(title: $0, words: Search.words(of: $0)) }
            var all = Set(words)
            trackWords = tracks.flatMap(\.words).filter { all.insert($0).inserted }
        }

        /// Nil when the tokens do not match. Else the track title that the match needs, or "" for a match on the
        /// own words.
        func match(_ tokens: [String]) -> String? {
            if Search.matches(tokens, words) { return "" }
            guard Search.matches(tokens, words, trackWords) else { return nil }
            return tracks.first { Search.matches(tokens, words, $0.words) }?.title
        }
    }

    private struct WorkEntry: Sendable {
        var tracked: Tracked<WorkIndex.Work>
        var titleWords: [String]
        var title: String
    }

    private let works: [WorkEntry]
    private let people: [Entry<Person>]
    private let albums: [Tracked<WorkIndex.Album>]

    init(index: WorkIndex) {
        // A work without a composer tag is found by its title. The stand-in name finds nothing.
        let composers = index.composers.filter { $0.name != Song.unknownComposer }
        // An untagged work stands for an album. The Albums section holds it.
        works = index.composers.flatMap(\.works).filter(\.isTagged).map { work in
            let composer = work.composer == Song.unknownComposer ? "" : work.composer
            // A track title can name the work where the WORK tag does not, such as "Für Elise" for WoO 59.
            return WorkEntry(
                tracked: Tracked(
                    item: work,
                    words: Self.words(of: [work.title, composer, work.grouping ?? ""].joined(separator: " ")),
                    titles: work.recordings.flatMap(\.songs).map(\.title)),
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

        // A tagged track belongs to its work, so only a track without a WORK tag finds its album (ADR 0025).
        albums = index.albums.map { album in
            Tracked(
                item: album, words: Self.words(of: [album.title, Self.artist(of: album) ?? ""].joined(separator: " ")),
                titles: album.tracks.filter { $0.works?.first == nil }.map(\.title))
        }
    }

    /// The results for a text. An empty text finds nothing; the page then shows its hint.
    func results(for text: String) -> Results {
        let tokens = Self.words(of: text, unique: false)
        guard !tokens.isEmpty else { return Results() }
        // A title that starts with the text comes first, then a title that holds every word, then a match on the
        // composer or the set, then a match that needs a track title (search.html).
        var results = Results()
        var ranked: [(work: WorkIndex.Work, rank: Int)] = []
        for entry in works {
            guard let track = entry.tracked.match(tokens) else { continue }
            let work = entry.tracked.item
            if track.isEmpty {
                ranked.append((work, Self.rank(of: entry, for: tokens)))
            } else {
                ranked.append((work, 3))
                results.workTracks[work.id] = track
            }
        }
        results.works = ranked.sorted { lhs, rhs in
            lhs.rank != rhs.rank
                ? lhs.rank < rhs.rank
                : lhs.work.title.localizedStandardCompare(rhs.work.title) == .orderedAscending
        }
        .map(\.work)
        results.people = people.filter { Self.matches(tokens, $0.words) }.map(\.item)
        for entry in albums {
            guard let track = entry.match(tokens) else { continue }
            results.albums.append(entry.item)
            if !track.isEmpty { results.albumTracks[entry.item.id] = track }
        }
        return results
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

    /// True when each token starts a word of either list.
    static func matches(_ tokens: [String], _ words: [String], _ more: [String]) -> Bool {
        tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } || more.contains { $0.hasPrefix(token) } }
    }
}

/// The results that the Search page shows while the text changes. Each text searches off the main actor, so a
/// keystroke never waits for a search. The results of an older text never replace those of a newer one, and a text
/// that was searched before over the same index shows its results at once.
@MainActor @Observable
final class LiveSearch {
    /// The text that `results` belong to.
    private(set) var text = ""
    private(set) var results = Search.Results()
    /// The newest text asked for.
    @ObservationIgnored private var latest = ""
    @ObservationIgnored private var version: Int?
    @ObservationIgnored private var cache: [String: Search.Results] = [:]
    private static let cacheLimit = 64

    /// True when `results` belong to this text, so an empty result means no match and not a search that runs.
    func isShowing(_ text: String) -> Bool { self.text == text }

    /// Shows the results for a text over the index of a version. `find` runs the search.
    func show(_ text: String, version: Int, find: @MainActor (String) async -> Search.Results) async {
        latest = text
        if version != self.version {
            self.version = version
            cache = [:]
        }
        if Search.words(of: text, unique: false).isEmpty { return apply(Search.Results(), for: text) }
        if let cached = cache[text] { return apply(cached, for: text) }
        guard !Task.isCancelled else { return }
        let found = await find(text)
        guard version == self.version else { return }
        if cache.count >= Self.cacheLimit { cache = [:] }
        cache[text] = found
        guard text == latest else { return }
        apply(found, for: text)
    }

    private func apply(_ results: Search.Results, for text: String) {
        self.text = text
        self.results = results
    }
}
