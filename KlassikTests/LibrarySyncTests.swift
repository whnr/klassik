import XCTest
@testable import Klassik

/// Syncs the fixture library from Navidrome. The screens workflow runs it against the fixture server.
final class LibrarySyncTests: XCTestCase {
    @MainActor
    func testSyncsFixtureLibraryAndFindsClassicalAlbums() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["KLASSIK_SERVER_URL"], let url = ServerCredentials.normalizedURL(from: server) else {
            throw XCTSkip("No fixture server configured")
        }
        let client = SubsonicClient(credentials: ServerCredentials(
            url: url, username: env["KLASSIK_USERNAME"] ?? "", password: env["KLASSIK_PASSWORD"] ?? ""))
        let cache = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let library = Library(cacheURL: cache, defaults: defaults)

        await library.sync(with: client)

        XCTAssertNil(library.syncError)
        XCTAssertEqual(library.songs.count, 24)
        XCTAssertEqual(library.albumCount, 7)
        XCTAssertEqual(library.classical.count, 22, "every track but the jazz album")
        XCTAssertEqual(library.classicalAlbumCount, 6)
        let finale = try XCTUnwrap(library.songs.first { $0.movements?.first?.number == 3 && $0.album == "Mendelssohn: Violin Concerto" })
        XCTAssertEqual(finale.works?.first?.name, "Violin Concerto in E minor, Op. 64")
        XCTAssertEqual(finale.movements?.first?.count, 3)

        let composers = library.index.composers.map(\.name)
        XCTAssertEqual(composers, ["Johann Sebastian Bach", "Ludwig van Beethoven", "Johannes Brahms", "Felix Mendelssohn", "Wolfgang Amadeus Mozart"])
        let fifth = try XCTUnwrap(library.index.composers.first { $0.name == "Ludwig van Beethoven" }?.works.first)
        XCTAssertEqual(fifth.title, "Symphony No. 5 in C minor, Op. 67")
        XCTAssertEqual(fifth.recordings.map(\.year), [1990, 2015])
        XCTAssertEqual(fifth.recordings.first?.performers, "Testing Philharmonic, Anna Probe")

        let reloaded = Library(cacheURL: cache, defaults: defaults)
        await reloaded.load(for: client.credentials)
        XCTAssertEqual(reloaded.songs.count, 24)
    }
}
