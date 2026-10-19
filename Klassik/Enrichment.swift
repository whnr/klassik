import Foundation
import Observation

/// Composition dates, MusicBrainz links and composer dates for the works of the library.
/// Tags are the truth: this only fills gaps. Facts are cached by MusicBrainz ID and fetched once.
/// The listener's own years stay on the device and win over every source.
@MainActor @Observable
final class Enrichment {
    struct Cache: Codable, Sendable {
        /// Facts by the MusicBrainz ID that the tag or the search gave.
        var works: [String: WorkFacts] = [:]
        /// IDs that MusicBrainz does not know.
        var unknownIDs: Set<String> = []
        /// MusicBrainz IDs of works without one in the tags, by Klassik work ID: a clear match or the
        /// listener's choice.
        var links: [String: String] = [:]
        /// Matches that the listener must confirm once, by Klassik work ID.
        var candidates: [String: [WorkCandidate]] = [:]
        /// Klassik work IDs that found no match, or whose match the listener turned down.
        var unmatched: Set<String> = []
        var composers: [String: ComposerFacts] = [:]
        /// MusicBrainz artist IDs by the composer name in the tags.
        var composerIDs: [String: String] = [:]
        var unknownComposers: Set<String> = []
        /// Composition years that the listener typed, by Klassik work ID.
        var years: [String: Int] = [:]
        /// MusicBrainz IDs of undated works that Wikidata was asked about.
        var askedWikidata: Set<String> = []
        /// Klassik work IDs whose match the listener turned down. They are never looked up again.
        var rejected: Set<String> = []

        init() {}

        /// A cache from an older version lacks the newer fields; the listener's years must survive.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            works = try values.decodeIfPresent([String: WorkFacts].self, forKey: .works) ?? [:]
            unknownIDs = try values.decodeIfPresent(Set<String>.self, forKey: .unknownIDs) ?? []
            links = try values.decodeIfPresent([String: String].self, forKey: .links) ?? [:]
            candidates = try values.decodeIfPresent([String: [WorkCandidate]].self, forKey: .candidates) ?? [:]
            unmatched = try values.decodeIfPresent(Set<String>.self, forKey: .unmatched) ?? []
            composers = try values.decodeIfPresent([String: ComposerFacts].self, forKey: .composers) ?? [:]
            composerIDs = try values.decodeIfPresent([String: String].self, forKey: .composerIDs) ?? [:]
            unknownComposers = try values.decodeIfPresent(Set<String>.self, forKey: .unknownComposers) ?? []
            years = try values.decodeIfPresent([String: Int].self, forKey: .years) ?? [:]
            askedWikidata = try values.decodeIfPresent(Set<String>.self, forKey: .askedWikidata) ?? []
            rejected = try values.decodeIfPresent(Set<String>.self, forKey: .rejected) ?? []
        }
    }

    enum Source: Equatable, Sendable {
        case listener, musicBrainz, wikidata

        var title: String {
            switch self {
            case .listener: "You"
            case .musicBrainz: "MusicBrainz"
            case .wikidata: "Wikidata"
            }
        }
    }

    /// How a work is linked to MusicBrainz.
    enum Link: Equatable, Sendable {
        /// The WORK tag carries the ID.
        case tagged(String)
        /// A match or the listener found the ID.
        case found(String)
        case candidates([WorkCandidate])
        case unmatched
        /// Not looked up yet.
        case pending
    }

    /// Where the running pass is.
    struct Progress: Equatable, Sendable {
        var done: Int
        var total: Int
        var composer: String?
    }

    /// What the lookup found for the tagged works of the library.
    struct Summary {
        var works = 0
        var linked = 0
        var dated = 0
        var toConfirm: [WorkIndex.Work] = []
        var unmatched: [WorkIndex.Work] = []
        var pending = 0
        var composers = 0
        var composersWithDates = 0
    }

    private(set) var cache = Cache()
    /// Lookups that run now: the pass over the library, and single works the listener asked for.
    private(set) var running = 0
    var isRunning: Bool { running > 0 }
    private(set) var progress: Progress?
    private(set) var lastError: String?
    /// Requests sent since the app started, to show how much the lookup costs.
    private(set) var requests = 0

    private let musicBrainz: MusicBrainz
    private let wikidata: Wikidata
    private let cacheURL: URL
    /// A pass started while another runs. It runs after that one, with the newer library.
    private var queued: WorkIndex?
    private var isPassRunning = false
    private var saving: Task<Void, Never>?

    init(
        musicBrainz: MusicBrainz = MusicBrainz(), wikidata: Wikidata = Wikidata(),
        cacheURL: URL = .applicationSupportDirectory.appending(path: "enrichment.json")
    ) {
        self.cacheURL = cacheURL
        self.musicBrainz = musicBrainz
        self.wikidata = wikidata
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            self.cache = cache
        }
    }

    // MARK: Reading

    func link(of work: WorkIndex.Work) -> Link {
        if let id = Self.taggedID(of: work) { return .tagged(id) }
        if let id = cache.links[work.id] { return .found(id) }
        if let found = cache.candidates[work.id] { return .candidates(found) }
        return cache.unmatched.contains(work.id) ? .unmatched : .pending
    }

    func musicBrainzID(of work: WorkIndex.Work) -> String? {
        Self.taggedID(of: work) ?? cache.links[work.id]
    }

    func facts(of work: WorkIndex.Work) -> WorkFacts? {
        musicBrainzID(of: work).flatMap { cache.works[$0] }
    }

    /// When the work was composed, and who says so.
    func composed(_ work: WorkIndex.Work) -> (span: YearSpan, source: Source)? {
        if let year = cache.years[work.id] { return (YearSpan(year), .listener) }
        guard let facts = facts(of: work), let span = facts.composed else { return nil }
        return (span, facts.source == .wikidata ? .wikidata : .musicBrainz)
    }

    func composer(named name: String) -> ComposerFacts? {
        cache.composerIDs[name].flatMap { cache.composers[$0] }
    }

    func summary(of index: WorkIndex) -> Summary {
        var summary = Summary()
        for composer in index.composers {
            let works = composer.works.filter(\.isTagged)
            guard !works.isEmpty else { continue }
            summary.composers += 1
            if let facts = self.composer(named: composer.name), facts.born != nil {
                summary.composersWithDates += 1
            }
            for work in works {
                summary.works += 1
                if composed(work) != nil { summary.dated += 1 }
                switch link(of: work) {
                case .tagged, .found: summary.linked += 1
                case .candidates: summary.toConfirm.append(work)
                case .unmatched: summary.unmatched.append(work)
                case .pending: summary.pending += 1
                }
            }
        }
        return summary
    }

    // MARK: Listener

    func setYear(_ year: Int?, for work: WorkIndex.Work) {
        cache.years[work.id] = year
        save()
    }

    func confirm(_ candidate: WorkCandidate, for work: WorkIndex.Work) async {
        cache.candidates[work.id] = nil
        cache.unmatched.remove(work.id)
        cache.rejected.remove(work.id)
        cache.links[work.id] = candidate.id
        save()
        await run {
            try await self.lookUp(work, in: [:], complete: false)
            try await self.lookUpComposerDates(work.composer, works: [work])
            try await self.askWikidata()
        }
    }

    func reject(_ work: WorkIndex.Work) {
        cache.candidates[work.id] = nil
        cache.links[work.id] = nil
        cache.unmatched.insert(work.id)
        cache.rejected.insert(work.id)
        save()
    }

    /// Forgets what Klassik knows about the work and asks again, for example after a fix in MusicBrainz.
    /// A match the listener confirmed stays.
    func lookUpAgain(_ work: WorkIndex.Work) async {
        if let id = musicBrainzID(of: work) {
            cache.works[id] = nil
            cache.unknownIDs.remove(id)
            cache.askedWikidata.remove(id)
        } else {
            cache.candidates[work.id] = nil
            cache.unmatched.remove(work.id)
            cache.rejected.remove(work.id)
        }
        await run {
            try await self.lookUp(work, in: [:], complete: false)
            try await self.lookUpComposerDates(work.composer, works: [work])
            try await self.askWikidata()
        }
    }

    /// Asks again for every work and composer without a match, for example after many fixes in MusicBrainz.
    func lookUpMissingAgain(_ index: WorkIndex) async {
        cache.unmatched = cache.rejected
        cache.unknownIDs = []
        cache.unknownComposers = []
        cache.askedWikidata = []
        await enrich(index)
    }

    // MARK: Lookup

    /// Looks up every tagged work and composer that is not in the cache yet, composer by composer.
    /// A network failure ends the pass; the next start goes on from there.
    func enrich(_ index: WorkIndex) async {
        guard !isPassRunning else {
            queued = index
            return
        }
        isPassRunning = true
        let open = index.composers.map { composer in
            (composer, composer.works.filter { $0.isTagged && needsLookUp($0) })
        }
        progress = Progress(done: 0, total: open.map(\.1.count).reduce(0, +))
        await run {
            for (composer, works) in open {
                self.progress?.composer = composer.name
                try await self.enrich(composer, works)
                self.save()
            }
            self.progress?.composer = nil
            try await self.askWikidata()
        }
        progress = nil
        isPassRunning = false
        if let next = queued {
            queued = nil
            await enrich(next)
        }
    }

    private func needsLookUp(_ work: WorkIndex.Work) -> Bool {
        switch link(of: work) {
        case .tagged(let id), .found(let id): cache.works[id] == nil && !cache.unknownIDs.contains(id)
        case .pending: true
        case .candidates, .unmatched: false
        }
    }

    /// Lists the composer's works when that costs fewer requests than a search for each work.
    /// The matches then come from the list, on the device.
    private func enrich(_ composer: WorkIndex.Composer, _ open: [WorkIndex.Work]) async throws {
        if !open.isEmpty { try await lookUpComposerID(composer.name, works: open) }
        var known: [String: MusicBrainz.Work] = [:]
        var complete = false
        if let id = cache.composerIDs[composer.name], open.count >= 2 {
            let first = try await listWorks(of: id, offset: 0)
            for work in first.works { known[work.id] = work }
            let pages = (first.total + MusicBrainz.pageSize - 1) / MusicBrainz.pageSize
            if first.total > 0, pages - 1 <= open.count {
                for page in 1..<max(pages, 1) {
                    for work in try await listWorks(of: id, offset: page * MusicBrainz.pageSize).works {
                        known[work.id] = work
                    }
                }
                complete = true
            }
        }
        for work in open {
            try await lookUp(work, in: known, complete: complete)
            progress?.done += 1
        }
        try await lookUpComposerDates(composer.name, works: composer.works)
    }

    private func listWorks(of composerID: String, offset: Int) async throws -> (works: [MusicBrainz.Work], total: Int) {
        requests += 1
        return try await musicBrainz.works(composerID: composerID, offset: offset)
    }

    /// `known` holds listed works of the composer. If `complete`, it holds all of them and no search is needed.
    private func lookUp(_ work: WorkIndex.Work, in known: [String: MusicBrainz.Work], complete: Bool) async throws {
        if let id = musicBrainzID(of: work) {
            guard cache.works[id] == nil, !cache.unknownIDs.contains(id) else { return }
            if known[id] == nil { requests += 1 }
            if let facts = try await musicBrainz.work(id: id, known: known) {
                cache.works[id] = facts
            } else {
                cache.unknownIDs.insert(id)
            }
            return
        }
        var found: [WorkCandidate] = []
        var byCatalogue = true
        if let composerID = cache.composerIDs[work.composer], !known.isEmpty {
            (found, byCatalogue) = MusicBrainz.candidates(
                in: Array(known.values), composerID: composerID, title: work.title)
        }
        if found.isEmpty, !complete, let catalogue = CatalogueNumber.find(in: work.title) {
            requests += 1
            found = try await musicBrainz.candidates(composer: work.composer, catalogue: catalogue)
            byCatalogue = true
        }
        // Two works with the same words but no shared catalogue number are two works, not two spellings.
        let best = byCatalogue ? MusicBrainz.confident(found, for: work.title) : (found.count == 1 ? found.first : nil)
        if let best {
            cache.links[work.id] = best.id
            try await lookUp(work, in: known, complete: complete)
        } else if found.isEmpty {
            cache.unmatched.insert(work.id)
        } else {
            cache.candidates[work.id] = Array(found.prefix(5))
        }
    }

    /// The composer ID comes from a work of the composer, else from a search by name.
    private func lookUpComposerID(_ name: String, works: [WorkIndex.Work]) async throws {
        guard cache.composerIDs[name] == nil else { return }
        if let id = works.lazy.compactMap({ self.facts(of: $0)?.composerID }).first {
            cache.composerIDs[name] = id
            return
        }
        // A tagged work names the composer for certain; a name can be ambiguous.
        if let tagged = works.first(where: { Self.taggedID(of: $0) != nil }) {
            try await lookUp(tagged, in: [:], complete: false)
            if let id = facts(of: tagged)?.composerID {
                cache.composerIDs[name] = id
                return
            }
        }
        guard !cache.unknownComposers.contains(name), name != Song.unknownComposer else { return }
        requests += 1
        if let found = try await musicBrainz.composer(named: name) {
            cache.composerIDs[name] = found.id
            cache.composers[found.id] = found
        } else {
            cache.unknownComposers.insert(name)
        }
    }

    private func lookUpComposerDates(_ name: String, works: [WorkIndex.Work]) async throws {
        try await lookUpComposerID(name, works: works)
        guard let id = cache.composerIDs[name], cache.composers[id] == nil else { return }
        requests += 1
        if let found = try await musicBrainz.composer(id: id) { cache.composers[id] = found }
    }

    /// Asks Wikidata for the works that MusicBrainz has no date for, many works in one query.
    private func askWikidata() async throws {
        let undated = cache.works.values.filter { $0.composed == nil && !cache.askedWikidata.contains($0.id) }
            .map(\.id)
        for start in stride(from: 0, to: undated.count, by: Wikidata.batchSize) {
            let batch = Array(undated[start..<min(start + Wikidata.batchSize, undated.count)])
            requests += 1
            // Wikidata only fills gaps, so its failure does not end the pass.
            guard let years = try? await wikidata.published(musicBrainzIDs: batch) else { continue }
            for key in cache.works.keys {
                guard let facts = cache.works[key], facts.composed == nil, let year = years[facts.id] else { continue }
                cache.works[key]?.composed = YearSpan(year)
                cache.works[key]?.source = .wikidata
            }
            cache.askedWikidata.formUnion(batch)
        }
    }

    private func run(_ body: @MainActor () async throws -> Void) async {
        running += 1
        defer {
            running -= 1
            save()
        }
        do {
            try await body()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Each write waits for the one before, so an older cache never overwrites a newer one.
    private func save() {
        let cache = cache
        let url = cacheURL
        saving = Task.detached { [previous = saving] in
            await previous?.value
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
        }
    }

    func clear() {
        cache = Cache()
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private static func taggedID(of work: WorkIndex.Work) -> String? {
        work.id.hasPrefix("mbid:") ? String(work.id.dropFirst(5)) : nil
    }
}

extension Enrichment {
    /// UI tests pass MusicBrainz and Wikidata answers in KLASSIK_MUSICBRAINZ_STUB, so the screen walk does not
    /// depend on the network. Release builds always ask the services.
    static func forLaunch() -> Enrichment {
        #if DEBUG
            if let json = ProcessInfo.processInfo.environment["KLASSIK_MUSICBRAINZ_STUB"],
                let bodies = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8))
            {
                let fetch: MusicBrainz.Fetch = { request in
                    guard let url = request.url, let body = bodies[stubKey(url)] else { return (Data(), 404) }
                    return (Data(body.utf8), 200)
                }
                return Enrichment(
                    musicBrainz: MusicBrainz(fetch: fetch, pacer: Pacer(interval: 0)),
                    wikidata: Wikidata(fetch: fetch, pacer: Pacer(interval: 0)))
            }
        #endif
        return Enrichment()
    }

    #if DEBUG
        /// "work/<id>", "artist/<id>", "work?<query>", "artist?<query>", "work?artist=<id>&offset=<n>", or
        /// "sparql?<MusicBrainz IDs, sorted, joined by commas>".
        nonisolated static func stubKey(_ url: URL) -> String {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            if url.host == "query.wikidata.org" {
                let ids = (value("query") ?? "").split(separator: "\"").filter { UUID(uuidString: String($0)) != nil }
                return "sparql?" + ids.map(String.init).sorted().joined(separator: ",")
            }
            let path = url.path.replacingOccurrences(of: "/ws/2/", with: "")
            if path.contains("/") { return path }
            if let artist = value("artist") { return "\(path)?artist=\(artist)&offset=\(value("offset") ?? "0")" }
            return path + (value("query").map { "?" + $0 } ?? "")
        }
    #endif
}
