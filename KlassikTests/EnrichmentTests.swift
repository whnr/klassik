import Foundation
import Testing

@testable import Klassik

struct CatalogueNumberTests {
    @Test(arguments: [
        ("Violin Concerto in G minor, Op. 8 No. 2, RV 315 \"Summer\"", "RV 315"),
        ("Étude in C major, Op. 10 No. 1", "op. 10 no. 1"),
        ("Nocturne No. 20 in C-sharp minor, KK IVa/16", "KK IVa/16"),
        ("Symphony No. 5 in C minor, Op. 67", "op. 67"),
        ("Piano Concerto No. 21 in C major, K. 467", "K. 467"),
        ("Cello Suite No. 1 in G major, BWV 1007", "BWV 1007"),
        ("Piano Sonata in B-flat major, D. 960", "D. 960"),
        ("Piano Sonata No. 62 in E-flat major, Hob. XVI:52", "Hob. XVI:52"),
        ("Sonata, op. 35", "op. 35"),
    ])
    func findsTheNumber(title: String, number: String) {
        #expect(CatalogueNumber.find(in: title)?.text == number)
    }

    @Test(arguments: ["Symphony in D major", "Nocturne No. 20 in C-sharp minor, Op. posth.", "Opera arias"])
    func findsNoNumber(title: String) {
        #expect(CatalogueNumber.find(in: title) == nil)
    }

    @Test func matchesHowMusicBrainzWritesIt() throws {
        let kk = try #require(CatalogueNumber.find(in: "Nocturne, KK IVa/16"))
        #expect(kk.matches("Nocturne no. 20 in C‐sharp minor, op. posth. 1 no. 16, B. 49, KKIVa/16"))
        let opus = try #require(CatalogueNumber.find(in: "Sonata, Op. 1"))
        #expect(!opus.matches("Sonata, op. 10"))
        let mazurka = try #require(CatalogueNumber.find(in: "Mazurka No. 36 in A minor, Op. 59 No. 1"))
        #expect(mazurka.matches("Mazurkas, op. 59: No. 1 in A minor. Moderato"))
        #expect(opus.matches("Sonata, op. 1: I. Allegro"))
    }
}

struct MusicBrainzTests {
    @Test func movementWalksUpToItsWork() async throws {
        let stub = MusicBrainzStub()
        let facts = try #require(try await stub.musicBrainz.work(id: MusicBrainzStub.summerFirstMovement))
        #expect(facts.id == MusicBrainzStub.summer)
        #expect(facts.composed == YearSpan(1723))
        #expect(facts.source == .musicBrainz)
        #expect(facts.composerID == MusicBrainzStub.vivaldi)
    }

    /// One étude of a set is a work of its own: only a movement walks up.
    @Test func partOfASetStays() async throws {
        let stub = MusicBrainzStub()
        let facts = try #require(try await stub.musicBrainz.work(id: MusicBrainzStub.etude))
        #expect(facts.id == MusicBrainzStub.etude)
        #expect(facts.composed == YearSpan(1829))
        #expect(stub.requests == ["work/\(MusicBrainzStub.etude)"])
    }

    @Test func unknownIDGivesNothing() async throws {
        #expect(try await MusicBrainzStub().musicBrainz.work(id: "00000000-0000-0000-0000-000000000000") == nil)
    }

    @Test func busyServerGetsAnotherTry() async throws {
        let stub = MusicBrainzStub()
        stub.fail("work/\(MusicBrainzStub.etude)", status: 503)
        #expect(try await stub.musicBrainz.work(id: MusicBrainzStub.etude)?.composed == YearSpan(1829))
        #expect(stub.requests.count == 2)
    }

    @Test func serverErrorThrows() async {
        let stub = MusicBrainzStub()
        stub.fail("work/\(MusicBrainzStub.etude)", status: 500)
        await #expect(throws: MusicBrainz.Failure.http(500)) {
            try await stub.musicBrainz.work(id: MusicBrainzStub.etude)
        }
    }

    @Test func clearBestMatchIsConfident() async throws {
        let found = try await MusicBrainzStub().musicBrainz.candidates(
            composer: "Frédéric Chopin", catalogue: #require(CatalogueNumber.find(in: "Nocturne, Op. 9 No. 2")))
        // The two Andante movements drop, because whole works are in the list.
        #expect(found.map(\.score) == [100, 74, 68])
        #expect(
            MusicBrainz.confident(found, for: "Nocturne No. 2 in E-flat major, Op. 9 No. 2")?.id
                == MusicBrainzStub.nocturne)
    }

    /// Movements outrank their work, and MusicBrainz holds this concerto twice.
    @Test func workWinsOverItsMovementsAndItsTwin() async throws {
        let found = try await MusicBrainzStub().musicBrainz.candidates(
            composer: "Felix Mendelssohn",
            catalogue: #require(CatalogueNumber.find(in: "Violin Concerto in E minor, Op. 64")))
        #expect(found.map(\.score) == [95, 92])
        #expect(
            MusicBrainz.confident(found, for: "Violin Concerto in E minor, Op. 64")?.id
                == "c230858f-8b2b-3e77-aa3e-777743980263")
    }

    @Test func aMovementAloneStays() {
        let movement = [WorkCandidate(id: "m", title: "Mazurkas, op. 59: No. 1", score: 100)]
        #expect(movement.preferringWholeWorks == movement)
        let mixed = movement + [WorkCandidate(id: "w", title: "Mazurka, op. 59 no. 1", score: 80)]
        #expect(mixed.preferringWholeWorks.map(\.id) == ["w"])
    }

    /// Real matches for Op. 46 and Op. 28 No. 20: a ballet arrangement outranks the work, and a set of variations
    /// shares as few words as the prelude itself.
    @Test func sharedWordsDecideBetweenRivals() {
        let allegro = [
            WorkCandidate(id: "ballet", title: "Chopiniana, op. 46", score: 100),
            WorkCandidate(id: "work", title: "Allegro de concert in A major, op. 46", score: 90),
        ]
        #expect(MusicBrainz.confident(allegro, for: "Allegro de concert in A major, Op. 46")?.id == "work")
        let prelude = [
            WorkCandidate(id: "a", title: "Prelude, op. 28 no. 20", score: 100),
            WorkCandidate(id: "b", title: "Prelude, Op. 28, No. 20 and Variations", score: 89),
        ]
        #expect(MusicBrainz.confident(prelude, for: "Prelude No. 20 in C minor, Op. 28 No. 20") == nil)
    }

    @Test func singleMatchWithALowScoreIsConfident() {
        let found = [WorkCandidate(id: "a", title: "Étude in E‐flat minor, op. 10 no. 6", score: 81)]
        #expect(MusicBrainz.confident(found, for: "Étude in E-flat minor, Op. 10 No. 6")?.id == "a")
        #expect(MusicBrainz.confident([WorkCandidate(id: "b", title: "Étude", score: 60)], for: "Étude") == nil)
    }

    @Test func twoGoodMatchesAreNotConfident() async throws {
        let found = try await MusicBrainzStub().musicBrainz.candidates(
            composer: "Frédéric Chopin", catalogue: #require(CatalogueNumber.find(in: "Nocturne, KK IVa/16")))
        #expect(found.count == 2)
        #expect(MusicBrainz.confident(found, for: "Lento con gran espressione, KK IVa/16") == nil)
    }

    @Test func composerByName() async throws {
        let found = try await MusicBrainzStub().musicBrainz.composer(named: "Frédéric Chopin")
        #expect(found == ComposerFacts(id: MusicBrainzStub.chopin, name: "Fryderyk Chopin", born: 1810, died: 1849))
    }

    @Test func wikidataGivesTheEarliestYear() async throws {
        #expect(try await MusicBrainzStub().wikidata.published(musicBrainzID: MusicBrainzStub.nocturne) == 1832)
    }

    @Test func yearsOfDates() {
        #expect(YearSpan.year(of: "1723") == 1723)
        #expect(YearSpan.year(of: "1829-10-01") == 1829)
        #expect(YearSpan.year(of: "+1725-00-00T00:00:00Z") == 1725)
        #expect(YearSpan.year(of: "-0300") == -300)
        #expect(YearSpan.year(of: "") == nil)
        #expect(YearSpan(1829, 1832).text == "1829–1832")
    }
}

@MainActor
struct EnrichmentTests {
    nonisolated static func song(_ id: String, composer: String, work: String, workID: String? = nil) -> Song {
        Song(
            id: id, title: work, album: "Album \(id)", albumId: id, displayComposer: composer,
            works: [Song.Work(name: work, musicBrainzId: workID)])
    }

    nonisolated static let index = WorkIndex(songs: [
        song("1", composer: "Antonio Vivaldi", work: "Summer", workID: MusicBrainzStub.summerFirstMovement),
        song("2", composer: "Frédéric Chopin", work: "Étude in C major, Op. 10 No. 1"),
        song("3", composer: "Frédéric Chopin", work: "Nocturne in E-flat major, Op. 9 No. 2"),
        song("4", composer: "Frédéric Chopin", work: "Lento con gran espressione, KK IVa/16"),
        song("5", composer: "Frédéric Chopin", work: "Nocturne in C-sharp minor, Op. posth."),
    ])

    nonisolated static func work(_ title: String) -> WorkIndex.Work {
        index.composers.flatMap(\.works).first { $0.title == title }!
    }

    static func cacheURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "enrichment-\(UUID().uuidString).json")
    }

    @Test func passFillsDatesLinksAndComposers() async {
        let stub = MusicBrainzStub()
        let enrichment = Enrichment(musicBrainz: stub.musicBrainz, wikidata: stub.wikidata, cacheURL: Self.cacheURL())
        await enrichment.enrich(Self.index)

        let summer = Self.work("Summer")
        #expect(enrichment.link(of: summer) == .tagged(MusicBrainzStub.summerFirstMovement))
        #expect(enrichment.composed(summer)?.span == YearSpan(1723))
        #expect(enrichment.composed(summer)?.source == .musicBrainz)

        let etude = Self.work("Étude in C major, Op. 10 No. 1")
        #expect(enrichment.link(of: etude) == .found(MusicBrainzStub.etude))
        #expect(enrichment.composed(etude)?.span == YearSpan(1829))

        // MusicBrainz has no date for this nocturne; Wikidata has.
        let nocturne = Self.work("Nocturne in E-flat major, Op. 9 No. 2")
        #expect(enrichment.composed(nocturne)?.span == YearSpan(1832))
        #expect(enrichment.composed(nocturne)?.source == .wikidata)

        guard case .candidates(let found) = enrichment.link(of: Self.work("Lento con gran espressione, KK IVa/16"))
        else {
            Issue.record("KK IVa/16 needs the listener")
            return
        }
        #expect(found.count == 2)
        #expect(enrichment.link(of: Self.work("Nocturne in C-sharp minor, Op. posth.")) == .noCatalogue)

        #expect(enrichment.composer(named: "Antonio Vivaldi")?.born == 1678)
        #expect(enrichment.composer(named: "Frédéric Chopin")?.died == 1849)
        #expect(enrichment.lastError == nil)
    }

    @Test func secondPassFetchesNothing() async {
        let stub = MusicBrainzStub()
        let enrichment = Enrichment(musicBrainz: stub.musicBrainz, wikidata: stub.wikidata, cacheURL: Self.cacheURL())
        await enrichment.enrich(Self.index)
        let count = stub.requests.count
        await enrichment.enrich(Self.index)
        #expect(stub.requests.count == count)
    }

    @Test func listenerConfirmsOnceAndTheirYearWins() async throws {
        let stub = MusicBrainzStub()
        let url = Self.cacheURL()
        let enrichment = Enrichment(musicBrainz: stub.musicBrainz, wikidata: stub.wikidata, cacheURL: url)
        await enrichment.enrich(Self.index)
        let work = Self.work("Lento con gran espressione, KK IVa/16")
        guard case .candidates(let found) = enrichment.link(of: work) else {
            Issue.record("KK IVa/16 needs the listener")
            return
        }
        await enrichment.confirm(found[0], for: work)
        #expect(enrichment.link(of: work) == .found(found[0].id))

        let summer = Self.work("Summer")
        enrichment.setYear(1720, for: summer)
        #expect(enrichment.composed(summer)?.span == YearSpan(1720))
        #expect(enrichment.composed(summer)?.source == .listener)

        try await Task.sleep(for: .milliseconds(200))
        let reloaded = Enrichment(musicBrainz: stub.musicBrainz, wikidata: stub.wikidata, cacheURL: url)
        #expect(reloaded.link(of: work) == .found(found[0].id))
        #expect(reloaded.composed(summer)?.span == YearSpan(1720))
    }

    @Test func rejectedMatchStaysRejected() async {
        let stub = MusicBrainzStub()
        let enrichment = Enrichment(musicBrainz: stub.musicBrainz, wikidata: stub.wikidata, cacheURL: Self.cacheURL())
        await enrichment.enrich(Self.index)
        let etude = Self.work("Étude in C major, Op. 10 No. 1")
        enrichment.reject(etude)
        #expect(enrichment.link(of: etude) == .unmatched)
        await enrichment.enrich(Self.index)
        #expect(enrichment.link(of: etude) == .unmatched)
        await enrichment.lookUpAgain(etude)
        #expect(enrichment.link(of: etude) == .found(MusicBrainzStub.etude))
    }

    @Test func networkFailureEndsThePassAndTheNextGoesOn() async {
        let stub = MusicBrainzStub()
        stub.fail("work/\(MusicBrainzStub.summerFirstMovement)", status: 500)
        let enrichment = Enrichment(musicBrainz: stub.musicBrainz, wikidata: stub.wikidata, cacheURL: Self.cacheURL())
        await enrichment.enrich(Self.index)
        #expect(enrichment.lastError != nil)
        #expect(enrichment.composed(Self.work("Summer")) == nil)
        await enrichment.enrich(Self.index)
        #expect(enrichment.lastError == nil)
        #expect(enrichment.composed(Self.work("Summer"))?.span == YearSpan(1723))
    }
}

struct TimelineTests {
    @Test func periodsOfComposers() {
        #expect(Timeline.Period.of(born: 1678, died: 1741) == .baroque)
        #expect(Timeline.Period.of(born: 1756, died: 1791) == .classical)
        #expect(Timeline.Period.of(born: 1797, died: 1828) == .romantic)
        #expect(Timeline.Period.of(born: 1810, died: 1849) == .romantic)
        #expect(Timeline.Period.of(born: nil, died: nil) == nil)
        #expect(Timeline.Period.of(year: 1500) == .early)
        #expect(Timeline.Period.of(year: 2001) == .contemporary)
    }

    @Test func undatedWorksSitInTheLifetime() {
        let index = EnrichmentTests.index
        let years = ["Summer": 1723, "Étude in C major, Op. 10 No. 1": 1829]
        let timeline = Timeline(
            index: index, composed: { years[$0.title].map { YearSpan($0) } },
            lifetime: { $0 == "Frédéric Chopin" ? (1810, 1849) : nil })

        #expect(timeline.sections.map(\.period) == [.baroque, .romantic])
        #expect(timeline.sections[0].entries.map(\.work.title) == ["Summer"])
        let romantic = timeline.sections[1].entries
        #expect(romantic.first?.work.title == "Étude in C major, Op. 10 No. 1")
        #expect(romantic.first?.isApproximate == false)
        #expect(romantic.dropFirst().allSatisfy { $0.isApproximate && $0.span == YearSpan(1810, 1849) })
        #expect(timeline.undated.isEmpty)
    }

    @Test func composerWithoutAnyDateIsUndated() {
        let timeline = Timeline(index: EnrichmentTests.index, composed: { _ in nil }, lifetime: { _ in nil })
        #expect(timeline.sections.isEmpty)
        #expect(timeline.undated.count == 5)
    }
}
