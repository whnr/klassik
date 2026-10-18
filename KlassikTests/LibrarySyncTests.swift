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
        let client = SubsonicClient(
            credentials: ServerCredentials(
                url: url, username: env["KLASSIK_USERNAME"] ?? "", password: env["KLASSIK_PASSWORD"] ?? ""))
        let cache = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let library = Library(cacheURL: cache, defaults: defaults)

        await library.sync(with: client)

        XCTAssertNil(library.syncError)
        XCTAssertEqual(library.songs.count, 27)
        XCTAssertEqual(library.albumCount, 8)
        XCTAssertEqual(library.classical.count, 22, "every track but the jazz and FLAC albums")
        XCTAssertEqual(library.classicalAlbumCount, 6)
        let finale = try XCTUnwrap(
            library.songs.first { $0.movements?.first?.number == 3 && $0.album == "Mendelssohn: Violin Concerto" })
        XCTAssertEqual(finale.works?.first?.name, "Violin Concerto in E minor, Op. 64")
        XCTAssertEqual(finale.movements?.first?.count, 3)

        let composers = library.index.composers.map(\.name)
        XCTAssertEqual(
            composers,
            [
                "Johann Sebastian Bach", "Ludwig van Beethoven", "Johannes Brahms", "Felix Mendelssohn",
                "Wolfgang Amadeus Mozart",
            ])
        let fifth = try XCTUnwrap(library.index.composers.first { $0.name == "Ludwig van Beethoven" }?.works.first)
        XCTAssertEqual(fifth.title, "Symphony No. 5 in C minor, Op. 67")
        XCTAssertEqual(fifth.recordings.map(\.year), [1990, 2015])
        XCTAssertEqual(fifth.recordings.first?.performers, "Testing Philharmonic, Anna Probe")
        let gain = try XCTUnwrap(fifth.recordings.first?.songs.first?.replayGain)
        XCTAssertEqual(gain, Song.ReplayGain(trackGain: 5, albumGain: 6, trackPeak: 0.7, albumPeak: 0.8))
        XCTAssertEqual(fifth.recordings.last?.songs.first?.replayGain, Song.ReplayGain())

        // Navidrome keeps a star on the track. The reference recording follows from it, and the server returns it.
        let reference = try XCTUnwrap(fifth.recordings.last)
        let ids = reference.songs.map(\.id)
        try await client.star(ids)
        await library.sync(with: client)
        let starred = try XCTUnwrap(library.index.composers.first { $0.name == "Ludwig van Beethoven" }?.works.first)
        XCTAssertEqual(starred.defaultRecording?.album, reference.album)
        XCTAssertTrue(starred.defaultRecording?.isReference == true)
        XCTAssertEqual(starred.recordings.filter(\.isReference).count, 1)
        try await client.unstar(ids)

        let reloaded = Library(cacheURL: cache, defaults: defaults)
        await reloaded.load(for: client.credentials)
        XCTAssertEqual(reloaded.songs.count, 27)

        // Nothing changed on the server, so the next start keeps the cache and does not fetch again.
        let cachedAt = try XCTUnwrap(reloaded.syncedAt)
        await reloaded.syncIfChanged(with: client)
        XCTAssertEqual(reloaded.syncedAt, cachedAt)
        XCTAssertNil(reloaded.syncError)
    }
}
