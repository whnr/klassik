import Foundation
import Testing

@testable import Klassik

actor FavouriteFixture: FavouriteServer {
    var stars = Starred()
    var writes: [[String]] = []
    var fails = false

    func configure(_ stars: Starred, fails: Bool = false) {
        self.stars = stars
        self.fails = fails
    }

    func star(_ ids: [String]) throws {
        if fails { throw URLError(.notConnectedToInternet) }
        writes.append(ids)
    }

    func unstar(_ ids: [String]) throws {
        if fails { throw URLError(.notConnectedToInternet) }
        writes.append(ids.map { "-" + $0 })
    }

    func getStarred() throws -> Starred {
        if fails { throw URLError(.notConnectedToInternet) }
        return stars
    }
}

@MainActor
struct RecordingOrderTests {
    private let credentials = ServerCredentials(
        url: URL(string: "https://music.example.org")!, username: "listener", password: "fixture")

    private func song(_ album: String, year: Int? = nil, starred: Bool = false, track: Int = 1) -> Song {
        Song(
            id: "\(album)-\(track)", title: "Movement \(track)", album: album, albumId: album,
            track: track, year: year, genres: [.init(name: "Classical")],
            contributors: [.init(role: "conductor", artist: .init(id: "person-\(album)", name: "Person \(album)"))],
            works: [.init(name: "Work")], starred: starred ? "2026-11-16" : nil)
    }

    private func library(_ songs: [Song], root: URL) async throws -> Library {
        let cache = root.appending(path: "library.json")
        try LibraryCache(server: credentials.url, username: credentials.username, syncedAt: .now, songs: songs).write(
            to: cache)
        let library = Library(cacheURL: cache, defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        await library.load(for: credentials)
        return library
    }

    private func store(_ root: URL) -> DeviceStore {
        DeviceStore(server: credentials.url, username: credentials.username, folder: root.appending(path: "listeners"))
    }

    @Test func deviceFilesSeparateServersAndUsersAndSurviveReconnection() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = store(root)
        let otherUser = DeviceStore(
            server: credentials.url, username: "other", folder: root.appending(path: "listeners"))
        let otherServer = DeviceStore(
            server: URL(string: "https://other.example.org")!, username: credentials.username,
            folder: root.appending(path: "listeners"))
        let data = DeviceStore.Data(favouriteWorks: ["work"], recordingOrder: ["work": ["album"]])
        try first.save(data)
        #expect(try store(root).load() == data)
        #expect(try otherUser.load() == DeviceStore.Data())
        #expect(try otherServer.load() == DeviceStore.Data())
        #expect(first.url != otherUser.url && first.url != otherServer.url)
        #expect(!first.url.lastPathComponent.contains(credentials.username))
        try first.delete()
        #expect(try first.load() == DeviceStore.Data())
    }

    @Test func ordersEveryTierAndExplainsRaisedRows() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let songs = [
            song("f1", year: 1960, starred: true), song("f2", year: 1970, starred: true),
            song("performer", year: 1950), song("album", year: 1940), song("new", year: 2025),
            song("old", year: 2000), song("unknown"),
        ]
        let library = try await library(songs, root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let server = FavouriteFixture()
        await server.configure(
            Starred(
                song: Array(songs.prefix(2)), artist: [.init(id: "person-performer", name: "Person performer")],
                album: [Album(id: "album", name: "album")]))
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.refresh()
        order.moveFavourites(of: work, from: [1], to: 0)
        let rows = order.rows(of: work)
        #expect(rows.map(\.recording.album) == ["f1", "f2", "performer", "album", "new", "old", "unknown"])
        #expect(rows[2].reason == "Favourite performer: Person performer")
        #expect(rows[3].reason == "Favourite album: album")
        #expect(rows[0].reason == nil && rows[4].reason == nil)
        #expect(order.reference(of: work)?.id == rows[0].id)
        let reconnected = RecordingOrder(library: library, store: store(root))
        #expect(reconnected.reference(of: work)?.id == rows[0].id)
    }

    @Test func togglesAllTracksAndKeepsOtherFavouritesAndQueueCopiesCurrent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library(
            [song("a", starred: true), song("b", starred: true), song("b", track: 2)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let b = try #require(work.recordings.first { $0.album == "b" })
        let server = FavouriteFixture()
        let order = RecordingOrder(library: library, store: store(root), server: server)
        #expect(!order.isFavourite(b, of: work))
        await order.toggle(b, of: work)
        #expect(order.rows(of: work).filter(\.isFavourite).count == 2)
        #expect(order.favouriteCount == 2)
        #expect(order.isFavourite(b, of: work))
        #expect(await server.writes == [["b-1", "b-2"]])
        order.moveFavourites(of: work, from: [1], to: 0)
        #expect(order.reference(of: work)?.album == "b")
        await order.toggle(b, of: work)
        #expect(!order.isFavourite(b, of: work))
        #expect(order.rows(of: work).filter(\.isFavourite).map(\.recording.album) == ["a"])
        #expect(await server.writes == [["b-1", "b-2"], ["-b-1", "-b-2"]])
    }

    @Test func workFavouriteIsLocalAndSurvivesSignOut() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let server = FavouriteFixture()
        let order = RecordingOrder(library: library, store: store(root), server: server)
        order.toggle(work)
        #expect(order.favouriteCount == 1)
        #expect(order.favouriteWorks.map(\.id) == [work.id])
        library.clear()
        let reconnected = RecordingOrder(library: library, store: store(root), server: server)
        #expect(reconnected.isFavourite(work))
        #expect(await server.writes.isEmpty)
        reconnected.toggle(work)
        #expect(!reconnected.isFavourite(work))
    }

    @Test func refreshDropsExternalUnstarsAndDoesNotRestoreTheirPosition() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let songs = [song("a", year: 2000, starred: true), song("b", year: 2020, starred: true)]
        let library = try await library(songs, root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let server = FavouriteFixture()
        let order = RecordingOrder(library: library, store: store(root), server: server)
        order.moveFavourites(of: work, from: [1], to: 0)
        await server.configure(Starred(song: [songs[1]]))
        await order.refresh()
        #expect(try store(root).load().recordingOrder[work.id] == [work.recordings[1].id])
        await server.configure(Starred(song: songs))
        await order.refresh()
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "a"])
    }

    @Test func missingYearsAndEqualYearsHaveStableOrderAndNoFavourite() {
        let work = WorkIndex.Work(
            id: "work", title: "Work", composer: "C", isTagged: true,
            recordings: [
                .init(id: "b", album: "B", year: 2000, songs: []),
                .init(id: "a", album: "A", year: 2000, songs: []),
                .init(id: "unknown", album: "U", songs: []),
            ])
        let order = RecordingOrder(library: Library())
        #expect(order.rows(of: work).map(\.id) == ["a", "b", "unknown"])
        #expect(order.rows(of: work).allSatisfy { !$0.isFavourite })
        #expect(order.reference(of: work)?.id == "a")
    }

    @Test func composerAndTechnicalStarsDoNotRaiseARecording() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var older = song("old", year: 1900)
        let composer = Song.Contributor(role: "composer", artist: .init(id: "composer", name: "Composer"))
        older.contributors = [
            composer,
            .init(role: "producer", artist: .init(id: "producer", name: "Producer")),
        ]
        var newer = song("new", year: 2020)
        newer.contributors?.append(composer)
        let library = try await library([older, newer], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let server = FavouriteFixture()
        await server.configure(
            Starred(artist: [.init(id: "composer", name: "Composer"), .init(id: "producer", name: "Producer")]))
        let order = RecordingOrder(library: library, server: server)
        await order.refresh()
        #expect(order.reference(of: work)?.album == "new")
        #expect(order.rows(of: work).allSatisfy { $0.reason == nil })
    }

    @Test func newestIsReferenceWithoutFavouritesAndInvalidMovesCannotChangeIt() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("old", year: 1900), song("new", year: 2020)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let order = RecordingOrder(library: library, store: store(root))
        #expect(order.reference(of: work)?.album == "new")
        order.moveFavourites(of: work, from: [0], to: 1)
        #expect(order.reference(of: work)?.album == "new")
        #expect(try store(root).load().recordingOrder.isEmpty)
    }

    @Test func corruptDeviceDataReportsAnErrorAndRemainsOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root)
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data("invalid".utf8)
        try bytes.write(to: store.url)
        let order = RecordingOrder(library: Library(), store: store)
        #expect(order.error != nil)
        #expect(try Data(contentsOf: store.url) == bytes)
    }

    @Test func failuresKeepTheLibraryAndDeviceStateAndReportAnError() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let recording = try #require(work.recordings.first)
        let server = FavouriteFixture()
        await server.configure(Starred(), fails: true)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(recording, of: work)
        #expect(order.error != nil)
        #expect(!order.isFavourite(recording, of: work))
        #expect(!order.isSaving)
        #expect(try store(root).load() == DeviceStore.Data())
    }
}
