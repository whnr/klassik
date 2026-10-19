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
        /// MusicBrainz IDs of works without one in the tags, by Klassik work ID: a clear search match or the
        /// listener's choice.
        var links: [String: String] = [:]
        /// Search matches that the listener must confirm once, by Klassik work ID.
        var candidates: [String: [WorkCandidate]] = [:]
        /// Klassik work IDs whose search found nothing, or whose match the listener turned down.
        var unmatched: Set<String> = []
        var composers: [String: ComposerFacts] = [:]
        /// MusicBrainz artist IDs by the composer name in the tags.
        var composerIDs: [String: String] = [:]
        var unknownComposers: Set<String> = []
        /// Composition years that the listener typed, by Klassik work ID.
        var years: [String: Int] = [:]
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
        /// A search or the listener found the ID.
        case found(String)
        case candidates([WorkCandidate])
        case unmatched
        /// The title has no catalogue number to search for.
        case noCatalogue
        /// Not looked up yet.
        case pending
    }

    private(set) var cache = Cache()
    /// Lookups that run now: the pass over the library, and single works the listener asked for.
    private(set) var running = 0
    var isRunning: Bool { running > 0 }
    /// Works and composers still to look up in the running pass.
    private(set) var remaining = 0
    private(set) var lastError: String?

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
        self.musicBrainz = musicBrainz
        self.wikidata = wikidata
        self.cacheURL = cacheURL
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            self.cache = cache
        }
    }

    // MARK: Reading

    func link(of work: WorkIndex.Work) -> Link {
        if let id = Self.taggedID(of: work) { return .tagged(id) }
        if let id = cache.links[work.id] { return .found(id) }
        if let found = cache.candidates[work.id] { return .candidates(found) }
        if cache.unmatched.contains(work.id) { return .unmatched }
        return CatalogueNumber.find(in: work.title) == nil ? .noCatalogue : .pending
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

    // MARK: Listener

    func setYear(_ year: Int?, for work: WorkIndex.Work) {
        cache.years[work.id] = year
        save()
    }

    func confirm(_ candidate: WorkCandidate, for work: WorkIndex.Work) async {
        cache.candidates[work.id] = nil
        cache.unmatched.remove(work.id)
        cache.links[work.id] = candidate.id
        save()
        await run {
            try await self.lookUp(work)
            try await self.lookUpComposer(work.composer, works: [work])
        }
    }

    func reject(_ work: WorkIndex.Work) {
        cache.candidates[work.id] = nil
        cache.links[work.id] = nil
        cache.unmatched.insert(work.id)
        save()
    }

    /// Forgets what Klassik knows about the work and asks again, for example after a fix in MusicBrainz.
    /// A match the listener confirmed stays.
    func lookUpAgain(_ work: WorkIndex.Work) async {
        if let id = musicBrainzID(of: work) {
            cache.works[id] = nil
            cache.unknownIDs.remove(id)
        } else {
            cache.candidates[work.id] = nil
            cache.unmatched.remove(work.id)
        }
        await run {
            try await self.lookUp(work)
            try await self.lookUpComposer(work.composer, works: [work])
        }
    }

    // MARK: Lookup

    /// Looks up every tagged work and composer that is not in the cache yet. A network failure ends the pass;
    /// the next start goes on from there.
    func enrich(_ index: WorkIndex) async {
        guard !isPassRunning else {
            queued = index
            return
        }
        isPassRunning = true
        let works = index.composers.flatMap(\.works).filter { $0.isTagged && needsLookUp($0) }
        remaining = works.count + index.composers.count
        await run {
            for (number, work) in works.enumerated() {
                try await self.lookUp(work)
                self.remaining -= 1
                if number % 10 == 9 { self.save() }
            }
            for composer in index.composers {
                try await self.lookUpComposer(composer.name, works: composer.works)
                self.remaining -= 1
            }
        }
        remaining = 0
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
        case .candidates, .unmatched, .noCatalogue: false
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

    private func lookUp(_ work: WorkIndex.Work) async throws {
        if let id = musicBrainzID(of: work) {
            guard cache.works[id] == nil, !cache.unknownIDs.contains(id) else { return }
            guard var facts = try await musicBrainz.work(id: id) else {
                cache.unknownIDs.insert(id)
                return
            }
            if facts.composed == nil, let year = try? await wikidata.published(musicBrainzID: facts.id) {
                facts.composed = YearSpan(year)
                facts.source = .wikidata
            }
            cache.works[id] = facts
            return
        }
        guard let catalogue = CatalogueNumber.find(in: work.title) else { return }
        let found = try await musicBrainz.candidates(composer: work.composer, catalogue: catalogue)
        if let best = MusicBrainz.confident(found) {
            cache.links[work.id] = best.id
            try await lookUp(work)
        } else if found.isEmpty {
            cache.unmatched.insert(work.id)
        } else {
            cache.candidates[work.id] = Array(found.prefix(5))
        }
    }

    /// The composer ID comes from a work of the composer, else from a search by name.
    private func lookUpComposer(_ name: String, works: [WorkIndex.Work]) async throws {
        if cache.composerIDs[name] == nil {
            if let id = works.lazy.compactMap({ self.facts(of: $0)?.composerID }).first {
                cache.composerIDs[name] = id
            } else if !cache.unknownComposers.contains(name), name != Song.unknownComposer {
                if let found = try await musicBrainz.composer(named: name) {
                    cache.composerIDs[name] = found.id
                    cache.composers[found.id] = found
                } else {
                    cache.unknownComposers.insert(name)
                }
            }
        }
        guard let id = cache.composerIDs[name], cache.composers[id] == nil else { return }
        if let found = try await musicBrainz.composer(id: id) { cache.composers[id] = found }
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
        /// "work/<id>", "artist/<id>", "work?<query>", "artist?<query>", or "sparql?<MusicBrainz ID>".
        nonisolated static func stubKey(_ url: URL) -> String {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "query" }?.value
            if url.host == "query.wikidata.org" {
                return "sparql?" + (query?.split(separator: "\"").dropFirst().first.map(String.init) ?? "")
            }
            let path = url.path.replacingOccurrences(of: "/ws/2/", with: "")
            return path.contains("/") ? path : path + (query.map { "?" + $0 } ?? "")
        }
    #endif
}
