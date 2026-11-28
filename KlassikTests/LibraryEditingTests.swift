import Foundation
import Testing

@testable import Klassik

@MainActor
struct LibraryEditingTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    private func rows() throws -> LibraryRows {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = DeviceStore(server: URL(string: "https://music.example.org")!, username: "listener", folder: root)
        return LibraryRows(file: ListenerFile(store: store), defaults: defaults)
    }

    private func kinds(_ rows: LibraryRows) -> [LibraryRowKind] { rows.rows.map(\.kind) }

    // MARK: Choices

    @Test func sourceOfAKindRowChangesTheKind() {
        var row = LibraryRowSetup(kind: .composers)
        #expect(row.choices(for: .source).map(\.id) == ["composers", "performers", "recordings", "albums"])
        row.choose("albums", for: .source)
        #expect(row.kind == .albums)
        #expect(row.source == .albums)
    }

    @Test func aRowThatFixesItsSourceOffersOnlyThatSource() {
        #expect(LibraryRowSetup(kind: .favourites).choices(for: .source).map(\.title) == ["Favourites"])
        #expect(LibraryRowSetup(kind: .added).choices(for: .source).map(\.title) == ["Albums"])
        #expect(LibraryRowSetup(kind: .heard).choices(for: .source).map(\.title) == ["Recordings"])
        #expect(LibraryRowSetup(kind: .pick).choices(for: .source).map(\.title) == ["Whole library"])
    }

    @Test func formsOnlyFitTheSource() {
        #expect(LibraryRowSetup(kind: .composers).choices(for: .form).map(\.id) == ["faces"])
        #expect(LibraryRowSetup(kind: .performers).choices(for: .form).map(\.id) == ["faces"])
        #expect(LibraryRowSetup(kind: .favourites).choices(for: .form).map(\.id) == ["covers"])
        #expect(LibraryRowSetup(kind: .albums).choices(for: .form).map(\.id) == ["covers", "tiles"])
    }

    @Test func countsFollowTheForm() {
        var row = LibraryRowSetup(kind: .albums)
        #expect(row.choices(for: .count).map(\.id) == ["6", "9", "12"])
        row.choose("tiles", for: .form)
        #expect(row.choices(for: .count).map(\.id) == ["3", "6", "9"])
    }

    @Test func aFormChangeKeepsTheCountThatFitsAndResetsOneThatDoesNot() {
        var row = LibraryRowSetup(kind: .albums)
        row.choose("6", for: .count)
        row.choose("tiles", for: .form)
        #expect(row.count == 6)
        row.choose("3", for: .count)
        row.choose("covers", for: .form)
        #expect(row.count == 9)
    }

    @Test func aSourceChangeFitsFormAndSort() {
        var row = LibraryRowSetup(kind: .albums)
        row.choose("tiles", for: .form)
        row.choose("newest", for: .sort)
        row.choose("composers", for: .source)
        #expect(row.form == .faces)
        #expect(row.sort == .random)
        row.choose("albums", for: .source)
        #expect(row.form == .covers)
    }

    @Test func aChoiceOutsideTheOffersChangesNothing() {
        var row = LibraryRowSetup(kind: .composers)
        row.choose("tiles", for: .form)
        row.choose("newest", for: .sort)
        row.choose("7", for: .count)
        row.choose("favourites", for: .source)
        row.choose("works", for: .source)
        #expect(row == LibraryRowSetup(kind: .composers, id: row.id))
    }

    @Test func sortsThatHaveNoDataYetAreNotOffered() {
        let sorts = LibraryRowSetup(kind: .composers).choices(for: .sort).map(\.id)
        #expect(sorts == ["random", "az"])
        #expect(!LibraryRowSetup(kind: .albums).choices(for: .sort).map(\.id).contains("heard"))
        #expect(LibraryRowSetup(kind: .heard).choices(for: .sort).map(\.id).contains("heard"))
    }

    @Test func theCurrentChoiceIsMarked() {
        var row = LibraryRowSetup(kind: .albums)
        row.choose("12", for: .count)
        #expect(row.choices(for: .count).filter(\.isCurrent).map(\.id) == ["12"])
    }

    @Test func aDailyPickAndALinkListHaveOnlyTheSettingsThatExist() {
        #expect(LibraryRowSetup(kind: .pick).fields == [.source])
        #expect(LibraryRowSetup(kind: .links).fields.isEmpty)
        #expect(LibraryRowSetup(kind: .albums).fields == [.source, .sort, .form, .count])
    }

    // MARK: Subtitle

    @Test func subtitleSaysWhatTheRowShowsWithCommas() {
        #expect(LibraryRowSetup(kind: .composers).subtitle == "Random, 9 faces")
        #expect(LibraryRowSetup(kind: .added).subtitle == "Albums, newest first, 9 covers")
        var albums = LibraryRowSetup(kind: .albums)
        albums.choose("tiles", for: .form)
        albums.choose("6", for: .count)
        #expect(albums.subtitle == "Newest first, 6 tiles")
        #expect(LibraryRowSetup(kind: .favourites).subtitle == "Random, 9 faces and covers")
        #expect(LibraryRowSetup(kind: .pick).subtitle == "Sentence, from the whole library")
        #expect(LibraryRowSetup(kind: .links).subtitle == "Performers, Works, Albums, Genres, Roles, Playlists")
    }

    @Test func aSortThatTheTitleNamesIsNotRepeated() {
        var row = LibraryRowSetup(kind: .composers)
        row.choose("az", for: .sort)
        #expect(LibraryPage.title(of: row) == "Composers, A to Z")
        #expect(row.subtitle == "9 faces")
    }

    // MARK: Editor

    @Test func addPutsTheRowBelowTheSelectedRowAndOpensItsSettings() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = try rows()
        let editor = LibraryEditor(rows: rows)
        editor.select(rows.rows[0].id)
        editor.add(.albums)
        #expect(kinds(rows) == [.composers, .albums, .favourites, .links, .added, .heard])
        #expect(editor.selected == rows.rows[1].id)
        #expect(editor.level == .row(rows.rows[1].id))
    }

    @Test func addWithoutASelectionPutsTheRowAtTheTop() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = try rows()
        let editor = LibraryEditor(rows: rows)
        editor.add(.performers)
        #expect(kinds(rows) == [.performers, .composers, .favourites, .links, .added, .heard])
    }

    @Test func worksAreNotOfferedOrAdded() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!LibraryRowSetup.addable.contains(.works))
        let rows = try rows()
        let editor = LibraryEditor(rows: rows)
        let before = rows.rows
        #expect(!editor.canAdd(.works))
        editor.add(.works)
        #expect(rows.rows == before)
    }

    @Test func aSecondDailyPickCannotBeAdded() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = try rows()
        let editor = LibraryEditor(rows: rows)
        #expect(editor.canAdd(.pick))
        editor.add(.pick)
        #expect(!editor.canAdd(.pick))
        let before = rows.rows
        editor.level = .add
        editor.add(.pick)
        #expect(rows.rows == before)
        #expect(editor.level == .add)
    }

    @Test func deletingTheSelectedRowClearsTheSelectionAndLeavesItsLevel() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = try rows()
        let editor = LibraryEditor(rows: rows)
        let id = rows.rows[1].id
        editor.select(id)
        editor.delete(id)
        #expect(editor.selected == nil)
        #expect(editor.level == .list)
        #expect(kinds(rows) == [.composers, .links, .added, .heard])
    }

    @Test func deletingAnotherRowKeepsTheSelection() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = try rows()
        let editor = LibraryEditor(rows: rows)
        let keep = rows.rows[0].id
        editor.select(keep)
        editor.delete(rows.rows[2].id)
        #expect(editor.selected == keep)
    }

    @Test func aSettingChangesTheStoredRowAtOnce() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = try rows()
        let editor = LibraryEditor(rows: rows)
        let id = rows.rows[0].id
        editor.select(id)
        editor.choose("performers", for: .source, ofRow: id)
        #expect(rows.rows[0].kind == .performers)
        #expect(rows.rows[0].id == id)
        editor.choose("az", for: .sort, ofRow: id)
        #expect(rows.rows[0].sort == .az)
    }

    @Test func backLeavesOneLevelAtATime() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = try rows()
        let editor = LibraryEditor(rows: rows)
        let id = rows.rows[0].id
        editor.select(id)
        editor.level = .choice(id, .sort)
        editor.back()
        #expect(editor.level == .row(id))
        editor.back()
        #expect(editor.level == .list)
        #expect(editor.selected == id)
    }

    @Test func aLevelOfAMissingRowShowsTheList() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = LibraryEditor(rows: try rows())
        editor.level = .row("gone")
        #expect(editor.shownLevel == .list)
    }

    // MARK: Empty rows

    @Test func aRowThatTheTabHidesIsEmptyInTheEditor() {
        let standard = LibraryRows.standard
        let page = LibraryPageTests.page(rows: standard)
        let shown = standard.filter { page.shows($0.id) }.map(\.kind)
        // No favourites are marked, so the Favourites row has nothing to show.
        #expect(shown == [.composers, .links, .added])
        #expect(!page.shows("no such row"))
        #expect(!LibraryPageTests.page(rows: [LibraryRowSetup(kind: .heard, id: "h")]).shows("h"))
    }

    // MARK: Reorder

    @Test func aDragPastHalfTheNeighbourMovesTheLine() {
        let heights: [CGFloat] = [60, 60, 60, 60]
        #expect(LibraryReorder.destination(of: 0, translation: 20, heights: heights) == 0)
        #expect(LibraryReorder.destination(of: 0, translation: 40, heights: heights) == 1)
        #expect(LibraryReorder.destination(of: 0, translation: 200, heights: heights) == 3)
        #expect(LibraryReorder.destination(of: 3, translation: -100, heights: heights) == 1)
        #expect(LibraryReorder.destination(of: 3, translation: -900, heights: heights) == 0)
        #expect(LibraryReorder.destination(of: 1, translation: 0, heights: heights) == 1)
    }

    @Test func aDragCountsEachLineByItsOwnHeight() {
        let heights: [CGFloat] = [60, 100, 60]
        // The centre of line 0 is at 30; with 70 more it is at 100, inside line 1 (60 to 160).
        #expect(LibraryReorder.destination(of: 0, translation: 70, heights: heights) == 1)
        #expect(LibraryReorder.destination(of: 0, translation: 20, heights: heights) == 0)
    }

    @Test func moveOffsetsMatchOnMove() {
        #expect(LibraryReorder.offset(from: 0, to: 2) == 3)
        #expect(LibraryReorder.offset(from: 2, to: 0) == 0)
    }

    @Test func aDragTranslationLosesTheLayoutShiftOfItsMove() {
        let heights: [CGFloat] = [60, 100, 60]
        #expect(LibraryReorder.shift(from: 0, to: 1, heights: heights) == 100)
        #expect(LibraryReorder.shift(from: 1, to: 0, heights: heights) == -60)
        #expect(LibraryReorder.shift(from: 0, to: 2, heights: heights) == 160)
    }
}
