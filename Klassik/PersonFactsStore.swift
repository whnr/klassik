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
/// Missing facts stay open for another lookup on the next visit.
@MainActor @Observable
final class PersonFactsStore {
    struct PictureWork: Codable, Equatable, Sendable {
        var portrait: PersonPortrait
        var old: PersonPortrait?
    }

    struct Cache: Codable, Sendable {
        /// Facts need a new version when parsing rules require another lookup.
        static let version = 1
        var version = Cache.version
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
        /// When the background pass last settled each person: "composer:<tag>" or "performer:<tag>" (ADR 0042).
        var checked: [String: Date] = [:]
        /// When each check of the background pass falls due, with its random spread (ADR 0042).
        var due: [String: Date] = [:]
        var picturePending: [String: PictureWork] = [:]

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
            people = try container.decode([String: PersonFacts].self, forKey: .people)
            composers = try container.decode([String: ComposerResolution].self, forKey: .composers)
            artists = try container.decode([String: String].self, forKey: .artists)
            chosen = try container.decode(Set<String>.self, forKey: .chosen)
            inputs = try container.decode([String: [String]].self, forKey: .inputs)
            // Performer mappings are optional for caches that hold composers only.
            performers = try container.decodeIfPresent([String: String].self, forKey: .performers) ?? [:]
            checked = try container.decodeIfPresent([String: Date].self, forKey: .checked) ?? [:]
            due = try container.decodeIfPresent([String: Date].self, forKey: .due) ?? [:]
            picturePending = try container.decodeIfPresent([String: PictureWork].self, forKey: .picturePending) ?? [:]
            // Resolutions and listener choices must survive facts invalidation.
            if version < Cache.version {
                people = [:]
                version = Cache.version
            }
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
    /// The result is false for a failed request only: a tag that needs no lookup counts as done.
    @discardableResult
    func resolve(performer tag: String) async -> Bool {
        guard !loading.contains(tag), !hasResolved(performer: tag) else { return true }
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
            save()
            return true
        } catch {
            lastError = error.localizedDescription
            save()
            return false
        }
    }

    /// Finds the composer of a tag. `artistIDs` are the MusicBrainz composer IDs of the works under the tag:
    /// when they all lead to one Wikidata person, the works decide.
    @discardableResult
    func resolve(composer tag: String, artistIDs: [String]) async -> Bool {
        let inputs = Set(artistIDs).sorted()
        let chosen = cache.chosen.contains(tag)
        guard !loading.contains(tag), tag != Song.unknownComposer,
            chosen ? lacksFacts(tag) : cache.composers[tag] == nil || cache.inputs[tag] != inputs || lacksFacts(tag)
        else { return true }
        loading.insert(tag)
        defer { loading.remove(tag) }
        do {
            if chosen, case .person(let qid)? = cache.composers[tag] {
                // A missing item or failed request must not replace the listener's choice.
                _ = try await load(qid)
            } else {
                var resolution = try await decide(tag, artistIDs: inputs)
                // The resolution is saved only with its facts: a failed load leaves the tag open for the next visit.
                if case .person(let qid) = resolution, try await load(qid) == false { resolution = .unknown }
                cache.composers[tag] = resolution
                cache.inputs[tag] = inputs
            }
            lastError = nil
            save()
            return true
        } catch {
            lastError = error.localizedDescription
            save()
            return false
        }
    }

    // MARK: Background pass

    /// The Wikidata item that a tag stands for now, if it has one.
    func qid(ofComposer tag: String) -> String? {
        if case .person(let qid)? = cache.composers[tag] { return qid }
        return nil
    }

    func qid(ofPerformer tag: String) -> String? {
        cache.performers[tag].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The seconds until Wikimedia lets the next person request go, after a throttle, or 0.
    func throttleHold() async -> Double {
        await service.pacer.hold
    }

    /// Loads the facts of an item again. The old facts stay when the request fails or the item is gone.
    /// Returns false on a failed request.
    func refresh(_ qid: String) async -> Bool {
        do {
            if let facts = try await service.facts(qid: qid) { cache.people[qid] = facts }
            lastError = nil
            save()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Finds the composer of a tag by the tag alone, for the background pass (ADR 0042). It uses no MusicBrainz
    /// ID. A tag with a resolution keeps it, unless `again` asks Wikidata again. The listener's choice stays.
    /// Returns false on a failed request.
    @discardableResult
    func lookUp(composer tag: String, again: Bool = false) async -> Bool {
        if !again, case .person(let qid)? = cache.composers[tag] {
            return cache.people[qid] != nil ? true : await refresh(qid)
        }
        guard again || cache.composers[tag] == nil, !cache.chosen.contains(tag) else { return true }
        // `resolve` asks again only when the saved inputs differ from the new ones.
        cache.inputs[tag] = nil
        return await resolve(composer: tag, artistIDs: [])
    }

    func reopen(performer tag: String) {
        cache.performers[tag] = nil
    }

    /// Records that the background pass settled a person, and when the person falls due again.
    func markChecked(_ key: String, at date: Date, due: Date) {
        cache.checked[key] = date
        cache.due[key] = due
        save()
    }

    func queuePicture(_ key: String, portrait: PersonPortrait, old: PersonPortrait?) {
        cache.picturePending[key] = PictureWork(portrait: portrait, old: old)
        save()
    }

    func finishPicture(_ key: String, work: PictureWork) {
        guard cache.picturePending[key] == work else { return }
        cache.picturePending[key] = nil
        save()
    }

    func saved() async { await saving?.value }

    /// Records when the background pass tries a failed person again. The person stays unchecked.
    func postpone(_ key: String, due: Date) {
        cache.due[key] = due
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

extension PersonFactsStore {
    /// The store of a launch. UI tests may give it answers through `PersonLaunchStub`.
    static func forLaunch() -> PersonFactsStore {
        #if DEBUG
            if let fetch = PersonLaunchStub.fetch {
                let service = PersonFactsService(fetch: fetch, pacer: WikimediaPacer(interval: .zero))
                return PersonFactsStore(service: service)
            }
        #endif
        return PersonFactsStore()
    }
}
