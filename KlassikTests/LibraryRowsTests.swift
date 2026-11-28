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
        #expect(kinds(rows) == [.composers, .favourites, .links, .added, .heard])
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
        #expect(kinds(rows) == [.favourites, .composers, .links, .added, .heard])
        rows.move(fromOffsets: [0], toOffset: 2)
        #expect(kinds(rows) == [.composers, .favourites, .links, .added, .heard])
    }

    @Test func moveAmongSomeRowsKeepsTheOthersInPlace() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        rows.insert(.albums, below: rows.rows[0].id)
        // composers, albums, favourites. Only composers and favourites show.
        let shown = rows.rows.filter { $0.kind != .albums }.map(\.id)
        rows.move(fromOffsets: [1], toOffset: 0, among: shown)
        #expect(kinds(rows) == [.favourites, .albums, .composers, .links, .added, .heard])
    }

    @Test func rowsSurviveARestart() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let first = open(suite).rows
        first.move(fromOffsets: [1], toOffset: 0)
        first.insert(.albums, below: first.rows[0].id)
        let ids = first.rows.map(\.id)
        let second = open(suite).rows
        #expect(kinds(second) == [.favourites, .albums, .composers, .links, .added, .heard])
        #expect(second.rows.map(\.id) == ids)
    }

    @Test func rowsAreStoredInTheDeviceFileNotInUserDefaults() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let (rows, file) = open(suite)
        rows.move(fromOffsets: [1], toOffset: 0)
        #expect(file.data.library?.rows.map(\.kind) == [.favourites, .composers, .links, .added, .heard])
        #expect(suite.object(forKey: LibraryRows.legacyKey) == nil)
    }

    @Test func resetGoesBackToTheDefaultRows() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        let rows = open(suite).rows
        rows.move(fromOffsets: [1], toOffset: 0)
        rows.reset()
        #expect(kinds(rows) == [.composers, .favourites, .links, .added, .heard])
        #expect(kinds(open(suite).rows) == [.composers, .favourites, .links, .added, .heard])
    }

    @Test func existingOrderMovesOnceFromUserDefaults() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        suite.set(["favourites", "composers"], forKey: LibraryRows.legacyKey)
        let (rows, file) = open(suite)
        #expect(kinds(rows) == [.favourites, .composers, .links, .added, .heard])
        #expect(file.data.library != nil)
        #expect(suite.object(forKey: LibraryRows.legacyKey) == nil)

        // The old order is gone and cannot come back over a later change.
        rows.move(fromOffsets: [1], toOffset: 0)
        suite.set(["favourites", "composers"], forKey: LibraryRows.legacyKey)
        #expect(kinds(open(suite).rows) == [.composers, .favourites, .links, .added, .heard])
    }

    @Test func oldOrderWithUnknownAndRepeatedNamesStaysWhole() {
        #expect(
            LibraryRows.legacyOrder(stored: ["favourites", "playlists", "favourites"])
                == [.favourites, .composers, .links, .added, .heard])
        #expect(LibraryRows.legacyOrder(stored: ["favourites"]) == [.favourites, .composers, .links, .added, .heard])
        #expect(LibraryRows.legacyOrder(stored: []) == [.composers, .favourites, .links, .added, .heard])
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
        #expect(kinds(rows) == [.composers, .albums, .favourites, .links, .added, .heard])
        #expect(rows.rows[1].id == added.id)
    }

    @Test func insertWithoutAGivenRowPutsTheRowAtTheTop() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        rows.insert(.albums, below: nil)
        #expect(kinds(rows) == [.albums, .composers, .favourites, .links, .added, .heard])
        rows.insert(.performers, below: "no such row")
        #expect(kinds(rows) == [.performers, .albums, .composers, .favourites, .links, .added, .heard])
    }

    @Test func storedWorksRowsFallAwayWithoutLosingOtherData() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let json = """
            {"favouriteWorks":["w"],"library":{"version":1,"rows":[
              {"id":"a","kind":"composers"},
              {"id":"b","kind":"works","source":"works"},
              {"id":"c","kind":"albums","count":6}]}}
            """
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store().url)
        let (rows, file) = open(try defaults())
        #expect(file.loadError == nil)
        #expect(file.data.favouriteWorks == ["w"])
        #expect(rows.rows.map(\.id) == ["a", "c"])
        #expect(rows.rows.last?.count == 6)
    }

    @Test func listenerAddsTheSameKindMoreThanOnce() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        rows.insert(.composers, below: nil)
        #expect(kinds(rows) == [.composers, .composers, .favourites, .links, .added, .heard])
        #expect(Set(rows.rows.map(\.id)).count == 6)
    }

    @Test func aSecondDailyPickIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = open(try defaults()).rows
        #expect(rows.insert(.pick, below: nil) != nil)
        #expect(rows.canInsert(.pick) == false)
        #expect(rows.insert(.pick, below: rows.rows[0].id) == nil)
        #expect(kinds(rows) == [.pick, .composers, .favourites, .links, .added, .heard])
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
        #expect(kinds(rows) == [.favourites, .links, .added, .heard])
        #expect(kinds(open(suite).rows) == [.favourites, .links, .added, .heard])
        rows.delete("no such row")
        #expect(kinds(rows) == [.favourites, .links, .added, .heard])
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

    /// A device file of a newer build: a setup with an unknown row kind, an unknown field and a changed shape.
    private let newerFile = """
        {"favouriteWorks":["w"],"library":{"version":2,"rows":{"order":[{"id":"a","kind":"playlists","tags":[1,2.5,null,true]}]},"extra":"x"}}
        """

    /// The `library` value of a device file, as bytes with sorted keys.
    private func libraryBytes(_ file: Data) throws -> Data {
        let object = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: try #require(object["library"]), options: .sortedKeys)
    }

    @Test func aNewerFormIsNeitherShownNorOverwritten() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try defaults()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(newerFile.utf8).write(to: store().url)
        let before = try libraryBytes(Data(contentsOf: store().url))

        let file = ListenerFile(store: store())
        #expect(file.loadError == nil)
        let rows = LibraryRows(file: file, defaults: suite)
        #expect(kinds(rows) == [.composers, .favourites, .links, .added, .heard])
        rows.move(fromOffsets: [1], toOffset: 0)
        rows.insert(.works, below: nil)
        rows.delete(rows.rows[0].id)
        rows.reset()

        var changed = file.data
        changed.favouriteWorks.insert("w2")
        try file.save(changed)
        let after = try Data(contentsOf: store().url)
        #expect(try libraryBytes(after) == before)
        #expect(ListenerFile(store: store()).data.favouriteWorks == ["w", "w2"])
    }

    @Test func aSetupThatDoesNotReadStillLetsTheRestOfTheFileLoad() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let broken = [
            #"{"favouriteWorks":["w"],"library":{"version":"two","rows":[]}}"#,
            #"{"favouriteWorks":["w"],"library":{"version":1,"rows":"none"}}"#,
            #"{"favouriteWorks":["w"],"library":[1,2]}"#,
            #"{"favouriteWorks":["w"],"library":{"rows":[]}}"#,
        ]
        for json in broken {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: store().url)
            let before = try libraryBytes(Data(contentsOf: store().url))
            let file = ListenerFile(store: store())
            #expect(file.loadError == nil)
            #expect(file.data.favouriteWorks == ["w"])
            let rows = LibraryRows(file: file, defaults: try defaults())
            #expect(kinds(rows) == [.composers, .favourites, .links, .added, .heard])
            var changed = file.data
            changed.favouriteWorks.insert("w2")
            try file.save(changed)
            #expect(try libraryBytes(Data(contentsOf: store().url)) == before)
        }
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
