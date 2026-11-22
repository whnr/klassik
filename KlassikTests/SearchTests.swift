import Foundation
import Testing

@testable import Klassik

struct SearchTests {
    static let british = Locale(identifier: "en_GB")

    static func song(
        _ id: String, album: String, track: Int = 1, title: String? = nil, composer: String, work: String? = nil,
        albumArtist: String? = nil, year: Int? = nil, people: [(role: String, sub: String?, name: String)] = [],
        grouping: String? = nil
    ) -> Song {
        Song(
            id: id, title: title ?? "Track \(track)", album: album, albumId: album, artist: albumArtist,
            displayAlbumArtist: albumArtist, track: track, discNumber: 1, year: year, displayComposer: composer,
            contributors: people.map {
                Song.Contributor(role: $0.role, subRole: $0.sub, artist: Song.Artist(id: $0.name, name: $0.name))
            },
            works: work.map { [Song.Work(name: $0)] },
            groupings: grouping.map { [$0] })
    }

    static let dvorak = "Antonín Dvořák"
    static let kubelik = "Rafael Kubelík"

    /// Two Dvořák symphonies under Kubelík, a Bach suite, a Chopin set and an album without WORK tags.
    static let songs: [Song] = [
        song(
            "d9", album: "Dvořák Symphonies", composer: dvorak, work: "Symphony No. 9 in E minor, Op. 95",
            albumArtist: kubelik, year: 1972,
            people: [("conductor", nil, kubelik), ("performer", nil, "Berliner Philharmoniker")]),
        song(
            "d8", album: "Dvořák Symphonies", track: 2, composer: dvorak, work: "Symphony No. 8 in G major, Op. 88",
            albumArtist: kubelik, year: 1972,
            people: [("conductor", nil, kubelik), ("performer", nil, "Berliner Philharmoniker")]),
        song(
            "d9b", album: "New World", composer: dvorak, work: "Symphony No. 9 in E minor, Op. 95",
            albumArtist: "Václav Talich", year: 1954, people: [("conductor", nil, "Václav Talich")]),
        song(
            "k1", album: "Kubelík plays", composer: kubelik, work: "Sonata for Violin",
            albumArtist: kubelik, year: 1960, people: [("performer", "violin", kubelik)]),
        song(
            "b1", album: "Cello Suites", composer: "Johann Sebastian Bach", work: "Suite No. 1, BWV 1007",
            albumArtist: "Clara Cellotest", people: [("performer", "cello", "Clara Cellotest")]),
        song(
            "c1", album: "Nocturnes", composer: "Frédéric Chopin", work: "Nocturne No. 1",
            people: [("performer", "piano", "Pia Nissimo")], grouping: "Nocturnes, Op. 9"),
        song(
            "e1", album: "Encores for Søren", title: "Humoresque", composer: dvorak, albumArtist: "Søren Strand",
            year: 2001),
        song(
            "e2", album: "Encores for Søren", track: 2, title: "Liebesleid", composer: "Fritz Kreisler",
            albumArtist: "Søren Strand", year: 2001),
    ]

    static let search = Search(index: WorkIndex(songs: songs))

    @Test func peopleHaveSeparateComposerAndPerformerSections() {
        let results = Search.Results(people: [
            Search.Person(
                name: "Performer", roles: [.init(label: "piano", count: 2, countsWorks: false)], recordings: 2),
            Search.Person(
                name: "Composer", roles: [.init(label: "composer", count: 1, countsWorks: true)], recordings: 1),
        ])
        #expect(results.composers.map(\.name) == ["Composer"])
        #expect(results.performers.map(\.name) == ["Performer"])
        let both = Self.search.results(for: "kubelik")
        #expect(both.composers.map(\.name) == [Self.kubelik])
        #expect(both.performers.isEmpty)
    }

    static let beethoven = "Ludwig van Beethoven"

    /// A WORK tag without the nickname that the track title carries, on an album whose title names neither.
    static let elise: [Song] = [
        song(
            "f1", album: "Piano Pieces", title: "Bagatelle No. 25 in A minor \u{201C}Für Elise\u{201D}",
            composer: beethoven, work: "Bagatelle in A minor, WoO 59", albumArtist: "Pia Nissimo"),
        song(
            "f2", album: "Piano Pieces", track: 2, title: "Elise Waltz", composer: "Ellis Elmer",
            work: "Waltz for Elise", albumArtist: "Pia Nissimo"),
    ]

    /// A track title finds its work under Works, and the result names that track. The album of a tagged track is
    /// no result, and no recording shows apart from its work (ADR 0067).
    @Test func aTrackTitleFindsItsWorkAndSaysWhich() throws {
        let results = Search(index: WorkIndex(songs: Self.elise)).results(for: "elise")
        #expect(results.works.map(\.title) == ["Waltz for Elise", "Bagatelle in A minor, WoO 59"])
        let bagatelle = try #require(results.works.last)
        #expect(results.workTracks[bagatelle.id] == "Bagatelle No. 25 in A minor \u{201C}Für Elise\u{201D}")
        #expect(results.workTracks[results.works[0].id] == nil, "A title match names a track")
        #expect(results.albums.isEmpty, "A tagged track title finds its album")
    }

    /// Every word must match the work or one of its track titles.
    @Test func aTrackTitleMatchNeedsEveryWord() {
        let search = Search(index: WorkIndex(songs: Self.elise))
        #expect(search.results(for: "beethoven elise").works.map(\.title) == ["Bagatelle in A minor, WoO 59"])
        #expect(search.results(for: "elise waltz").works.map(\.title) == ["Waltz for Elise"])
        #expect(search.results(for: "beethoven waltz").isEmpty)
    }

    /// The conditions keep the track that found a work.
    @Test func conditionsKeepTheTrackThatFoundAWork() {
        let index = WorkIndex(songs: Self.elise)
        let found = Search(index: index).results(for: "elise")
        let narrowed = SearchFilters(index: index).narrow(
            found, by: [Search.Condition(terms: [Search.Term(scope: .composers, name: Self.beethoven)])])
        #expect(narrowed.results.works.map(\.title) == ["Bagatelle in A minor, WoO 59"])
        #expect(narrowed.results.workTracks == found.workTracks)
    }

    @Test func foldsCaseAndDiacritics() {
        let results = Self.search.results(for: "DVORAK")
        #expect(results.people.map(\.name) == [Self.dvorak])
        #expect(Set(results.works.map(\.title)).count == 2)
        #expect(Self.search.results(for: "frederic").people.map(\.name) == ["Frédéric Chopin"])
        #expect(Self.search.results(for: "kubelik").people.map(\.name) == [Self.kubelik])
    }

    @Test func foldsLettersThatDoNotDecompose() {
        #expect(Search.fold("Søren Łukasz Straße Æther Œuvre") == "soren lukasz strasse aether oeuvre")
        #expect(Self.search.results(for: "soren").albums.map(\.title) == ["Encores for Søren"])
    }

    @Test func matchesWordStartsOnly() {
        #expect(Self.search.results(for: "sym").works.count == 2)
        #expect(Self.search.results(for: "phony").isEmpty)
        #expect(Self.search.results(for: "noct").works.map(\.title) == ["Nocturne No. 1"])
    }

    @Test func everyWordMustStartAWord() {
        let works = Self.search.results(for: "symphony e minor").works
        #expect(works.map(\.title) == ["Symphony No. 9 in E minor, Op. 95"])
        #expect(Self.search.results(for: "symphony cello").isEmpty)
    }

    /// No catalogue prefixes and no aliases (ADR 0025): the words match as they are written.
    @Test func knowsNoCataloguePrefixesOrAliases() {
        #expect(Self.search.results(for: "op 95").works.count == 1)
        #expect(Self.search.results(for: "op95").isEmpty)
        #expect(Self.search.results(for: "bwv 1007").works.count == 1)
        #expect(Self.search.results(for: "bwv1007").isEmpty)
        #expect(Self.search.results(for: "kv 95").isEmpty)
    }

    @Test func findsAWorkThroughItsComposerAndItsSet() {
        #expect(Self.search.results(for: "bach").works.map(\.title) == ["Suite No. 1, BWV 1007"])
        #expect(Self.search.results(for: "nocturnes op 9").works.map(\.title) == ["Nocturne No. 1"])
    }

    /// A title that starts with the text comes first, then a title that holds it, then a composer match.
    @Test func ranksTitleStartsFirst() {
        let titles = Self.search.results(for: "s").works.map(\.title)
        #expect(
            titles == [
                "Sonata for Violin", "Suite No. 1, BWV 1007", "Symphony No. 8 in G major, Op. 88",
                "Symphony No. 9 in E minor, Op. 95",
            ])
        let minor = Self.search.results(for: "minor").works.map(\.title)
        #expect(minor == ["Symphony No. 9 in E minor, Op. 95"])
    }

    /// The WORK tag and the movement names leave out a nickname. The track titles keep it, and it finds the work.
    @Test func aNicknameInTheTrackTitlesFindsTheWork() throws {
        let beethoven = "Ludwig van Beethoven"
        let work = "Symphonie Nr. 3 Es-Dur, Op. 55"
        let index = WorkIndex(songs: [
            Self.song(
                "e1", album: "Beethoven 3", title: "Symphonie Nr.3 Es-Dur \"Eroica\": I. Allegro con brio",
                composer: beethoven, work: work),
            Self.song(
                "e2", album: "Beethoven 3", track: 2, title: "Symphonie Nr.3 Es-Dur \"Eroica\": II. Marcia funebre",
                composer: beethoven, work: work),
            Self.song("f1", album: "Beethoven 5", title: "Symphonie Nr.5", composer: beethoven, work: "Op. 67"),
        ])
        let found = Search(index: index).results(for: "eroica").works
        #expect(found.map(\.title) == [work])
        #expect(Search(index: index).results(for: "eroica").workTracks.isEmpty)
        #expect(try #require(found.first).nicknames == ["Eroica"])
    }

    @Test func albumsMatchOnNameArtistAndUntaggedTrackTitles() {
        #expect(Self.search.results(for: "encores").albums.map(\.title) == ["Encores for Søren"])
        #expect(Self.search.results(for: "strand").albums.map(\.title) == ["Encores for Søren"])
        let liebesleid = Self.search.results(for: "liebesleid")
        #expect(liebesleid.albums.map(\.title) == ["Encores for Søren"])
        #expect(liebesleid.works.isEmpty)
        #expect(liebesleid.albumTracks.values.sorted() == ["Liebesleid"])
        #expect(Self.search.results(for: "encores").albumTracks.isEmpty)
        // A track with a WORK tag finds its work, not its album.
        let track = Self.search.results(for: "track")
        #expect(track.albums.isEmpty)
        #expect(track.works.count == 5)
        #expect(Set(track.workTracks.values) == ["Track 1", "Track 2"])
    }

    /// An album without WORK tags is an album, not a work.
    @Test func anUntaggedAlbumIsNoWork() {
        let results = Self.search.results(for: "humoresque")
        #expect(results.works.isEmpty)
        #expect(results.albums.map(\.title) == ["Encores for Søren"])
    }

    @Test func emptyTextFindsNothing() {
        #expect(Self.search.results(for: "").isEmpty)
        #expect(Self.search.results(for: "  ,. ").isEmpty)
    }

    /// One count for each role, the biggest first, in prose (ADR 0031).
    @Test func countsEachRoleOfAPerson() throws {
        let kubelik = try #require(Self.search.results(for: "rafael").people.first)
        #expect(kubelik.composes)
        #expect(
            kubelik.counts(locale: Self.british)
                == "Conductor on 2\u{00A0}recordings, composer of 1\u{00A0}work and violin on 1\u{00A0}recording")
        let dvorak = try #require(Self.search.results(for: "antonin").people.first)
        #expect(dvorak.counts(locale: Self.british) == "Composer of 3\u{00A0}works")
        let talich = try #require(Self.search.results(for: "talich").people.first)
        #expect(!talich.composes)
        #expect(talich.counts(locale: Self.british) == "Conductor on 1\u{00A0}recording")
    }

    /// People in more of the library come first.
    @Test func peopleWithMoreRecordingsComeFirst() {
        let names = Self.search.results(for: "b").people.map(\.name)
        #expect(names == ["Berliner Philharmoniker", "Johann Sebastian Bach"])
    }

    /// A work without a composer tag is found by its title, never by the stand-in name.
    @Test func unknownComposerIsNoPerson() {
        let index = WorkIndex(songs: [Self.song("u", album: "Mystery", composer: "", work: "Lost Piece")])
        let search = Search(index: index)
        #expect(search.results(for: "unknown").isEmpty)
        #expect(search.results(for: "lost").works.map(\.title) == ["Lost Piece"])
    }
}
