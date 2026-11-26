import Foundation

extension Search {
    /// The kinds of search terms that the filter sheet lists, one kind at a time.
    enum Scope: Int, CaseIterable, Identifiable, Sendable {
        case genres, composers, conductors, performers

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .genres: L("Genres")
            case .composers: L("Composers")
            case .conductors: L("Conductors")
            case .performers: L("Performers")
            }
        }

        /// The prompt of the field that narrows the terms of this kind.
        var findPrompt: String {
            switch self {
            case .genres: L("Find in genres")
            case .composers: L("Find in composers")
            case .conductors: L("Find in conductors")
            case .performers: L("Find in performers")
            }
        }
    }

    struct Term: Hashable, Sendable {
        var scope: Scope
        var name: String
    }

    /// One row of a search. Its terms join with "or"; the conditions of a search join with "and".
    struct Condition: Hashable, Sendable {
        var terms: [Term]
    }

    /// A term of the sheet, with what a tap on it does and the recordings that remain after the tap.
    struct Choice: Identifiable, Equatable, Sendable {
        enum Effect: Sendable {
            /// The first condition of the search.
            case start
            /// A new condition that joins the others with "and".
            case and
            /// The term joins the open condition with "or".
            case or
            /// The open condition holds the term. A tap removes it.
            case check
        }

        var term: Term
        var effect: Effect
        var count: Int
        var id: String { term.name }
    }

    /// The results that the conditions leave, with the counts that their rows show.
    struct Filtered: Sendable {
        var results = Results()
        /// For each shown work, its recordings that pass the conditions. Empty without conditions.
        var matching: [String: Int] = [:]
    }

    /// The recordings that a text found, through its works, people and albums. Without a text it holds every
    /// recording.
    struct Pool: Sendable {
        fileprivate var members: Set<Int>?
    }
}

/// The conditions of a search over the work index. It knows the search terms of each
/// recording, counts what a tap on a term leaves, and narrows the results of a text. It does no text matching of its
/// own: the pool of a text comes from the results of `Search`.
struct SearchFilters: Sendable {
    /// The terms of each recording, by its position.
    private var terms: [Set<Search.Term>] = []
    /// The recordings of each term, by position.
    private var postings: [Search.Term: [Int]] = [:]
    /// The terms of each scope, by name. A genre that every recording with a genre carries is not here.
    private var scopes: [Search.Scope: [Search.Term]] = [:]
    private var workRecordings: [String: [Int]] = [:]
    private var albumRecordings: [String: [Int]] = [:]
    private var personRecordings: [String: [Int]] = [:]
    /// For each person and role label, the recordings that name the person in that role.
    private var personRoles: [String: [String: [Int]]] = [:]
    /// For each composer, the recordings of each of their works.
    private var composerWorks: [String: [[Int]]] = [:]
    /// The tagged works by title, for conditions without a text.
    private var works: [WorkIndex.Work] = []
    private var albums: [WorkIndex.Album] = []

    init(index: WorkIndex) {
        var positions: [String: Int] = [:]
        var genreCarriers = 0
        var genreCounts: [String: Int] = [:]
        for composer in index.composers {
            let composes = composer.name != Song.unknownComposer
            var byWork: [[Int]] = []
            for work in composer.works {
                var mine: [Int] = []
                for recording in work.recordings {
                    let position = terms.count
                    positions[recording.id] = position
                    mine.append(position)
                    var own = Set<Search.Term>()
                    let genres = Set(recording.songs.flatMap(\.allGenres))
                    if !genres.isEmpty { genreCarriers += 1 }
                    for genre in genres {
                        own.insert(Search.Term(scope: .genres, name: genre))
                        genreCounts[genre, default: 0] += 1
                    }
                    if composes { own.insert(Search.Term(scope: .composers, name: composer.name)) }
                    for line in recording.principalNames {
                        let scope: Search.Scope = line.kind == .conductor ? .conductors : .performers
                        for name in line.names {
                            own.insert(Search.Term(scope: scope, name: name))
                            personRecordings[name, default: []].append(position)
                            personRoles[name, default: [:]][line.label, default: []].append(position)
                        }
                    }
                    for term in own { postings[term, default: []].append(position) }
                    terms.append(own)
                }
                workRecordings[work.id] = mine
                byWork.append(mine)
                if composes { personRecordings[composer.name, default: []] += mine }
            }
            if composes { composerWorks[composer.name] = byWork }
        }
        // A person in two roles of one recording counts it once.
        personRecordings = personRecordings.mapValues { Set($0).sorted() }
        // A genre that every recording with a genre carries filters nothing, such as Classical.
        let everywhere = Set(genreCounts.filter { $0.value == genreCarriers }.keys)
        scopes = Dictionary(grouping: postings.keys.filter { $0.scope != .genres || !everywhere.contains($0.name) }) {
            $0.scope
        }
        .mapValues { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        for album in index.albums {
            let mine = Set(album.tracks.compactMap { positions["\(WorkIndex.workKey($0))|\($0.albumKey)"] })
            albumRecordings[album.id] = mine.sorted()
        }
        works = index.composers.flatMap(\.works).filter(\.isTagged)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        albums = index.albums
    }

    /// The recordings that a text found: those of its works, people and albums. Nil results stand for no text.
    func pool(of results: Search.Results?) -> Search.Pool {
        guard let results else { return Search.Pool() }
        var members = Set<Int>()
        for work in results.works { members.formUnion(workRecordings[work.id] ?? []) }
        for person in results.people { members.formUnion(personRecordings[person.name] ?? []) }
        for album in results.albums { members.formUnion(albumRecordings[album.id] ?? []) }
        return Search.Pool(members: members)
    }

    /// The recordings of the pool that pass every condition.
    func count(_ conditions: [Search.Condition], in pool: Search.Pool) -> Int {
        remaining(conditions, in: pool).count
    }

    /// The terms of one scope that a tap can pick, with the effect of the tap. `joining` is the condition that the
    /// next term joins with "or"; without it a term starts a new condition. `narrowing` keeps the terms whose name
    /// has a word that starts with each of its words. A term that would leave no recording does not show.
    func choices(
        in scope: Search.Scope, conditions: [Search.Condition], joining: Int? = nil, narrowing: String = "",
        pool: Search.Pool
    ) -> [Search.Choice] {
        let joining = joining.flatMap { conditions.indices.contains($0) ? $0 : nil }
        let remain = remaining(conditions, in: pool)
        // In "or": the recordings that pass every other condition, and the open condition alone.
        let others = joining.map { open in
            remaining(conditions.enumerated().filter { $0.offset != open }.map(\.element), in: pool)
        }
        let used = Set(conditions.enumerated().filter { $0.offset != joining }.flatMap(\.element.terms))
        let tokens = Search.words(of: narrowing, unique: false)
        var choices: [Search.Choice] = []
        for term in scopes[scope] ?? [] where !used.contains(term) {
            if !tokens.isEmpty, !Search.matches(tokens, Search.words(of: term.name)) { continue }
            let posted = postings[term] ?? []
            let choice: Search.Choice
            if let open = joining, let others {
                let condition = conditions[open]
                if condition.terms.contains(term) {
                    choice = Search.Choice(term: term, effect: .check, count: remain.count)
                } else {
                    // Existing matches must not make an unrelated term available for "or".
                    guard posted.contains(where: { others.contains($0) }) else { continue }
                    let added = posted.count(where: { others.contains($0) && !passes($0, condition) })
                    choice = Search.Choice(term: term, effect: .or, count: remain.count + added)
                }
            } else {
                let count = posted.count(where: { remain.contains($0) })
                choice = Search.Choice(term: term, effect: conditions.isEmpty ? .start : .and, count: count)
            }
            if choice.count > 0 || choice.effect == .check { choices.append(choice) }
        }
        return choices.sorted { lhs, rhs in
            if (lhs.effect == .check) != (rhs.effect == .check) { return lhs.effect == .check }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.term.name.localizedStandardCompare(rhs.term.name) == .orderedAscending
        }
    }

    /// The results that pass the conditions. Nil results stand for no text: every tagged work and every album then
    /// counts as found, and people show only for a text. A row stays when one of its recordings passes.
    func narrow(_ results: Search.Results?, by conditions: [Search.Condition]) -> Search.Filtered {
        guard !conditions.isEmpty else { return Search.Filtered(results: results ?? Search.Results()) }
        let passing = remaining(conditions, in: Search.Pool())
        let found = results ?? Search.Results(works: works, albums: albums)
        var filtered = Search.Filtered()
        filtered.results.workTracks = found.workTracks
        filtered.results.albumTracks = found.albumTracks
        filtered.results.workNicknames = found.workNicknames
        for work in found.works {
            let count = (workRecordings[work.id] ?? []).count(where: { passing.contains($0) })
            guard count > 0 else { continue }
            filtered.results.works.append(work)
            filtered.matching[work.id] = count
        }
        filtered.results.people = found.people.compactMap { person($0, passing: passing) }
        filtered.results.albums = found.albums.filter {
            (albumRecordings[$0.id] ?? []).contains { passing.contains($0) }
        }
        return filtered
    }

    /// A person with the counts of each role over the recordings that pass, the biggest first. Nil when none pass.
    private func person(_ person: Search.Person, passing: Set<Int>) -> Search.Person? {
        var roles: [Search.Person.Role] = []
        for role in person.roles {
            var role = role
            if role.countsWorks {
                role.count = (composerWorks[person.name] ?? []).count(where: { $0.contains { passing.contains($0) } })
            } else {
                role.count = (personRoles[person.name]?[role.label] ?? []).count(where: { passing.contains($0) })
            }
            if role.count > 0 { roles.append(role) }
        }
        guard !roles.isEmpty else { return nil }
        var narrowed = person
        // The stable sort keeps the composer role first when two counts are equal, as `Search` orders them.
        narrowed.roles = roles.enumerated().sorted { ($1.element.count, $0.offset) < ($0.element.count, $1.offset) }
            .map(\.element)
        narrowed.recordings = (personRecordings[person.name] ?? []).count(where: { passing.contains($0) })
        return narrowed
    }

    private func remaining(_ conditions: [Search.Condition], in pool: Search.Pool) -> Set<Int> {
        if let members = pool.members {
            return members.filter { position in conditions.allSatisfy { passes(position, $0) } }
        }
        guard let first = conditions.first else { return Set(terms.indices) }
        // Every passing recording carries a term of the first condition, so its postings are the candidates.
        let candidates = Set(first.terms.flatMap { postings[$0] ?? [] })
        return candidates.filter { position in conditions.dropFirst().allSatisfy { passes(position, $0) } }
    }

    private func passes(_ position: Int, _ condition: Search.Condition) -> Bool {
        condition.terms.contains { terms[position].contains($0) }
    }
}
