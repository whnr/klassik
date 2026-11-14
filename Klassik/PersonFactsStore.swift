import Foundation
import Observation

/// How a composer tag turns into a Wikidata person (ADR 0017).
enum ComposerResolution: Codable, Equatable, Sendable {
    /// The Wikidata item of the composer.
    case person(String)
    /// The works do not decide: the listener picks.
    case pick([PersonMatch])
    /// One surname tag holds works of several composers, here with their names.
    case mixed([String])
    /// Wikidata knows nobody, or the listener picked "None of these".
    case unknown
}

/// The person facts of the device, cached by Wikidata item and by composer tag.
/// A lookup that fails on the network leaves no trace in the cache, so the next visit asks again.
@MainActor @Observable
final class PersonFactsStore {
    struct Cache: Codable, Sendable {
        var people: [String: PersonFacts] = [:]
        /// The resolution of each composer tag.
        var composers: [String: ComposerResolution] = [:]
        /// The Wikidata item of each MusicBrainz artist ID. An empty text means that Wikidata has none.
        var artists: [String: String] = [:]
        /// The tags that the listener decided by hand. No lookup changes them.
        var chosen: Set<String> = []
        /// The MusicBrainz artist IDs that each resolution used, so that a lookup runs again only for new IDs.
        var inputs: [String: [String]] = [:]
    }

    private(set) var cache = Cache()
    private(set) var lastError: String?
    /// The tags that a lookup runs for.
    private(set) var loading: Set<String> = []

    private let service: PersonFactsService
    private let cacheURL: URL
    private var saving: Task<Void, Never>?

    init(
        service: PersonFactsService = PersonFactsService(),
        cacheURL: URL = .applicationSupportDirectory.appending(path: "person-facts.json")
    ) {
        self.service = service
        self.cacheURL = cacheURL
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            self.cache = cache
        }
    }

    // MARK: Reading

    func resolution(ofComposer tag: String) -> ComposerResolution? {
        cache.composers[tag]
    }

    /// The facts of the composer that the tag stands for, if it stands for one.
    func facts(ofComposer tag: String) -> PersonFacts? {
        guard case .person(let qid)? = cache.composers[tag] else { return nil }
        return cache.people[qid]
    }

    // MARK: Lookup

    /// Finds the composer of a tag. `artistIDs` are the MusicBrainz composer IDs of the works under the tag:
    /// when they all lead to one Wikidata person, the works decide.
    func resolve(composer tag: String, artistIDs: [String]) async {
        let inputs = Set(artistIDs).sorted()
        guard !loading.contains(tag), tag != Song.unknownComposer, !cache.chosen.contains(tag),
            cache.composers[tag] == nil || cache.inputs[tag] != inputs
        else { return }
        loading.insert(tag)
        defer { loading.remove(tag) }
        do {
            let resolution = try await decide(tag, artistIDs: inputs)
            cache.composers[tag] = resolution
            cache.inputs[tag] = inputs
            if case .person(let qid) = resolution { try await load(qid) }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        save()
    }

    /// The listener's choice from a pick list. Nil is "None of these".
    func choose(_ match: PersonMatch?, forComposer tag: String) async {
        cache.chosen.insert(tag)
        guard let match else {
            cache.composers[tag] = .unknown
            save()
            return
        }
        loading.insert(tag)
        defer { loading.remove(tag) }
        do {
            try await load(match.qid)
            cache.composers[tag] = .person(match.qid)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        save()
    }

    /// Lets the listener choose again, from the composers that Wikidata finds for the tag.
    func chooseAgain(composer tag: String) async {
        loading.insert(tag)
        defer { loading.remove(tag) }
        do {
            let found = try await service.composers(named: tag)
            cache.composers[tag] = found.isEmpty ? .unknown : .pick(found)
            cache.chosen.insert(tag)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        save()
    }

    private func load(_ qid: String) async throws {
        guard cache.people[qid] == nil else { return }
        if let facts = try await service.facts(qid: qid) { cache.people[qid] = facts }
    }

    private func decide(_ tag: String, artistIDs: [String]) async throws -> ComposerResolution {
        var persons: [String] = []
        for id in Set(artistIDs).sorted() {
            let qid = try await person(ofArtist: id)
            if !qid.isEmpty, !persons.contains(qid) { persons.append(qid) }
        }
        let surnameOnly = Self.isSurnameOnly(tag)
        if persons.count == 1 { return .person(persons[0]) }
        if persons.count > 1, surnameOnly {
            var names: [String] = []
            for qid in persons {
                try await load(qid)
                names.append(cache.people[qid]?.name ?? qid)
            }
            return .mixed(names)
        }
        let found = try await service.composers(named: tag)
        if found.isEmpty { return .unknown }
        let exact = found.filter { Self.fold($0.name) == Self.fold(tag) }
        if !surnameOnly, exact.count == 1 { return .person(exact[0].qid) }
        if !surnameOnly, found.count == 1 { return .person(found[0].qid) }
        return .pick(found)
    }

    private func person(ofArtist id: String) async throws -> String {
        if let known = cache.artists[id] { return known }
        let qid = try await service.person(musicBrainzArtist: id)?.qid ?? ""
        cache.artists[id] = qid
        return qid
    }

    /// A tag of one word, such as "Strauss", leaves the person open.
    nonisolated static func isSurnameOnly(_ tag: String) -> Bool {
        tag.split(whereSeparator: \.isWhitespace).count < 2
    }

    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clear() {
        cache = Cache()
        try? FileManager.default.removeItem(at: cacheURL)
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
}
