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
/// A lookup that fails leaves no resolution in the cache, so the next visit asks again.
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
        /// The Wikidata item of each performer tag. An empty text means that Wikidata has none.
        var performers: [String: String] = [:]

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            people = try container.decode([String: PersonFacts].self, forKey: .people)
            composers = try container.decode([String: ComposerResolution].self, forKey: .composers)
            artists = try container.decode([String: String].self, forKey: .artists)
            chosen = try container.decode(Set<String>.self, forKey: .chosen)
            inputs = try container.decode([String: [String]].self, forKey: .inputs)
            // A cache from before performer pages has no such key.
            performers = try container.decodeIfPresent([String: String].self, forKey: .performers) ?? [:]
        }
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

    /// The facts of the performer that the tag stands for. Nil when Wikidata knows nobody, or not yet.
    func facts(ofPerformer tag: String) -> PersonFacts? {
        guard let qid = cache.performers[tag], !qid.isEmpty else { return nil }
        return cache.people[qid]
    }

    /// True when a lookup for the tag has finished, with or without a match.
    func hasResolved(performer tag: String) -> Bool {
        guard let qid = cache.performers[tag] else { return false }
        return qid.isEmpty || cache.people[qid] != nil
    }

    // MARK: Lookup

    /// Finds the performer of a tag. A failed lookup leaves nothing in the cache, so the next visit asks again.
    func resolve(performer tag: String) async {
        guard !loading.contains(tag), !hasResolved(performer: tag) else { return }
        loading.insert(tag)
        defer { loading.remove(tag) }
        do {
            if let qid = try await service.performer(named: tag)?.qid {
                // The item is saved only with its facts, as for a composer.
                cache.performers[tag] = try await load(qid) ? qid : ""
            } else {
                cache.performers[tag] = ""
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        save()
    }

    /// Finds the composer of a tag. `artistIDs` are the MusicBrainz composer IDs of the works under the tag:
    /// when they all lead to one Wikidata person, the works decide.
    func resolve(composer tag: String, artistIDs: [String]) async {
        let inputs = Set(artistIDs).sorted()
        guard !loading.contains(tag), tag != Song.unknownComposer, !cache.chosen.contains(tag),
            cache.composers[tag] == nil || cache.inputs[tag] != inputs || lacksFacts(tag)
        else { return }
        loading.insert(tag)
        defer { loading.remove(tag) }
        do {
            var resolution = try await decide(tag, artistIDs: inputs)
            // The resolution is saved only with its facts: a failed load leaves the tag open for the next visit.
            if case .person(let qid) = resolution, try await load(qid) == false { resolution = .unknown }
            cache.composers[tag] = resolution
            cache.inputs[tag] = inputs
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        save()
    }

    /// The listener's choice from a pick list. Nil is "None of these".
    func choose(_ match: PersonMatch?, forComposer tag: String) async {
        pin(tag)
        guard let match else {
            cache.composers[tag] = .unknown
            save()
            return
        }
        loading.insert(tag)
        defer { loading.remove(tag) }
        do {
            cache.composers[tag] = try await load(match.qid) ? .person(match.qid) : .unknown
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
            pin(tag)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        save()
    }

    /// True when the facts of the item are on the device after the call. False: Wikidata has no such item.
    private func load(_ qid: String) async throws -> Bool {
        if cache.people[qid] != nil { return true }
        guard let facts = try await service.facts(qid: qid) else { return false }
        cache.people[qid] = facts
        return true
    }

    private func lacksFacts(_ tag: String) -> Bool {
        guard case .person(let qid)? = cache.composers[tag] else { return false }
        return cache.people[qid] == nil
    }

    /// Keeps the listener's decision against later lookups. A decision made while the works had no
    /// MusicBrainz IDs yet stays open: the works may settle it when the IDs arrive.
    private func pin(_ tag: String) {
        if cache.inputs[tag]?.isEmpty != true { cache.chosen.insert(tag) }
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
                _ = try await load(qid)
                names.append(cache.people[qid]?.name ?? qid)
            }
            // The names keep one order, whatever order the artist IDs have.
            return .mixed(names.sorted { Self.fold($0) < Self.fold($1) })
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
