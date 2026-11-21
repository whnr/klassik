import Foundation
import Testing

@testable import Klassik

/// The conditions of a search: term effects, counts and the narrowed results (ADR 0020, 0025, 0029).
struct SearchFiltersTests {
    typealias Term = Search.Term
    typealias Condition = Search.Condition

    static let dvorak = "Antonín Dvořák"
    static let chopin = "Frédéric Chopin"
    static let bach = "Johann Sebastian Bach"

    static func song(
        _ id: String, album: String, composer: String, work: String, genres: [String],
        people: [(role: String, sub: String?, name: String)]
    ) -> Song {
        Song(
            id: id, title: "Track 1", album: album, albumId: album, artist: nil, displayAlbumArtist: nil, track: 1,
            discNumber: 1, year: nil, genres: genres.map { Song.Genre(name: $0) }, displayComposer: composer,
            contributors: people.map {
                Song.Contributor(role: $0.role, subRole: $0.sub, artist: Song.Artist(id: $0.name, name: $0.name))
            },
            works: [Song.Work(name: work)])
    }

    static let kubelik: [(role: String, sub: String?, name: String)] = [
        ("conductor", nil, "Rafael Kubelík"), ("performer", nil, "Berliner Philharmoniker"),
    ]

    /// Seven recordings. Six carry Classical; the Bach partita carries no genre.
    static let songs: [Song] = [
        song(
            "d9", album: "Dvořák Symphonies", composer: dvorak, work: "Symphony No. 9",
            genres: ["Classical", "Symphony"], people: kubelik),
        song(
            "d8", album: "Dvořák Symphonies", composer: dvorak, work: "Symphony No. 8",
            genres: ["Classical", "Symphony"], people: kubelik),
        song(
            "t9", album: "New World", composer: dvorak, work: "Symphony No. 9", genres: ["Classical", "Symphony"],
            people: [("conductor", nil, "Václav Talich")]),
        song(
            "c1", album: "Nocturnes", composer: chopin, work: "Nocturne No. 1", genres: ["Classical", "Piano"],
            people: [("performer", "piano", "Pia Nissimo")]),
        song(
            "c2", album: "Ballades", composer: chopin, work: "Ballade No. 1", genres: ["Classical", "Piano"],
            people: [("performer", "piano", "Pia Nissimo")]),
        song(
            "b1", album: "Cello Suites", composer: bach, work: "Suite No. 1", genres: ["Classical", "Chamber"],
            people: [("performer", "cello", "Clara Cellotest")]),
        song(
            "b2", album: "Partitas", composer: bach, work: "Partita No. 2", genres: [],
            people: [("performer", "violin", "Viktor Strich")]),
    ]

    static let index = WorkIndex(songs: songs)
    static let search = Search(index: index)
    static let filters = SearchFilters(index: index)
    static let everything = filters.pool(of: nil)

    static func composer(_ name: String) -> Term { Term(scope: .composers, name: name) }
    static func conductor(_ name: String) -> Term { Term(scope: .conductors, name: name) }
    static func genre(_ name: String) -> Term { Term(scope: .genres, name: name) }

    static func summary(_ choices: [Search.Choice]) -> [String] {
        choices.map { choice in
            switch choice.effect {
            case .start: "\(choice.term.name) \(choice.count)"
            case .and: "\(choice.term.name) and \(choice.count)"
            case .or: "\(choice.term.name) or \(choice.count)"
            case .check: "\(choice.term.name) check \(choice.count)"
            }
        }
    }

    /// Classical is on every recording that carries a genre, so it filters nothing. The partita without a genre
    /// does not keep it.
    @Test func hidesAGenreThatEveryRecordingWithAGenreCarries() {
        let choices = Self.filters.choices(in: .genres, conditions: [], pool: Self.everything)
        #expect(Self.summary(choices) == ["Symphony 3", "Piano 2", "Chamber 1"])
    }

    @Test func termsOfAConditionJoinWithOrAndConditionsWithAnd() {
        let filters = Self.filters
        let all = Self.everything
        #expect(filters.count([], in: all) == 7)
        #expect(filters.count([Condition(terms: [Self.composer(Self.dvorak)])], in: all) == 3)
        let either = Condition(terms: [Self.composer(Self.dvorak), Self.composer(Self.chopin)])
        #expect(filters.count([either], in: all) == 5)
        #expect(filters.count([either, Condition(terms: [Self.genre("Piano")])], in: all) == 2)
        let kubelik = Condition(terms: [Self.conductor("Rafael Kubelík")])
        #expect(filters.count([Condition(terms: [Self.composer(Self.dvorak)]), kubelik], in: all) == 2)
        #expect(filters.count([kubelik, Condition(terms: [Self.genre("Piano")])], in: all) == 0)
    }

    /// Without an open condition a term adds a condition with "and". A term that leaves nothing does not show, and
    /// a term that a condition holds does not show again.
    @Test func aTermStartsAConditionWithAnd() {
        let conditions = [Condition(terms: [Self.composer(Self.dvorak)])]
        let conductors = Self.filters.choices(in: .conductors, conditions: conditions, pool: Self.everything)
        #expect(Self.summary(conductors) == ["Rafael Kubelík and 2", "Václav Talich and 1"])
        #expect(Self.filters.choices(in: .composers, conditions: conditions, pool: Self.everything).isEmpty)
    }

    /// With an open condition a term joins it with "or", and a term that it holds shows a check.
    @Test func aTermJoinsTheOpenConditionWithOr() {
        let conditions = [Condition(terms: [Self.composer(Self.dvorak)])]
        let composers = Self.filters.choices(
            in: .composers, conditions: conditions, joining: 0, pool: Self.everything)
        #expect(
            Self.summary(composers) == [
                "Antonín Dvořák check 3", "Frédéric Chopin or 5", "Johann Sebastian Bach or 5",
            ])
    }

    /// "Or" counts against the other conditions: only a piano recording can join the composer condition. The open
    /// condition shows its own term with a check even when nothing passes.
    @Test func orCountsPassTheOtherConditions() {
        let conditions = [
            Condition(terms: [Self.genre("Piano")]), Condition(terms: [Self.composer(Self.dvorak)]),
        ]
        #expect(Self.filters.count(conditions, in: Self.everything) == 0)
        let composers = Self.filters.choices(
            in: .composers, conditions: conditions, joining: 1, pool: Self.everything)
        #expect(Self.summary(composers) == ["Antonín Dvořák check 0", "Frédéric Chopin or 2"])
    }

    /// The counts use only the recordings that the text found (ADR 0029).
    @Test func countsUseOnlyTheRecordingsThatTheTextFound() {
        let pool = Self.filters.pool(of: Self.search.results(for: "nocturne"))
        #expect(Self.filters.count([], in: pool) == 1)
        #expect(Self.summary(Self.filters.choices(in: .genres, conditions: [], pool: pool)) == ["Piano 1"])
        let composers = Self.filters.choices(in: .composers, conditions: [], pool: pool)
        #expect(Self.summary(composers) == ["Frédéric Chopin 1"])
    }

    /// A person in the results brings every recording that names them.
    @Test func aPersonOfTheTextBringsTheirRecordings() {
        let pool = Self.filters.pool(of: Self.search.results(for: "kubelik"))
        #expect(Self.filters.count([], in: pool) == 2)
        let genres = Self.filters.choices(in: .genres, conditions: [], pool: pool)
        #expect(Self.summary(genres) == ["Symphony 2"])
    }

    @Test func theNarrowingFieldMatchesWordStarts() {
        let all = Self.everything
        let pia = Self.filters.choices(in: .performers, conditions: [], narrowing: "NISS", pool: all)
        #expect(pia.map(\.term.name) == ["Pia Nissimo"])
        #expect(Self.filters.choices(in: .performers, conditions: [], narrowing: "issimo", pool: all).isEmpty)
        let performers = Self.filters.choices(in: .performers, conditions: [], pool: all).map(\.term.name)
        #expect(Set(performers) == ["Berliner Philharmoniker", "Pia Nissimo", "Clara Cellotest", "Viktor Strich"])
    }

    /// The conditions narrow every section of the text's results. A work row counts its recordings that pass.
    @Test func conditionsNarrowTheResultsOfTheText() throws {
        let found = Self.search.results(for: "dvorak")
        #expect(found.works.count == 2)
        let filtered = Self.filters.narrow(found, by: [Condition(terms: [Self.conductor("Václav Talich")])])
        let work = try #require(filtered.results.works.first)
        #expect(filtered.results.works.map(\.title) == ["Symphony No. 9"])
        #expect(filtered.matching[work.id] == 1)
        #expect(work.recordings.count == 2)
        #expect(filtered.hiddenWorks == 1)
        #expect(found.albums.map(\.title) == ["Dvořák Symphonies"])
        #expect(filtered.results.albums.isEmpty)
        let dvorak = try #require(filtered.results.people.first)
        #expect(filtered.results.people.map(\.name) == [Self.dvorak])
        #expect(dvorak.counts(locale: Locale(identifier: "en_GB")) == "Composer of 1\u{00A0}work")
        #expect(dvorak.recordings == 1)
    }

    /// Without a text the conditions find tagged works and albums, and no people.
    @Test func conditionsWithoutTextFindWorksAndAlbums() {
        let filtered = Self.filters.narrow(nil, by: [Condition(terms: [Self.genre("Piano")])])
        #expect(filtered.results.works.map(\.title) == ["Ballade No. 1", "Nocturne No. 1"])
        #expect(filtered.results.people.isEmpty)
        #expect(filtered.results.albums.map(\.title) == ["Ballades", "Nocturnes"])
        #expect(filtered.hiddenWorks == 4)
    }

    @Test func noConditionsLeaveTheResults() {
        let found = Self.search.results(for: "dvorak")
        let filtered = Self.filters.narrow(found, by: [])
        #expect(filtered.results.works.count == found.works.count)
        #expect(filtered.matching.isEmpty)
        #expect(filtered.hiddenWorks == 0)
        #expect(Self.filters.narrow(nil, by: []).results.isEmpty)
    }

    /// A scope that the library lacks lists no terms.
    @Test func anEmptyLibraryListsNoTerms() {
        let filters = SearchFilters(index: WorkIndex())
        for scope in Search.Scope.allCases {
            #expect(filters.choices(in: scope, conditions: [], pool: filters.pool(of: nil)).isEmpty)
        }
    }
}
