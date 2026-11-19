import CoreGraphics
import Foundation
import Testing

@testable import Klassik

/// The Chronology module on fixture songs and facts: ADR 0016 (overview, focus, rows, opening), ADR 0022 (the
/// scrub across the lines on screen, rows that stand for several works) and ADR 0026 (contemporaries).
@MainActor
struct ChronologyTests {
    /// Life dates and work period starts (P2031) as Wikidata gives them. Handel and Mendelssohn have no P2031.
    nonisolated static let facts: [String: PersonFacts] = [
        "Antonio Vivaldi": person("Antonio Vivaldi", 1678, 1741, active: 1703),
        "Johann Sebastian Bach": person("Johann Sebastian Bach", 1685, 1750, active: 1703),
        "George Frideric Handel": person("George Frideric Handel", 1685, 1759),
        "Wolfgang Amadeus Mozart": person("Wolfgang Amadeus Mozart", 1756, 1791, active: 1761),
        "Ludwig van Beethoven": person("Ludwig van Beethoven", 1770, 1827, active: 1782),
        "Felix Mendelssohn": person("Felix Mendelssohn", 1809, 1847),
        "Frédéric Chopin": person("Frédéric Chopin", 1810, 1849, active: 1817),
        "Johannes Brahms": person("Johannes Brahms", 1833, 1897, active: 1851),
        "Arvo Pärt": person("Arvo Pärt", 1935, nil, active: 1958),
        // Wikidata knows the person, but not when they were born.
        "Hildegard Fixture": person("Hildegard Fixture", nil, nil),
    ]

    /// Composition years, as MusicBrainz gives them. Every other work has no date.
    nonisolated static let years: [String: Int] = [
        "Le quattro stagioni": 1723,
        "Symphony No. 5": 1808,
        "Symphony No. 3": 1804,
        "Violin Concerto, Op. 64": 1844,
        "Étude, Op. 10 No. 1": 1829,
        "Étude, Op. 10 No. 2": 1830,
        "Étude, Op. 10 No. 3": 1832,
        "Nocturne, Op. 9 No. 2": 1830,
        "Ballade No. 1": 1835,
        "Ballade No. 4": 1842,
        "Fratres": 1977,
    ]

    nonisolated static let index = WorkIndex(
        songs: [
            ("Antonio Vivaldi", "Le quattro stagioni"),
            ("Johann Sebastian Bach", "Cello Suite No. 1"),
            ("George Frideric Handel", "Messiah"),
            ("Wolfgang Amadeus Mozart", "Requiem"),
            ("Ludwig van Beethoven", "Symphony No. 5"),
            ("Ludwig van Beethoven", "Symphony No. 3"),
            ("Felix Mendelssohn", "Violin Concerto, Op. 64"),
            ("Frédéric Chopin", "Étude, Op. 10 No. 1"),
            ("Frédéric Chopin", "Étude, Op. 10 No. 2"),
            ("Frédéric Chopin", "Étude, Op. 10 No. 3"),
            ("Frédéric Chopin", "Nocturne, Op. 9 No. 2"),
            ("Frédéric Chopin", "Ballade No. 1"),
            ("Frédéric Chopin", "Ballade No. 4"),
            ("Frédéric Chopin", "Mazurka, Op. 7 No. 1"),
            ("Frédéric Chopin", "Mazurka, Op. 7 No. 2"),
            ("Johannes Brahms", "Symphony No. 4"),
            ("Arvo Pärt", "Fratres"),
            ("Hildegard Fixture", "Ordo virtutum"),
            ("Anonymous Fixture", "Kyrie"),
        ].enumerated().map { EnrichmentTests.song(String($0.offset), composer: $0.element.0, work: $0.element.1) })

    nonisolated static func person(_ name: String, _ born: Int?, _ died: Int?, active: Int? = nil) -> PersonFacts {
        PersonFacts(qid: "Q\(abs(name.hashValue % 100_000))", name: name, born: born, died: died, activeFrom: active)
    }

    static let chronology = Chronology(
        index: index, facts: { facts[$0] }, year: { years[$0.title] }, now: 2026)

    static func composer(_ name: String) -> Chronology.Composer { chronology.composer(named: name)! }

    static func work(_ title: String) -> WorkIndex.Work {
        index.composers.flatMap(\.works).first { $0.title == title }!
    }

    // MARK: ADR 0016: the overview

    @Test func overviewHoldsComposersWithLifeDatesInBirthOrder() {
        #expect(
            Self.chronology.composers.map(\.name) == [
                "Antonio Vivaldi", "George Frideric Handel", "Johann Sebastian Bach", "Wolfgang Amadeus Mozart",
                "Ludwig van Beethoven", "Felix Mendelssohn", "Frédéric Chopin", "Johannes Brahms", "Arvo Pärt",
            ])
        // Without a birth year, or without facts, a composer stays off the chart.
        #expect(Self.chronology.composer(named: "Hildegard Fixture") == nil)
        #expect(Self.chronology.composer(named: "Anonymous Fixture") == nil)
    }

    @Test func overviewYearsRunFromTheFirstBirthToTheLastLine() {
        // A living composer's line runs to the current year.
        #expect(Self.composer("Arvo Pärt").end(now: 2026) == 2026)
        #expect(Self.chronology.overviewYears == 1668...2031)
    }

    @Test func periodsAreBandsInOrder() {
        let periods = Chronology.periods
        #expect(periods.map(\.name) == ["Renaissance", "Baroque", "Classical", "Romantic", "Modern"])
        #expect(zip(periods, periods.dropFirst()).allSatisfy { $0.end == $1.start })
    }

    // MARK: ADR 0016: one composer

    @Test func worksAreRowsByYearWhileTheyFit() {
        let chopin = Self.composer("Frédéric Chopin")
        let scale = Self.chronology.scale(of: chopin, height: 2000, rowHeight: 20)
        let rows = Self.chronology.rows(of: chopin, scale: scale)
        #expect(rows.map(\.years) == ["1829", "1830", "1832", "1835", "1842", "No date"])
        #expect(
            rows.map(\.title) == [
                "Étude, Op. 10 No. 1", "2 works", "Étude, Op. 10 No. 3", "Ballade No. 1",
                "Ballade No. 4", "2 works",
            ])
        // A row sits at its year: the life fills the height above the undated row.
        #expect(rows[0].y == scale.y(1829))
        #expect(scale.y(chopin.born) == 10)
        #expect(scale.y(1849) == scale.span)
    }

    @Test func rowsThatDoNotFitMergeIntoASpanWithACount() {
        let chopin = Self.composer("Frédéric Chopin")
        let scale = Self.chronology.scale(of: chopin, height: 200, rowHeight: 20)
        let rows = Self.chronology.rows(of: chopin, scale: scale)
        let dated = rows.filter { $0.from != nil }
        #expect(dated.map(\.years) == ["1829–35", "1842"])
        #expect(dated.map(\.title) == ["5 works", "Ballade No. 4"])
        // Rows never overlap.
        #expect(zip(rows, rows.dropFirst()).allSatisfy { $1.y - $0.y >= scale.rowHeight - 0.001 })
    }

    @Test func spanAcrossTwoCenturiesKeepsBothYearsWhole() {
        let row = Chronology.Row(from: 1898, to: 1901, works: [], y: 0)
        #expect(row.years == "1898–1901")
    }

    @Test func posthumousSourceYearKeepsItsLabelAndReachableRow() throws {
        let work = Self.work("Ballade No. 4")
        let index = WorkIndex(songs: work.recordings.flatMap(\.songs))
        let chronology = Chronology(index: index, facts: { Self.facts[$0] }, year: { _ in 1870 }, now: 2026)
        let chopin = try #require(chronology.composer(named: "Frédéric Chopin"))
        let scale = chronology.scale(of: chopin, height: 600, rowHeight: 20)
        let row = try #require(chronology.rows(of: chopin, scale: scale).first)
        #expect(scale.years == 1810...1849)
        #expect(row.years == "1870")
        #expect(row.title == "Ballade No. 4")
        #expect(row.works.map(\.id) == [work.id])
        #expect(!row.opensList)
        #expect(row.y - scale.rowHeight / 2 >= 0)
        #expect(row.y + scale.rowHeight / 2 <= scale.height)
        #expect(chopin.dated.first?.year == 1870)
    }

    @Test func outOfLifeRowsFitWithoutOverlappingOtherRows() {
        var chopin = Self.composer("Frédéric Chopin")
        chopin.works[0].year = 1700
        chopin.works[5].year = 1900
        let scale = Self.chronology.scale(of: chopin, height: 200, rowHeight: 20)
        let rows = Self.chronology.rows(of: chopin, scale: scale)
        #expect(rows.allSatisfy { $0.y >= scale.rowHeight / 2 && $0.y <= scale.height - scale.rowHeight / 2 })
        #expect(zip(rows, rows.dropFirst()).allSatisfy { $1.y - $0.y >= scale.rowHeight - 0.001 })
        #expect(rows.flatMap(\.works).map(\.id).sorted() == chopin.works.map(\.id).sorted())
    }

    @Test func oneUndatedWorkHasACountAndOpensAList() throws {
        let brahms = Self.composer("Johannes Brahms")
        let scale = Self.chronology.scale(of: brahms, height: 600, rowHeight: 20)
        let row = try #require(Self.chronology.rows(of: brahms, scale: scale).last)
        #expect(row.years == "No date")
        #expect(row.title == "1 work")
        #expect(row.opensList)
        #expect(row.works.map(\.title) == ["Symphony No. 4"])
        #expect(row.y == scale.undatedY)
    }

    @Test func undatedWorksAreOneRowAtTheEnd() {
        let chopin = Self.composer("Frédéric Chopin")
        let scale = Self.chronology.scale(of: chopin, height: 600, rowHeight: 20)
        let undated = Self.chronology.rows(of: chopin, scale: scale).last
        #expect(undated?.from == nil)
        #expect(undated?.works.map(\.title) == ["Mazurka, Op. 7 No. 1", "Mazurka, Op. 7 No. 2"])
        #expect(undated?.y == scale.undatedY)
        // No undated work is placed on a guessed year: the midpoint of the life is gone.
        #expect(chopin.dated.allSatisfy { Self.years[$0.work.title] == $0.year })
    }

    @Test func lineIsDimBeforeTheWorkPeriodStartAndBrightFromIt() {
        let chronology = Self.chronology
        #expect(
            chronology.segments(of: Self.composer("Frédéric Chopin")) == [
                .init(from: 1810, to: 1817, dim: true), .init(from: 1817, to: 1849, dim: false),
            ])
        // Without P2031 the line has no shading.
        #expect(
            chronology.segments(of: Self.composer("Felix Mendelssohn")) == [.init(from: 1809, to: 1847, dim: false)])
    }

    @Test func opensOnTheComposerOfWhatPlays() {
        let chronology = Self.chronology
        let left = Chronology.Position(level: .composer, composer: "Johannes Brahms")
        #expect(
            chronology.opening(playing: Self.work("Symphony No. 5"), left: left)
                == .init(level: .composer, composer: "Ludwig van Beethoven"))
        // Nothing plays: where the listener left it.
        #expect(chronology.opening(playing: nil, left: left) == left)
        let overview = Chronology.Position(level: .overview, composer: "Johannes Brahms")
        #expect(chronology.opening(playing: nil, left: overview) == overview)
        // A composer that plays but has no life dates cannot open the chart.
        #expect(chronology.opening(playing: Self.work("Kyrie"), left: left) == left)
        // First visit, or a composer that left the chart: the overview.
        #expect(chronology.opening(playing: nil, left: nil).level == .overview)
        #expect(
            chronology.opening(playing: nil, left: .init(level: .composer, composer: "Anonymous Fixture")).level
                == .overview)
    }

    @Test func placeOpensOnANewPlayingWorkAndElseWhereTheListenerLeftIt() throws {
        let suite = "chronology-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let place = ChronologyPlace(defaults: defaults)
        let fifth = Self.work("Symphony No. 5")
        #expect(place.open(Self.chronology, playing: fifth).composer == "Ludwig van Beethoven")
        // The listener moves on while the same work plays: the place stays there.
        place.keep(.init(level: .composer, composer: "Frédéric Chopin"))
        #expect(place.open(Self.chronology, playing: fifth).composer == "Frédéric Chopin")
        // A new work opens on its composer again.
        #expect(place.open(Self.chronology, playing: Self.work("Requiem")).composer == "Wolfgang Amadeus Mozart")
        // The last opened composer stays on the device, for the mark in the overview (ADR 0022).
        place.keep(.init(level: .overview, composer: "Johannes Brahms"))
        let again = ChronologyPlace(defaults: defaults)
        #expect(again.lastOpened == "Johannes Brahms")
        #expect(again.open(Self.chronology, playing: nil) == .init(level: .overview, composer: "Johannes Brahms"))
        // The composer page opens on its composer, also while another composer plays.
        again.show(composer: "Felix Mendelssohn", playing: fifth)
        #expect(again.open(Self.chronology, playing: fifth).composer == "Felix Mendelssohn")
    }

    @Test func playingComposerOpensWhenPendingPersonFactsArrive() throws {
        let suite = "chronology-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let place = ChronologyPlace(defaults: defaults)
        let fifth = Self.work("Symphony No. 5")
        let pending = Chronology(index: Self.index, facts: { _ in nil }, year: { Self.years[$0.title] })
        #expect(place.open(pending, playing: fifth).level == .overview)
        #expect(place.open(pending, playing: fifth).level == .overview)
        #expect(place.open(Self.chronology, playing: fifth) == .init(level: .composer, composer: fifth.composer))
        place.keep(.init(level: .composer, composer: "Frédéric Chopin"))
        #expect(place.open(Self.chronology, playing: fifth).composer == "Frédéric Chopin")
    }

    // MARK: ADR 0022: the scrub

    @Test func scrubMapsTheChartWidthOntoTheLinesInOrder() {
        #expect(Chronology.lane(at: 0, width: 300, count: 3) == 0)
        #expect(Chronology.lane(at: 99, width: 300, count: 3) == 0)
        #expect(Chronology.lane(at: 100, width: 300, count: 3) == 1)
        #expect(Chronology.lane(at: 299, width: 300, count: 3) == 2)
        // A finger past either edge stays on the outer line.
        #expect(Chronology.lane(at: -20, width: 300, count: 3) == 0)
        #expect(Chronology.lane(at: 340, width: 300, count: 3) == 2)
        #expect(Chronology.lane(at: 10, width: 300, count: 0) == nil)
    }

    @Test func lanesKeepTheOverviewOrderSoTheFocusNeverSwapsPlaces() {
        let lanes = Self.chronology.lanes(of: Self.composer("Johann Sebastian Bach"))
        #expect(lanes.map(\.name) == ["Antonio Vivaldi", "George Frideric Handel", "Johann Sebastian Bach"])
        let x = (0..<lanes.count).map { Chronology.Chart.laneX($0, count: lanes.count, width: 390) }
        #expect(x == x.sorted())
        #expect(x.last! < Chronology.Chart.rowsX(width: 390))
    }

    @Test func aRowOfSeveralWorksListsThem() {
        let chopin = Self.composer("Frédéric Chopin")
        let rows = Self.chronology.rows(
            of: chopin, scale: Self.chronology.scale(of: chopin, height: 2000, rowHeight: 20))
        let row = rows.first { $0.years == "1830" }
        #expect(row?.works.map(\.title) == ["Étude, Op. 10 No. 2", "Nocturne, Op. 9 No. 2"])
    }

    // MARK: ADR 0026: contemporaries

    @Test func contemporariesOverlapTheActiveYearsWithTenYearsEachSide() {
        let chronology = Self.chronology
        // Mozart is active 1761–1791: the window is 1751–1801. Beethoven is active from 1782.
        #expect(chronology.composer(named: "Wolfgang Amadeus Mozart")?.window(now: 2026) == 1751...1801)
        #expect(
            chronology.contemporaries(of: Self.composer("Wolfgang Amadeus Mozart")).map(\.name) == [
                "George Frideric Handel", "Ludwig van Beethoven",
            ])
    }

    @Test func workDatesDoNotDecideWhoIsAContemporary() {
        // Handel and Bach hold no dated work, and still stand beside Vivaldi.
        let contemporaries = Self.chronology.contemporaries(of: Self.composer("Antonio Vivaldi")).map(\.name)
        #expect(contemporaries == ["George Frideric Handel", "Johann Sebastian Bach"])
        #expect(Self.composer("George Frideric Handel").dated.isEmpty)
    }

    @Test func withoutAWorkPeriodStartTheWindowIsTheWholeLifeWithNoBuffer() {
        let mendelssohn = Self.composer("Felix Mendelssohn")
        #expect(mendelssohn.window(now: 2026) == 1809...1847)
        // Brahms lived in those years, but is active from 1851: inside a buffer, outside the life.
        let names = Self.chronology.contemporaries(of: mendelssohn).map(\.name)
        #expect(names == ["Ludwig van Beethoven", "Frédéric Chopin"])
    }

    @Test func aContemporarysActiveYearsStartAtTheirWorkPeriodStart() {
        let brahms = Self.composer("Johannes Brahms")
        #expect(brahms.activeYears(now: 2026) == 1851...1897)
        // Chopin's window (1807–1859) holds Brahms's active years; Brahms's window (1841–1907) holds Chopin's.
        #expect(
            Self.chronology.contemporaries(of: Self.composer("Frédéric Chopin")).map(\.name).contains("Johannes Brahms")
        )
        #expect(Self.chronology.contemporaries(of: brahms).map(\.name) == ["Felix Mendelssohn", "Frédéric Chopin"])
    }
}
