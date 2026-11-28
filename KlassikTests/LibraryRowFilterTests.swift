import Foundation
import Testing

@testable import Klassik

@MainActor
struct LibraryRowFilterTests {
    private func row(_ kind: LibraryRowKind, _ conditions: [[RecentSearch.Term]]) -> LibraryRowSetup {
        var row = LibraryRowSetup(kind: kind)
        row.conditions = conditions
        return row
    }

    private let chopin = RecentSearch.Term(kind: .composer, name: "Frédéric Chopin")
    private let strauss = RecentSearch.Term(kind: .composer, name: "Richard Strauss")

    private var index: WorkIndex {
        WorkIndex(songs: [
            LibraryPageTests.song("c", work: "Ballade", conductor: "Pianist", created: "2026-11-01T00:00:00Z"),
            LibraryPageTests.song(
                "s", composer: "Richard Strauss", work: "Song", conductor: "Singer", created: "2026-11-01T00:00:00Z"),
            LibraryPageTests.song(
                "b", composer: "Bach", work: "Suite", conductor: "Pianist", created: "2026-11-01T00:00:00Z"),
        ])
    }

    @Test(arguments: [LibraryRowKind.composers, .performers, .recordings, .albums, .added])
    func conditionsNarrowEverySourceBeforeTheCount(kind: LibraryRowKind) {
        var row = row(kind, [[chopin, strauss]])
        let page = LibraryPageTests.page(rows: [row], index: index)
        #expect(page.sections.first?.cards.count == 2)
        row.conditions.append([RecentSearch.Term(kind: .conductor, name: "Pianist")])
        let narrower = LibraryPageTests.page(rows: [row], index: index)
        #expect(narrower.sections.first?.cards.count == 1)
        row.conditions = [[RecentSearch.Term(kind: .composer, name: "Missing")]]
        #expect(LibraryPageTests.page(rows: [row], index: index).sections.isEmpty)
    }

    @Test func matchingUsesOneRecordingForAllConditions() {
        let index = WorkIndex(songs: [
            LibraryPageTests.song("a", composer: "Chopin", work: "Ballade", conductor: "A"),
            LibraryPageTests.song("b", composer: "Strauss", work: "Song", conductor: "B"),
        ])
        let row = row(
            .performers,
            [
                [.init(kind: .composer, name: "Chopin")], [.init(kind: .conductor, name: "B")],
            ])
        #expect(LibraryPageTests.page(rows: [row], index: index).sections.isEmpty)
    }

    @Test func countUsesRowItemsBeforeTheDisplayLimit() {
        var row = LibraryRowSetup(kind: .composers)
        row.count = 6
        #expect(LibraryPage.matchingCount(row, index: LibraryPageTests.index, favourites: .init()) == 11)
        row.conditions = [[.init(kind: .composer, name: "Composer 01")]]
        #expect(LibraryPage.matchingCount(row, index: LibraryPageTests.index, favourites: .init()) == 1)
    }

    @Test func pickerTermsStayInsideTheRowsSource() {
        let index = index
        let favourite = index.composers.first { $0.name == "Bach" }!
        let row = LibraryRowSetup(kind: .favourites)
        let filters = SearchFilters(index: index)
        let pool = LibraryPage.filterPool(row, index: index, favourites: .init(composers: [favourite]))
        let choices = filters.choices(in: .composers, conditions: [], pool: pool)
        #expect(choices.map { $0.term.name } == ["Bach"])
    }

    @Test func favouritesKeepTheirSourceWhenFiltered() {
        let index = index
        let favourite = index.composers.first { $0.name == "Bach" }!
        let row = row(.favourites, [[chopin]])
        let page = LibraryPageTests.page(rows: [row], favourites: .init(composers: [favourite]), index: index)
        #expect(page.sections.isEmpty)
    }

    @Test func storedConditionsRoundTripThroughTheEditor() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DeviceStore(server: URL(string: "https://music.example.org")!, username: "listener", folder: folder)
        let rows = LibraryRows(file: ListenerFile(store: store), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let editor = LibraryEditor(rows: rows)
        let id = rows.rows[0].id
        let conditions = [Search.Condition(terms: [chopin.searchTerm, strauss.searchTerm])]
        editor.filter(conditions, ofRow: id)
        #expect(rows.rows[0].searchConditions == conditions)
        let restored = LibraryRows(
            file: ListenerFile(store: store), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(restored.rows[0].searchConditions == conditions)
    }

    @Test func alternativesUseTheListFormatterOfTheAppLanguage() {
        let row = row(.composers, [[chopin, strauss], [.init(kind: .genre, name: "Song")]])
        #expect(row.filterSummary(locale: Locale(identifier: "en")) == "Frédéric Chopin or Richard Strauss, Song")
        #expect(row.filterSummary(locale: Locale(identifier: "de")) == "Frédéric Chopin oder Richard Strauss, Song")
    }

    @Test func filterTitlesAndSubtitlesFollowTheSpecimen() {
        let single = row(.composers, [[chopin]])
        #expect(LibraryPage.title(of: single) == "Composers, Frédéric Chopin")
        let multiple = row(.composers, [[chopin, strauss], [.init(kind: .genre, name: "Song")]])
        #expect(LibraryPage.title(of: multiple) == "Composers, filtered")
        #expect(multiple.filterSummary == "Frédéric Chopin or Richard Strauss, Song")
        #expect(multiple.subtitle == "Frédéric Chopin or Richard Strauss, Song, random, 9 faces")
    }
}
