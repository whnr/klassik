import Foundation

/// The names of tracks, one line per role (ADR 0031). The page shows what every track shares, and a row shows what
/// its track adds.
enum Roles {
    /// The musical roles in page order. Names without a role come last.
    enum Kind: Int, Comparable, Sendable {
        case conductor
        case soloist
        case ensemble
        case arranger
        case lyricist
        /// A role tag that Klassik does not know, such as "director". The tag is the label.
        case other
        case unlabelled

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The roles that make a recording recognisable.
        var isPrincipal: Bool { self <= .ensemble }
    }

    /// The names of one role. A name that holds a comma takes its own row, so a list cannot split it.
    struct Line: Hashable, Sendable, Identifiable {
        struct Row: Hashable, Sendable {
            var label: String
            var text: String
        }

        var kind: Kind
        var label: String
        var names: [String]
        var id: String { "\(kind.rawValue)|\(label)" }

        func rows(locale: Locale = .current) -> [Row] {
            if names.contains(where: { $0.contains(",") }) {
                return names.map { Row(label: label, text: $0) }
            }
            return [Row(label: label, text: Self.list(names, locale: locale))]
        }

        static func list(_ names: [String], locale: Locale = .current) -> String {
            let formatter = ListFormatter()
            formatter.locale = locale
            return formatter.string(from: names) ?? names.joined(separator: " ")
        }
    }

    /// The names that every track shares, and for each track the names that it adds. `tracks` has one entry for each
    /// input track, in input order.
    struct Split: Sendable {
        var shared: [Line]
        var tracks: [[Line]]
    }

    /// Roles that never show in a name line. The raw tags view has them. A role not listed shows under its own tag.
    /// "artist" and "albumartist" repeat the artist tag, which the fallback below reads.
    private static let hidden: Set<String> = [
        "composer", "producer", "engineer", "mixer", "djmixer", "remixer", "artist", "albumartist",
    ]

    /// All names of the tracks. Technical roles (producer, engineer, mixer) are not here; the raw tags view has them.
    static func lines(of songs: [Song]) -> [Line] {
        lines(from: songs.flatMap(entries(of:)))
    }

    static func split(_ songs: [Song]) -> Split {
        let perTrack = songs.map(entries(of:))
        guard var common = perTrack.first.map({ Set($0.map(\.key)) }) else { return Split(shared: [], tracks: []) }
        for entries in perTrack.dropFirst() { common.formIntersection(entries.map(\.key)) }
        let shared = lines(from: perTrack.flatMap { $0 }.filter { common.contains($0.key) })
        let tracks = perTrack.map { entries in lines(from: entries.filter { !common.contains($0.key) }) }
        return Split(shared: shared, tracks: tracks)
    }

    // MARK: - Reading the tags

    /// A name in a role. The label is the instrument or group that the tag names; it does not make a name different.
    private struct Entry: Sendable {
        var kind: Kind
        var label: String
        var name: String
        var key: String { "\(kind.rawValue)|\(name)" }
    }

    private static func entries(of song: Song) -> [Entry] {
        var result: [Entry] = []
        for contributor in (song.contributors ?? []).sorted(by: { precedes($0, $1, in: song) }) {
            let name = contributor.artist.name
            guard !name.isEmpty else { continue }
            let sub = (contributor.subRole ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let role = contributor.role.trimmingCharacters(in: .whitespaces).lowercased()
            switch role {
            case "conductor": result.append(Entry(kind: .conductor, label: "conductor", name: name))
            case "arranger": result.append(Entry(kind: .arranger, label: "arranger", name: name))
            case "lyricist": result.append(Entry(kind: .lyricist, label: "lyricist", name: name))
            case "performer":
                if contributor.isEnsemble {
                    result.append(Entry(kind: .ensemble, label: sub.isEmpty ? "ensemble" : sub, name: name))
                } else {
                    result.append(Entry(kind: .soloist, label: sub.isEmpty ? "soloist" : sub, name: name))
                }
            case _ where hidden.contains(role) || role.isEmpty: continue
            default: result.append(Entry(kind: .other, label: sub.isEmpty ? role : "\(role) \(sub)", name: name))
            }
        }
        // A track with no performer names its artist as tagged, unless a name above already stands in that tag.
        // Navidrome often lists the conductor but not the orchestra that the artist tag names.
        let hasPerformer = result.contains { $0.kind == .soloist || $0.kind == .ensemble }
        if !hasPerformer, let artist = song.artist, !artist.isEmpty,
            !result.contains(where: { Self.names($0.name, in: artist) })
        {
            result.append(Entry(kind: .unlabelled, label: "", name: artist))
        }
        return result
    }

    /// Navidrome returns the contributors of a track in a different order after each scan. The order of the names in
    /// the track's artist tag comes first, then the sort name, then the name and the ID, so the result never changes.
    private static func precedes(_ lhs: Song.Contributor, _ rhs: Song.Contributor, in song: Song) -> Bool {
        let left = (rank(lhs, in: song), sortKey(lhs.artist), lhs.artist.name, lhs.artist.id)
        let right = (rank(rhs, in: song), sortKey(rhs.artist), rhs.artist.name, rhs.artist.id)
        if left.0 != right.0 { return left.0 < right.0 }
        if left.1 != right.1 { return left.1.localizedStandardCompare(right.1) == .orderedAscending }
        if left.2 != right.2 { return left.2.localizedStandardCompare(right.2) == .orderedAscending }
        return left.3 < right.3
    }

    private static func names(_ name: String, in tag: String) -> Bool {
        tag.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// One form for every name: the server's sort name, else the name with its last word first. Mixing forms would
    /// compare "Kubelík, Rafael" with "Rafael Kubelík".
    private static func sortKey(_ artist: Song.Artist) -> String {
        if let sort = artist.sortName, !sort.isEmpty { return sort }
        let words = artist.name.split(separator: " ")
        guard let last = words.last, words.count > 1 else { return artist.name }
        return "\(last), \(words.dropLast().joined(separator: " "))"
    }

    private static func rank(_ contributor: Song.Contributor, in song: Song) -> Int {
        guard let tag = song.artist,
            let found = tag.range(of: contributor.artist.name, options: [.caseInsensitive, .diacriticInsensitive])
        else { return Int.max }
        return tag.distance(from: tag.startIndex, to: found.lowerBound)
    }

    /// Groups entries by role. A name shows once in a role, under the label of its first appearance. Roles keep the
    /// order of the page, and names keep the order of the tracks.
    private static func lines(from entries: [Entry]) -> [Line] {
        var seen = Set<String>()
        var lines: [Line] = []
        for entry in entries where seen.insert(entry.key).inserted {
            if let index = lines.firstIndex(where: { $0.kind == entry.kind && $0.label == entry.label }) {
                lines[index].names.append(entry.name)
            } else {
                lines.append(Line(kind: entry.kind, label: entry.label, names: [entry.name]))
            }
        }
        return lines.enumerated().sorted { ($0.element.kind, $0.offset) < ($1.element.kind, $1.offset) }.map(\.element)
    }
}

extension Song.Contributor {
    /// Words that start a group name: "orchestra", "Philharmoniker", "Kammerorchester", "Symphony".
    private static let groupStems = [
        "orchest", "philharmon", "symphon", "sinfon", "kammerorch", "kammerchor", "kammerens", "ensemble",
        "quartet", "quintet", "sextet", "consort",
        "choir", "chorus", "camerata", "collegium",
    ]
    /// Short words that count only as a whole word, so "Chorley" stays a person.
    private static let groupWords: Set = ["chor", "trio", "duo", "band", "orchestre"]

    /// The tag names a group for an ensemble and an instrument for a soloist. Without a group in the tag, a group
    /// word in the name decides.
    var isEnsemble: Bool {
        let sub = (subRole ?? "").lowercased()
        if Self.groupStems.contains(where: { sub.contains($0) }) { return true }
        let tokens = artist.name.lowercased().split { !$0.isLetter }.map(String.init)
        return tokens.contains { token in
            Self.groupWords.contains(token) || Self.groupStems.contains { token.hasPrefix($0) }
        }
    }
}
