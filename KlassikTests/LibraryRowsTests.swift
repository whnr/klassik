import Foundation
import Testing

@testable import Klassik

@MainActor
struct LibraryRowsTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func defaults() throws -> UserDefaults { try #require(UserDefaults(suiteName: UUID().uuidString)) }

    private func store() -> DeviceStore {
        DeviceStore(server: URL(string: "https://music.example.org")!, username: "listener", folder: root)
    }

    /// Opens the rows as a launch does: the device file is read again each time.
    private func open(_ defaults: UserDefaults) -> (rows: LibraryRows, file: ListenerFile) {
        let file = ListenerFile(store: store())
        return (LibraryRows(file: file, defaults: defaults), file)
    }

    private func kinds(_ rows: LibraryRows) -> [LibraryRowKind] { rows.rows.map(\.kind) }

    @Test func startsWithTheDefaultRows() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        #expect(kinds(rows) == [.composers, .favourites])
    }

    @Test func defaultRowsKeepTheirIdentityBetweenLaunches() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let first = open(suite).rows.rows.map(\.id)
        #expect(open(suite).rows.rows.map(\.id) == first)
        #expect(Set(first).count == first.count)
    }

    @Test func listenerMovesARow() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        rows.move(fromOffsets: [1], toOffset: 0)
        #expect(kinds(rows) == [.favourites, .composers])
        rows.move(fromOffsets: [0], toOffset: 2)
        #expect(kinds(rows) == [.composers, .favourites])
    }

    @Test func moveAmongSomeRowsKeepsTheOthersInPlace() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        rows.insert(.albums, below: rows.rows[0].id)
        // composers, albums, favourites. Only composers and favourites show.
        let shown = rows.rows.filter { $0.kind != .albums }.map(\.id)
        rows.move(fromOffsets: [1], toOffset: 0, among: shown)
        #expect(kinds(rows) == [.favourites, .albums, .composers])
    }

    @Test func rowsSurviveARestart() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let first = open(suite).rows
        first.move(fromOffsets: [1], toOffset: 0)
        first.insert(.albums, below: first.rows[0].id)
        let ids = first.rows.map(\.id)
        let second = open(suite).rows
        #expect(kinds(second) == [.favourites, .albums, .composers])
        #expect(second.rows.map(\.id) == ids)
    }

    @Test func rowsAreStoredInTheDeviceFileNotInUserDefaults() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let (rows, file) = open(suite)
        rows.move(fromOffsets: [1], toOffset: 0)
        #expect(file.data.library?.rows.map(\.kind) == [.favourites, .composers])
        #expect(suite.object(forKey: LibraryRows.legacyKey) == nil)
    }

    @Test func resetGoesBackToTheDefaultRows() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let rows = open(suite).rows
        rows.move(fromOffsets: [1], toOffset: 0)
        rows.reset()
        #expect(kinds(rows) == [.composers, .favourites])
        #expect(kinds(open(suite).rows) == [.composers, .favourites])
    }

    @Test func existingOrderMovesOnceFromUserDefaults() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        suite.set(["favourites", "composers"], forKey: LibraryRows.legacyKey)
        let (rows, file) = open(suite)
        #expect(kinds(rows) == [.favourites, .composers])
        #expect(file.data.library != nil)
        #expect(suite.object(forKey: LibraryRows.legacyKey) == nil)

        // The old order is gone and cannot come back over a later change.
        rows.move(fromOffsets: [1], toOffset: 0)
        suite.set(["favourites", "composers"], forKey: LibraryRows.legacyKey)
        #expect(kinds(open(suite).rows) == [.composers, .favourites])
    }

    @Test func oldOrderWithUnknownAndRepeatedNamesStaysWhole() {
        #expect(
            LibraryRows.legacyOrder(stored: ["favourites", "playlists", "favourites"]) == [.favourites, .composers])
        #expect(LibraryRows.legacyOrder(stored: ["favourites"]) == [.favourites, .composers])
        #expect(LibraryRows.legacyOrder(stored: []) == [.composers, .favourites])
    }

    @Test func oldOrderStaysInUserDefaultsWhenTheFileDoesNotLoad() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        suite.set(["favourites", "composers"], forKey: LibraryRows.legacyKey)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("damaged".utf8).write(to: store().url)
        let (rows, file) = open(suite)
        #expect(file.loadError != nil)
        #expect(suite.stringArray(forKey: LibraryRows.legacyKey) == ["favourites", "composers"])
        rows.move(fromOffsets: [1], toOffset: 0)
        #expect(file.loadError != nil)
        #expect(try Data(contentsOf: store().url) == Data("damaged".utf8))
    }

    @Test func insertPutsTheRowBelowTheGivenRow() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        let added = try #require(rows.insert(.albums, below: rows.rows[0].id))
        #expect(kinds(rows) == [.composers, .albums, .favourites])
        #expect(rows.rows[1].id == added.id)
    }

    @Test func insertWithoutAGivenRowPutsTheRowAtTheTop() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        rows.insert(.albums, below: nil)
        #expect(kinds(rows) == [.albums, .composers, .favourites])
        rows.insert(.works, below: "no such row")
        #expect(kinds(rows) == [.works, .albums, .composers, .favourites])
    }

    @Test func listenerAddsTheSameKindMoreThanOnce() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        rows.insert(.composers, below: nil)
        #expect(kinds(rows) == [.composers, .composers, .favourites])
        #expect(Set(rows.rows.map(\.id)).count == 3)
    }

    @Test func aSecondDailyPickIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        #expect(rows.insert(.pick, below: nil) != nil)
        #expect(rows.canInsert(.pick) == false)
        #expect(rows.insert(.pick, below: rows.rows[0].id) == nil)
        #expect(kinds(rows) == [.pick, .composers, .favourites])
        #expect(rows.canInsert(.albums))
    }

    @Test func deletingTheDailyPickAllowsANewOne() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        let pick = try #require(rows.insert(.pick, below: nil))
        rows.delete(pick.id)
        #expect(rows.canInsert(.pick))
    }

    @Test func listenerDeletesARow() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let rows = open(suite).rows
        rows.delete(rows.rows[0].id)
        #expect(kinds(rows) == [.favourites])
        #expect(kinds(open(suite).rows) == [.favourites])
        rows.delete("no such row")
        #expect(kinds(rows) == [.favourites])
    }

    @Test func listenerDeletesEveryRow() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let rows = open(suite).rows
        for row in rows.rows { rows.delete(row.id) }
        #expect(rows.rows.isEmpty)
        #expect(open(suite).rows.rows.isEmpty)
    }

    @Test func aNewRowStartsWithTheSettingsOfItsKind() {
        let composers = LibraryRowSetup(kind: .composers)
        #expect(composers.source == .composers)
        #expect(composers.sort == .random)
        #expect(composers.form == .faces)
        #expect(composers.count == 9)
        #expect(LibraryRowSetup(kind: .albums).sort == .newest)
        #expect(LibraryRowSetup(kind: .albums).form == .covers)
        #expect(LibraryRowSetup(kind: .heard).sort == .heard)
        #expect(LibraryRowSetup(kind: .links).form == .tiles)
        #expect(LibraryRowSetup(kind: .links).links == LibraryRowSetup.defaultLinks)
    }

    @Test func storedFormCarriesAVersion() throws {
        let data = try JSONEncoder().encode(LibrarySetup(rows: [LibraryRowSetup(kind: .albums)]))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["version"] as? Int == LibrarySetup.version)
    }

    @Test func storedFormRoundTrips() throws {
        var row = LibraryRowSetup(kind: .saved)
        row.conditions = [[RecentSearch.Term(kind: .composer, name: "Johann Sebastian Bach")]]
        row.sort = .az
        row.count = 12
        let setup = LibrarySetup(rows: [row, LibraryRowSetup(kind: .links)])
        let decoded = try JSONDecoder().decode(LibrarySetup.self, from: JSONEncoder().encode(setup))
        #expect(decoded == setup)
    }

    @Test func unknownKindsFallAway() throws {
        let json = """
            {"version":1,"rows":[
              {"id":"a","kind":"playlists"},
              {"id":"b","kind":"albums","sort":"newest","form":"covers","count":6},
              {"id":"c","kind":"composers","sort":"sideways"}]}
            """
        let setup = try JSONDecoder().decode(LibrarySetup.self, from: Data(json.utf8))
        #expect(setup.rows.map(\.id) == ["b"])
        #expect(setup.rows.first?.count == 6)
    }

    @Test func aStoredSecondDailyPickFallsAway() throws {
        let json = """
            {"version":1,"rows":[{"id":"a","kind":"pick"},{"id":"b","kind":"pick"},{"id":"c","kind":"albums"}]}
            """
        let setup = try JSONDecoder().decode(LibrarySetup.self, from: Data(json.utf8))
        #expect(setup.rows.map(\.id) == ["a", "c"])
    }

    @Test func aNewerFormIsNeitherShownNorOverwritten() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        var data = DeviceStore.Data()
        data.library = LibrarySetup(version: LibrarySetup.version + 1, rows: [LibraryRowSetup(kind: .albums)])
        try ListenerFile(store: store()).save(data)

        let rows = LibraryRows(file: ListenerFile(store: store()), defaults: suite)
        #expect(kinds(rows) == [.composers, .favourites])
        rows.move(fromOffsets: [1], toOffset: 0)
        rows.insert(.works, below: nil)
        rows.delete(rows.rows[0].id)
        rows.reset()
        #expect(ListenerFile(store: store()).data.library?.rows.map(\.kind) == [.albums])
    }

    @Test func aFileWithoutLibraryRowsStillLoads() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"favouriteWorks":["w"]}"#.utf8).write(to: store().url)
        let file = ListenerFile(store: store())
        #expect(file.loadError == nil)
        #expect(file.data.library == nil)
    }
}
