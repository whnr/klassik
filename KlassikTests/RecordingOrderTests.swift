import Foundation
import Observation
import Testing

@testable import Klassik

@MainActor private final class IndexChange {
    var seen = false
}

actor FavouriteFixture: FavouriteServer {
    var stars = Starred()
    var writes: [[String]] = []
    var failure: (any Error)?
    var readsFail = true

    static let offline = URLError(.notConnectedToInternet)
    static let refusal = SubsonicError.server(code: 50, message: "The user is not authorised")

    func configure(_ stars: Starred, failure: (any Error)? = nil, readsFail: Bool = true) {
        self.stars = stars
        self.failure = failure
        self.readsFail = readsFail
    }

    func star(_ ids: [String]) throws {
        if let failure { throw failure }
        writes.append(ids)
    }

    func unstar(_ ids: [String]) throws {
        if let failure { throw failure }
        writes.append(ids.map { "-" + $0 })
    }

    func starAlbum(_ id: String) throws {
        if let failure { throw failure }
        writes.append(["album:" + id])
    }

    func unstarAlbum(_ id: String) throws {
        if let failure { throw failure }
        writes.append(["-album:" + id])
    }

    func getStarred() throws -> Starred {
        if let failure, readsFail { throw failure }
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

    /// The mark and the order change before the server answers, so a tap shows its result at once.
    @Test func aFavouriteChangesStateAndPlaceBeforeTheServerAnswers() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a", year: 2001), song("b", year: 1990)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let b = try #require(work.recordings.first { $0.album == "b" })
        let server = FavouriteFixture()
        let order = RecordingOrder(library: library, store: store(root), server: server)
        #expect(order.rows(of: work).map(\.recording.album) == ["a", "b"])
        let confirm = try #require(order.begin(b, of: work))
        #expect(order.isFavourite(b, of: work))
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "a"])
        #expect(await server.writes.isEmpty)
        #expect(try store(root).load().recordingOrder[work.id] == [b.id])
        #expect(try store(root).load().pendingFavourites.map(\.songs) == [["b-1"]])
        await confirm()
        #expect(await server.writes == [["b-1"]])
        #expect(try store(root).load().recordingOrder[work.id] == [b.id])
        #expect(try store(root).load().pendingFavourites.isEmpty)
        #expect(!order.isSaving)
    }

    /// A refusal keeps the mark and the change, and the next changes still go to the server (ADR 0052).
    @Test func aRefusedFavouriteKeepsItsMarkAndWaits() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let songs = [song("a", year: 2001), song("b", year: 1990)]
        let library = try await library(songs, root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let b = try #require(work.recordings.first { $0.album == "b" })
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.refusal)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(b, of: work)
        #expect(order.isFavourite(b, of: work))
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "a"])
        #expect(order.error?.hasPrefix("The server did not accept this change:") == true)
        #expect(try store(root).load().pendingFavourites.count == 1)
        order.error = nil
        await order.synchronize()
        #expect(order.error == nil)

        await server.configure(Starred(song: [songs[1]]))
        await order.toggle(album: "a")
        #expect(await server.writes == [["b-1"], ["album:a"]])
        #expect(order.error == nil)
        #expect(try store(root).load().pendingFavourites.isEmpty)
        await order.refresh()
        #expect(order.isFavourite(b, of: work))
    }

    /// Offline, every tap keeps its result and shows one notice. Sends without a tap stay quiet (ADR 0052).
    @Test func offlineChangesStayAndShowOneNoticeForEachTap() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a", year: 2001), song("b", year: 1990)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let b = try #require(work.recordings.first { $0.album == "b" })
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.offline)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(b, of: work)
        #expect(order.isFavourite(b, of: work))
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "a"])
        #expect(order.error == RecordingOrder.offlineNotice)
        #expect(order.error == "No internet connection. This syncs when you are back online.")
        order.error = nil
        await order.toggle(album: "a")
        #expect(order.isFavourite(album: "a"))
        #expect(order.error == RecordingOrder.offlineNotice)
        order.error = nil
        await order.refresh()
        await order.synchronize()
        #expect(order.error == nil)
        #expect(order.isFavourite(b, of: work))
        #expect(order.isFavourite(album: "a"))
        #expect(await server.writes.isEmpty)

        await library.cacheWrite?.value
        let cached = Library(
            cacheURL: root.appending(path: "library.json"),
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        await cached.load(for: credentials)
        let relaunched = RecordingOrder(library: cached, store: store(root), server: server)
        #expect(relaunched.isFavourite(b, of: work))
        #expect(relaunched.isFavourite(album: "a"))
        #expect(relaunched.reference(of: work)?.id == b.id)
    }

    /// When the connection comes back, the queue goes to the server with the newest choice for each target.
    @Test func reconnectSendsTheNewestChoiceOfEachTargetOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let songs = [song("a", year: 2001), song("b", year: 1990)]
        let library = try await library(songs, root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let a = try #require(work.recordings.first { $0.album == "a" })
        let b = try #require(work.recordings.first { $0.album == "b" })
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.offline)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(a, of: work)
        await order.toggle(b, of: work)
        await order.toggle(a, of: work)
        await order.toggle(album: "b")
        await order.toggle(album: "b")
        await order.toggle(album: "b")
        #expect(try store(root).load().pendingFavourites.count == 3)

        await server.configure(Starred(song: [songs[1]], album: [Album(id: "b", name: "b")]))
        await order.synchronize()
        #expect(await server.writes == [["b-1"], ["-a-1"], ["album:b"]])
        #expect(try store(root).load().pendingFavourites.isEmpty)
        #expect(!order.isFavourite(a, of: work))
        #expect(order.isFavourite(b, of: work))
        #expect(order.isFavourite(album: "b"))

        // After the sync, the server is right again: a star removed elsewhere goes.
        await server.configure(Starred())
        await order.refresh()
        #expect(!order.isFavourite(b, of: work))
        #expect(!order.isFavourite(album: "b"))
        #expect(await server.writes.count == 3)
    }

    /// A star read while a change waits keeps the change, and the change goes first at the next refresh.
    @Test func aStarReadKeepsChangesThatWait() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let songs = [song("a", starred: true)]
        let library = try await library(songs, root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let a = try #require(work.recordings.first)
        let server = FavouriteFixture()
        await server.configure(Starred(song: songs), failure: FavouriteFixture.refusal, readsFail: false)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(a, of: work)
        #expect(!order.isFavourite(a, of: work))
        order.error = nil
        await order.refresh()
        #expect(!order.isFavourite(a, of: work))
        #expect(order.error == nil)
        await server.configure(Starred())
        await order.refresh()
        #expect(await server.writes == [["-a-1"]])
        #expect(!order.isFavourite(a, of: work))
    }

    @Test func deviceFilesWithoutAQueueStillLoad() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root)
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"favouriteWorks":["w"],"recordingOrder":{"w":["r"]}}"#.utf8).write(to: store.url)
        #expect(try store.load() == DeviceStore.Data(favouriteWorks: ["w"], recordingOrder: ["w": ["r"]]))
    }

    /// A work favourite or a new order made while the server call runs stays, on the device too.
    @Test func changesDuringAFavouriteCallAreKept() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library(
            [song("a", year: 2001, starred: true), song("b", year: 1990), song("c", year: 1980)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let a = try #require(work.recordings.first { $0.album == "a" })
        let b = try #require(work.recordings.first { $0.album == "b" })
        let c = try #require(work.recordings.first { $0.album == "c" })
        let server = FavouriteFixture()
        let order = RecordingOrder(library: library, store: store(root), server: server)

        let confirm = try #require(order.begin(b, of: work))
        order.toggle(work)
        order.moveFavourites(of: work, from: [1], to: 0)
        await confirm()
        #expect(order.isFavourite(work))
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "a", "c"])
        #expect(try store(root).load().favouriteWorks == [work.id])
        #expect(try store(root).load().recordingOrder[work.id] == [b.id, a.id])

        await server.configure(Starred(), failure: FavouriteFixture.refusal)
        let refused = try #require(order.begin(c, of: work))
        order.toggle(work)
        order.moveFavourites(of: work, from: [0], to: 2)
        await refused()
        #expect(!order.isFavourite(work))
        #expect(order.isFavourite(c, of: work))
        #expect(order.rows(of: work).map(\.recording.album) == ["a", "b", "c"])
        #expect(try store(root).load().favouriteWorks.isEmpty)
        #expect(try store(root).load().recordingOrder[work.id] == [a.id, b.id, c.id])
    }

    /// An album favourite is a star on the album, not on its tracks, and it raises its recordings (ADR 0013).
    @Test func anAlbumFavouriteStarsTheAlbumAtOnceAndRaisesItsRecordings() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a", year: 2001), song("b", year: 1990)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let server = FavouriteFixture()
        let order = RecordingOrder(library: library, store: store(root), server: server)
        let confirm = try #require(order.begin(album: "b"))
        #expect(order.isFavourite(album: "b"))
        #expect(order.rows(of: work).first?.reason == "Favourite album: b")
        await confirm()
        #expect(await server.writes == [["album:b"]])
        #expect(order.rows(of: work).allSatisfy { !$0.isFavourite })
        await order.toggle(album: "b")
        #expect(!order.isFavourite(album: "b"))
        #expect(await server.writes == [["album:b"], ["-album:b"]])
    }

    @Test func aFailedAlbumFavouriteStays() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.offline)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(album: "a")
        #expect(order.isFavourite(album: "a"))
        #expect(order.error == RecordingOrder.offlineNotice)
        order.error = nil
        await server.configure(Starred(), failure: FavouriteFixture.refusal)
        await order.toggle(album: "a")
        #expect(!order.isFavourite(album: "a"))
        #expect(order.error?.hasPrefix("The server did not accept this change:") == true)
        #expect(try store(root).load().pendingFavourites.map(\.isSet) == [false])
        #expect(!order.isSaving)
    }

    @Test func theFavouriteActionOfAFavouriteSaysUnfavourite() {
        #expect(FavouriteAction.title(isSet: true) == "Unfavourite")
        #expect(FavouriteAction.title(isSet: false) == "Favourite")
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

    @Test func corruptDeviceDataReportsAnErrorAndRemainsOnDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root)
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data("invalid".utf8)
        try bytes.write(to: store.url)
        let library = try await library([song("a")], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let recording = try #require(work.recordings.first)
        let server = FavouriteFixture()
        let order = RecordingOrder(library: library, store: store, server: server)
        #expect(order.loadError != nil)
        #expect(order.error == nil)
        await order.refresh()
        #expect(order.error == nil)
        order.toggle(work)
        #expect(!order.isFavourite(work))
        #expect(order.error == order.loadError)
        await order.toggle(recording, of: work)
        #expect(await server.writes.isEmpty)
        #expect(try Data(contentsOf: store.url) == bytes)
    }

    @Test(arguments: [FavouriteFixture.offline as any Error, FavouriteFixture.refusal])
    func refreshFailureDoesNotReportASaveFailure(_ failure: any Error) async {
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: failure)
        let order = RecordingOrder(library: Library(), server: server)
        await order.refresh()
        #expect(order.error == nil)
        #expect(order.refreshError == failure.localizedDescription)
        await server.configure(Starred())
        await order.refresh()
        #expect(order.refreshError == nil)
    }

    @Test func unchangedStarsDoNotRebuildOrWriteTheLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a", starred: true)], root: root)
        let change = IndexChange()
        withObservationTracking {
            _ = library.index
        } onChange: {
            MainActor.assumeIsolated { change.seen = true }
        }
        library.replaceStars(["a-1"])
        #expect(!change.seen)
        #expect(library.cacheWrite == nil)
    }

    @Test func starCacheWritesKeepTheirOrderAndClearRunsLast() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        library.setStarred(["a-1"], true)
        library.setStarred(["a-1"], false)
        library.setStarred(["a-1"], true)
        await library.cacheWrite?.value
        let cache = root.appending(path: "library.json")
        #expect(try LibraryCache.read(from: cache).songs.first?.starred != nil)
        library.setStarred(["a-1"], false)
        library.clear()
        await library.cacheWrite?.value
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func aRefusalSurvivesARelaunchAndGoesAtTheNextLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let songs = [song("a")]
        let library = try await library(songs, root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let recording = try #require(work.recordings.first)
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.refusal)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(recording, of: work)
        #expect(order.error != nil)
        #expect(order.isFavourite(recording, of: work))
        #expect(!order.isSaving)
        await server.configure(Starred(song: songs))
        let relaunched = RecordingOrder(library: library, store: store(root), server: server)
        await relaunched.refresh()
        #expect(relaunched.error == nil)
        #expect(await server.writes == [["a-1"]])
        #expect(relaunched.isFavourite(recording, of: work))
        #expect(try store(root).load().pendingFavourites.isEmpty)
    }
}
