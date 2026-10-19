import Foundation

/// A span of years, such as the composition of a work. One year if `start == end`.
struct YearSpan: Codable, Equatable, Hashable, Sendable {
    var start: Int
    var end: Int

    init(_ start: Int, _ end: Int? = nil) {
        self.start = start
        self.end = max(end ?? start, start)
    }

    /// "1723", or "1829–1832".
    var text: String { start == end ? String(start) : "\(start)–\(end)" }

    /// The year of a MusicBrainz or Wikidata date such as "1723", "1829-10" or "+1725-00-00T00:00:00Z".
    static func year(of date: String?) -> Int? {
        guard var text = date?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        var sign = 1
        if text.hasPrefix("+") {
            text.removeFirst()
        } else if text.hasPrefix("-") {
            sign = -1
            text.removeFirst()
        }
        return Int(text.prefix { $0.isNumber }).map { sign * $0 }
    }
}

/// What MusicBrainz and Wikidata say about one work.
struct WorkFacts: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case musicBrainz, wikidata
    }

    /// The MusicBrainz ID of the work. A movement ID gives way to the ID of its work.
    var id: String
    var title: String
    var composed: YearSpan?
    var source: Source?
    var composerID: String?
}

/// A composer's dates from MusicBrainz.
struct ComposerFacts: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var born: Int?
    var died: Int?
}

/// A MusicBrainz work that a search found for a work without an ID.
struct WorkCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var score: Int
}

/// Reads works, composers and dates from the MusicBrainz web service.
/// MusicBrainz allows one request per second and asks for a User-Agent that names the client.
struct MusicBrainz: Sendable {
    /// Returns the body and the HTTP status.
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    static let base = URL(string: "https://musicbrainz.org/ws/2/")!
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Klassik/\(version) ( https://github.com/whnr/klassik )"
    }()

    var fetch: Fetch = MusicBrainz.network
    var pacer = Pacer.musicBrainz

    enum Failure: Error, Equatable {
        case http(Int)
    }

    /// The facts of a work. A movement walks up to its work: the facts then describe the whole work.
    /// Works in `known`, such as a composer's listed works, need no request.
    func work(id: String, known: [String: Work] = [:]) async throws -> WorkFacts? {
        func find(_ id: String) async throws -> Work? {
            if let work = known[id] { return work }
            return try await lookUp(id)
        }
        guard var work = try await find(id) else { return nil }
        var movement: Work?
        // Only a movement relation leads up. A plain part, such as one étude of a set, is a work of its own.
        for _ in 0..<3 {
            guard let parent = work.parentID, let found = try await find(parent) else { break }
            movement = movement ?? work
            work = found
        }
        let composed = work.composed ?? movement?.composed
        return WorkFacts(
            id: work.id, title: work.title, composed: composed, source: composed == nil ? nil : .musicBrainz,
            composerID: work.composerID ?? movement?.composerID)
    }

    func composer(id: String) async throws -> ComposerFacts? {
        let data = try await get("artist/\(id)", [])
        guard let data else { return nil }
        return try JSONDecoder().decode(Artist.self, from: data).facts
    }

    /// The composer of this name, if MusicBrainz knows exactly one person by it.
    func composer(named name: String) async throws -> ComposerFacts? {
        // An alias finds "Georg Friedrich Händel" and "Pjotr Iljitsch Tschaikowski".
        let name = Self.escape(name)
        let query = "(artist:\"\(name)\" OR alias:\"\(name)\") AND type:person"
        guard
            let data = try await get(
                "artist", [URLQueryItem(name: "query", value: query), .init(name: "limit", value: "3")])
        else { return nil }
        let artists = try JSONDecoder().decode(ArtistSearch.self, from: data).artists
        guard let top = artists.first, top.score == 100, artists.dropFirst().allSatisfy({ ($0.score ?? 0) < 100 })
        else { return nil }
        return top.facts
    }

    /// One page of the works of a composer, with their relations, and the number of all their works.
    func works(composerID: String, offset: Int) async throws -> (works: [Work], total: Int) {
        let query = [
            URLQueryItem(name: "artist", value: composerID), URLQueryItem(name: "inc", value: "artist-rels work-rels"),
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let data = try await get("work", query) else { return ([], 0) }
        let page = try JSONDecoder().decode(WorkPage.self, from: data)
        return (page.works, page.workCount)
    }

    static let pageSize = 100

    /// The listed works of a composer that can be the work with this tag title: the works that carry its
    /// catalogue number. Without such works, the works whose titles hold 80% of the other words of the tag title.
    /// `byCatalogue` tells which: two works with the same words are two works, not two spellings of one.
    static func candidates(in works: [Work], composerID: String, title: String) -> (
        found: [WorkCandidate], byCatalogue: Bool
    ) {
        let own = works.filter { $0.composerIDs.contains(composerID) }
        let catalogue = CatalogueNumber.find(in: title)
        if let catalogue {
            let found = own.filter { catalogue.matches($0.title) }
            if !found.isEmpty {
                return (found.map { WorkCandidate(id: $0.id, title: $0.title, score: 100) }.preferringWholeWorks, true)
            }
        }
        let wanted = words(title).subtracting(catalogue.map { words($0.text) } ?? [])
        // "Song in G major" must not match "Bourrée in G major": the words that name the piece must all be there.
        let naming = wanted.filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) && !genericWords.contains($0) }
        guard wanted.count >= 2, !naming.isEmpty else { return ([], false) }
        let wantedKey = key(of: title)
        let found = own.filter { work in
            let words = words(work.title)
            let found = key(of: work.title)
            return naming.isSubset(of: words) && (wantedKey == nil || found == nil || wantedKey == found)
                && Double(wanted.intersection(words).count) >= 0.8 * Double(wanted.count)
        }
        return (found.map { WorkCandidate(id: $0.id, title: $0.title, score: 100) }.preferringWholeWorks, false)
    }

    /// Works of the composer that carry the catalogue number, best first.
    func candidates(composer: String, catalogue: CatalogueNumber) async throws -> [WorkCandidate] {
        // MusicBrainz may spell the first name differently, such as "Fryderyk Chopin".
        let surname = composer.split(separator: " ").last.map(String.init) ?? composer
        let query = "\"\(Self.escape(catalogue.text))\" AND artist:\"\(Self.escape(surname))\""
        guard
            let data = try await get(
                "work", [URLQueryItem(name: "query", value: query), .init(name: "limit", value: "10")])
        else { return [] }
        return try JSONDecoder().decode(WorkSearch.self, from: data).works
            .filter { catalogue.matches($0.title) }
            .map { WorkCandidate(id: $0.id, title: $0.title, score: $0.score ?? 0) }
            .preferringWholeWorks
    }

    /// The candidate that Klassik takes without asking, for the work with this title in the tags.
    /// A good match with no good rival of another title wins: MusicBrainz holds some works twice, and scores an
    /// exact title as low as 75 when it spells the hyphens differently. Else the candidate whose title shares the
    /// most words with the tag title wins, if it shares 60% of them: a rival with the same catalogue number is
    /// mostly a spelling of the same work, sometimes a derived work such as a ballet. The words of the catalogue
    /// number do not count, because every candidate has them.
    static func confident(_ candidates: [WorkCandidate], for title: String) -> WorkCandidate? {
        guard let top = candidates.max(by: { $0.score < $1.score }), top.score >= 75 else { return nil }
        let lowered = top.title.lowercased()
        if candidates.allSatisfy({ $0.score < 75 || $0.title.lowercased() == lowered }) { return top }
        let wanted = words(title).subtracting(CatalogueNumber.find(in: title).map { words($0.text) } ?? [])
        guard !wanted.isEmpty else { return nil }
        let shared = { (candidate: WorkCandidate) in Double(wanted.intersection(words(candidate.title)).count) }
        let best = candidates.max { (shared($0), $0.score) < (shared($1), $1.score) }
        return best.flatMap { shared($0) / Double(wanted.count) >= 0.6 ? $0 : nil }
    }

    /// The key that a title names, such as "e flat major", in one spelling for all hyphens.
    static func key(of title: String) -> String? {
        let pattern = "\\b([A-Ga-g])(?:[-‐ ](flat|sharp))?\\s+(major|minor)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title))
        else { return nil }
        return (1...3).compactMap { Range(match.range(at: $0), in: title).map { title[$0].lowercased() } }
            .joined(separator: " ")
    }

    /// Words of keys and joins, which many titles share.
    static let genericWords: Set<String> = [
        "major", "minor", "flat", "sharp", "and", "for", "the", "dur", "moll", "und", "von",
    ]

    static func words(_ text: String) -> Set<String> {
        Set(
            text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    static func workURL(id: String) -> URL { URL(string: "https://musicbrainz.org/work/\(id)")! }

    static func searchURL(_ text: String) -> URL {
        var components = URLComponents(string: "https://musicbrainz.org/search")!
        components.queryItems = [URLQueryItem(name: "query", value: text), URLQueryItem(name: "type", value: "work")]
        return components.url!
    }

    // MARK: Requests

    private func lookUp(_ id: String) async throws -> Work? {
        guard let data = try await get("work/\(id)", [URLQueryItem(name: "inc", value: "work-rels artist-rels")]) else {
            return nil
        }
        return try JSONDecoder().decode(Work.self, from: data)
    }

    /// Returns nil for an ID or search that MusicBrainz does not know. A busy server gets two more tries.
    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data? {
        let url = Self.base.appending(path: path).appending(
            queryItems: query + [URLQueryItem(name: "fmt", value: "json")])
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for attempt in 0..<3 {
            await pacer.wait(extra: Double(attempt) * 2)
            let (data, status) = try await fetch(request)
            switch status {
            case 200..<300: return data
            case 400, 404: return nil
            case 503 where attempt < 2: continue
            default: throw Failure.http(status)
            }
        }
        return nil
    }

    static let network: Fetch = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Lucene treats these characters as syntax.
    static func escape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\\"+-!(){}[]^~*?:/&|".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    // MARK: JSON

    struct Work: Decodable, Sendable {
        struct Relation: Decodable, Sendable {
            struct Target: Decodable, Sendable {
                var id: String
            }
            var type: String
            var direction: String?
            var attributes: [String]?
            var begin: String?
            var end: String?
            var work: Target?
            var artist: Target?
        }
        var id: String
        var title: String
        var score: Int?
        var relations: [Relation]?

        /// The work that this movement belongs to.
        var parentID: String? {
            relations?.first {
                $0.type == "parts" && $0.direction == "backward" && $0.attributes?.contains("movement") == true
            }?
            .work?.id
        }

        private var composerRelations: [Relation] { relations?.filter { $0.type == "composer" } ?? [] }

        /// The composition date is the date of the composer relation.
        var composed: YearSpan? {
            composerRelations.lazy.compactMap { relation in
                YearSpan.year(of: relation.begin ?? relation.end).map {
                    YearSpan($0, YearSpan.year(of: relation.end))
                }
            }.first
        }

        var composerID: String? { composerRelations.first?.artist?.id }

        var composerIDs: [String] { composerRelations.compactMap(\.artist?.id) }
    }

    struct WorkPage: Decodable, Sendable {
        var works: [Work]
        var workCount: Int

        enum CodingKeys: String, CodingKey {
            case works
            case workCount = "work-count"
        }
    }

    struct WorkSearch: Decodable {
        var works: [Work]
    }

    struct Artist: Decodable {
        struct LifeSpan: Decodable {
            var begin: String?
            var end: String?
        }
        var id: String
        var name: String
        var score: Int?
        var lifeSpan: LifeSpan?

        enum CodingKeys: String, CodingKey {
            case id, name, score
            case lifeSpan = "life-span"
        }

        var facts: ComposerFacts {
            ComposerFacts(
                id: id, name: name, born: YearSpan.year(of: lifeSpan?.begin), died: YearSpan.year(of: lifeSpan?.end))
        }
    }

    struct ArtistSearch: Decodable {
        var artists: [Artist]
    }
}

extension [WorkCandidate] {
    /// A search often ranks a movement, such as "…, op. 35: IV. Finale", above its work. A colon marks the
    /// movement. If any candidate is a whole work, the movements drop. A movement alone stays: the lookup walks up.
    var preferringWholeWorks: [WorkCandidate] {
        let whole = filter { !$0.title.contains(":") }
        return whole.isEmpty ? self : whole
    }
}

/// Spaces requests to one service, so that all lookups together stay inside its rate limit.
actor Pacer {
    static let musicBrainz = Pacer(interval: 1.1)
    static let wikidata = Pacer(interval: 1.1)

    private let interval: Double
    private var next = ContinuousClock.now

    init(interval: Double) {
        self.interval = interval
    }

    func wait(extra: Double = 0) async {
        let start = max(next, .now) + .seconds(extra)
        next = start + .seconds(interval)
        try? await Task.sleep(until: start)
    }
}
