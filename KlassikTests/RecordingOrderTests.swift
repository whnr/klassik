import Foundation
import Observation
import Testing

@testable import Klassik

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private final class FavouriteLibraryProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let json = #"""
            {"subsonic-response":{"status":"ok","version":"1.16.1","searchResult3":{"song":[
            {"id":"a-1","title":"Movement 1","album":"a","albumId":"a","year":2020,"genre":"Classical","works":[{"name":"Work"}]},
            {"id":"b-1","title":"Movement 1","album":"b","albumId":"b","year":1990,"genre":"Classical","works":[{"name":"Work"}]},
            {"id":"c-1","title":"Movement 1","album":"c","albumId":"c","year":2000,"genre":"Classical","works":[{"name":"Work"}],"starred":"2026-11-16"}
            ]}}}
            """#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

#if !canImport(FoundationNetworking)
    extension FavouriteLibraryProtocol: @unchecked Sendable {}
#endif

@MainActor private final class IndexChange {
    var seen = false
}

/// A server that takes no call until the test opens it, as a slow or hung server does.
actor SilentServer: FavouriteServer {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var calls = 0

    private func hold() async {
        calls += 1
        if !isOpen { await withCheckedContinuation { waiting.append($0) } }
    }

    func open() {
        isOpen = true
        for call in waiting { call.resume() }
        waiting = []
    }

    func star(_ ids: [String]) async { await hold() }
    func unstar(_ ids: [String]) async { await hold() }
    func starAlbum(_ id: String) async { await hold() }
    func unstarAlbum(_ id: String) async { await hold() }
    func starArtist(_ id: String) async { await hold() }
    func unstarArtist(_ id: String) async { await hold() }
    func getStarred() async -> Starred {
        await hold()
        return Starred()
    }
}

actor FavouriteFixture: FavouriteServer {
    var stars = Starred()
    var writes: [[String]] = []
    var failure: (any Error)?
    var readsFail = true
    var failures: [String: any Error] = [:]
    /// Song stars that fail as if offline before the fixture answers, as a reconnect before the server answers.
    var silentStars = 0

    static let offline = URLError(.notConnectedToInternet)
    static let refusal = SubsonicError.server(code: 50, message: "The user is not authorised")

    func configure(_ stars: Starred, failure: (any Error)? = nil, readsFail: Bool = true) {
        self.stars = stars
        self.failure = failure
        self.readsFail = readsFail
    }

    func dropStars(_ count: Int) { silentStars = count }

    func star(_ ids: [String]) throws {
        if silentStars > 0 {
            silentStars -= 1
            throw Self.offline
        }
        if let id = ids.first, let failure = failures[id] { throw failure }
        if let failure { throw failure }
        writes.append(ids)
    }

    func fail(_ failures: [String: any Error]) { self.failures = failures }

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

    func starArtist(_ id: String) throws {
        if let failure { throw failure }
        writes.append(["artist:" + id])
    }

    func unstarArtist(_ id: String) throws {
        if let failure { throw failure }
        writes.append(["-artist:" + id])
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

    @Test(arguments: [false, true])
    func queuedChoicesSurviveFullReloadAndFailedStarReads(loadBeforeOrder: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let songs = [song("a", year: 2020), song("b", year: 1990), song("c", year: 2000, starred: true)]
        let library = try await library(songs, root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let b = try #require(work.recordings.first { $0.album == "b" })
        let c = try #require(work.recordings.first { $0.album == "c" })
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.refusal)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(b, of: work)
        await order.toggle(c, of: work)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FavouriteLibraryProtocol.self]
        let client = SubsonicClient(credentials: credentials, session: URLSession(configuration: configuration))
        await library.sync(with: client)
        #expect(library.syncError == nil)
        await order.refresh()
        #expect(order.refreshError != nil)
        #expect(order.isFavourite(b, of: work))
        #expect(!order.isFavourite(c, of: work))
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "a", "c"])
        #expect(order.favouriteRecordings.map(\.recording.album) == ["b"])
        #expect(try store(root).load().recordingOrder[work.id] == [b.id])
        await library.cacheWrite?.value
        let cached = try LibraryCache.read(from: root.appending(path: "library.json"))
        #expect(cached.songs.first { $0.id == "b-1" }?.starred != nil)
        #expect(cached.songs.first { $0.id == "c-1" }?.starred == nil)
        try LibraryCache(server: credentials.url, username: credentials.username, syncedAt: .now, songs: songs)
            .write(to: root.appending(path: "library.json"))
        let reloaded = Library(cacheURL: root.appending(path: "library.json"))
        if loadBeforeOrder { await reloaded.load(for: credentials) }
        let relaunched = RecordingOrder(library: reloaded, store: store(root), server: server)
        if !loadBeforeOrder { await reloaded.load(for: credentials) }
        #expect(relaunched.isFavourite(b, of: work))
        #expect(!relaunched.isFavourite(c, of: work))
        #expect(relaunched.favouriteRecordings.map(\.recording.album) == ["b"])
        #expect(relaunched.rows(of: work).map(\.recording.album) == ["b", "a", "c"])
        await reloaded.cacheWrite?.value
    }

    /// A failed send shows no notice. The status says why the changes wait; no answer wins over a refusal.
    @Test(arguments: [false, true])
    func failedSendsSetOneQuietStatusAndNoNotice(stopsBeforeTap: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a"), song("b"), song("c")], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let server = FavouriteFixture()
        await server.fail([
            "a-1": FavouriteFixture.refusal, "b-1": FavouriteFixture.offline,
            "c-1": FavouriteFixture.refusal,
        ])
        let order = RecordingOrder(library: library, store: store(root), server: server)
        let a = try #require(work.recordings.first { $0.album == "a" })
        let b = try #require(work.recordings.first { $0.album == "b" })
        let c = try #require(work.recordings.first { $0.album == "c" })
        await order.toggle(a, of: work)
        #expect(order.serverTrouble == .refused)
        if stopsBeforeTap { _ = order.begin(b, of: work) }
        await order.toggle(stopsBeforeTap ? c : b, of: work)
        #expect(order.serverTrouble == .unreachable)
        #expect(order.error == nil)
        #expect(try store(root).load().pendingFavourites.count == (stopsBeforeTap ? 3 : 2))
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
        order.move(of: work, from: [1], to: 0)
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
        order.move(of: work, from: [1], to: 0)
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
        #expect(order.serverTrouble == .refused)
        #expect(order.error == nil)
        #expect(try store(root).load().pendingFavourites.count == 1)
        await order.synchronize()
        #expect(order.error == nil)

        await server.configure(Starred(song: [songs[1]]))
        await order.toggle(album: "a")
        #expect(await server.writes == [["b-1"], ["album:a"]])
        #expect(order.serverTrouble == nil)
        #expect(order.error == nil)
        #expect(try store(root).load().pendingFavourites.isEmpty)
        await order.refresh()
        #expect(order.isFavourite(b, of: work))
    }

    /// Offline, every tap keeps its result and shows no notice. One status says the server is not reachable, and
    /// the next successful send clears it.
    @Test func offlineChangesStayWithOneQuietStatusUntilTheServerAnswers() async throws {
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
        #expect(order.error == nil)
        #expect(order.serverTrouble == .unreachable)
        #expect(order.serverTrouble?.status == "Server not reachable. Changes wait on this iPhone.")
        await order.toggle(album: "a")
        #expect(order.isFavourite(album: "a"))
        await order.refresh()
        await order.synchronize()
        #expect(order.error == nil)
        #expect(order.serverTrouble == .unreachable)
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
        #expect(order.serverTrouble == .unreachable)

        await server.configure(Starred(song: [songs[1]], album: [Album(id: "b", name: "b")]))
        await order.synchronize()
        #expect(order.serverTrouble == nil)
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
        order.move(of: work, from: [1], to: 0)
        await confirm()
        #expect(order.isFavourite(work))
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "a", "c"])
        #expect(try store(root).load().favouriteWorks == [work.id])
        #expect(try store(root).load().recordingOrder[work.id] == [b.id, a.id, c.id])

        await server.configure(Starred(), failure: FavouriteFixture.refusal)
        let refused = try #require(order.begin(c, of: work))
        order.toggle(work)
        order.move(of: work, from: [0], to: 2)
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
        #expect(order.serverTrouble == .unreachable)
        await server.configure(Starred(), failure: FavouriteFixture.refusal)
        await order.toggle(album: "a")
        #expect(!order.isFavourite(album: "a"))
        #expect(order.serverTrouble == .refused)
        #expect(order.error == nil)
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
        order.move(of: work, from: [1], to: 0)
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

    @Test func aStarredArtistMarksAPersonAsAFavourite() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        let server = FavouriteFixture()
        await server.configure(Starred(artist: [.init(id: "person-a", name: "Person a")]))
        let order = RecordingOrder(library: library, server: server)
        #expect(!order.isFavourite(person: "Person a"))
        await order.refresh()
        #expect(order.isFavourite(person: "Person a"))
        #expect(!order.isFavourite(person: "Person b"))
    }

    @Test func artistChoicesStayOfflineThenRefreshFromTheServer() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var track = song("a")
        let composer = Song.Artist(id: "composer", name: "Composer")
        track.contributors?.append(.init(role: "composer", artist: composer))
        let library = try await library([track, song("b", year: 2020)], root: root)
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.offline)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        let sendComposer = try #require(order.begin(person: "Composer"))
        #expect(order.isFavourite(person: "Composer"))
        #expect(order.favouriteComposers.map(\.name) == ["Composer"])
        await sendComposer()
        let sendPerformer = try #require(order.begin(person: "Person a"))
        #expect(order.isFavourite(person: "Person a"))
        await sendPerformer()
        #expect(order.error == nil)
        #expect(order.pendingChanges.count == 2)
        #expect(order.title(of: order.pendingChanges[0]) == "Composer")
        let restored = RecordingOrder(library: library, store: store(root), server: server)
        #expect(restored.isFavourite(person: "Composer"))
        #expect(restored.isFavourite(person: "Person a"))
        #expect(restored.favouritePerformers.map(\.name) == ["Person a"])
        await server.configure(Starred(artist: [composer, .init(id: "person-a", name: "Person a")]))
        await restored.refresh()
        #expect(await server.writes == [["artist:composer"], ["artist:person-a"]])
        #expect(restored.pendingChanges.isEmpty)
        #expect(library.songs.allSatisfy { $0.starred == nil })
        await server.configure(Starred())
        await restored.refresh()
        #expect(!restored.isFavourite(person: "Composer"))
        #expect(!restored.isFavourite(person: "Person a"))
        #expect(order.begin(person: "No server ID") == nil)
    }

    @Test func mixedOfflineTargetsKeepOnlyTheNewestChoiceAndTheirOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.offline, readsFail: false)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.begin(person: "Person a")?()
        await order.toggle(album: "a")
        let work = try #require(library.index.composers.first?.works.first)
        let recording = try #require(work.recordings.first)
        await order.toggle(recording, of: work)
        await order.begin(person: "Person a")?()
        await order.refresh()
        #expect(order.pendingChanges.count == 3)
        #expect(order.pendingChanges[0].album == "a")
        #expect(order.pendingChanges[1].songs == ["a-1"])
        #expect(order.pendingChanges[2].artist?.id == "person-a")
        #expect(order.pendingChanges[2].isSet == false)
        #expect(order.isFavourite(album: "a"))
        #expect(!order.isFavourite(person: "Person a"))
        #expect(order.favouriteAlbums.map(\.title) == ["a"])
        #expect(order.favouriteCount == 2)
        await server.configure(Starred())
        await order.synchronize()
        #expect(await server.writes == [["album:a"], ["a-1"], ["-artist:person-a"]])
        #expect(order.pendingChanges.isEmpty)
    }

    @Test func newestIsReferenceWithoutFavouritesAndInvalidMovesCannotChangeIt() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("old", year: 1900), song("new", year: 2020)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let order = RecordingOrder(library: library, store: store(root))
        #expect(order.reference(of: work)?.album == "new")
        order.move(of: work, from: [2], to: 0)
        order.move(of: work, from: [0], to: 3)
        #expect(order.reference(of: work)?.album == "new")
        #expect(try store(root).load().recordingOrder.isEmpty)
    }

    /// A drop puts the dragged row where the target row stands, up or down, favourite or not, and keeps the order on
    /// the device.
    @Test func dropOntoARowMovesTheRowAndKeepsItOnTheDevice() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library(
            [
                song("a", year: 2003, starred: true), song("b", year: 2002, starred: true),
                song("c", year: 2001, starred: true), song("d", year: 1990),
            ], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let order = RecordingOrder(library: library, store: store(root))
        func ids(_ album: String) throws -> String { try #require(work.recordings.first { $0.album == album }).id }
        func albums() -> [String] { order.rows(of: work).map(\.recording.album) }
        let start = albums()

        order.move(try ids(start[0]), of: work, onto: try ids(start[2]))
        #expect(albums() == [start[1], start[2], start[0], start[3]])
        order.move(try ids(start[0]), of: work, onto: try ids(start[1]))
        #expect(albums() == [start[0], start[1], start[2], start[3]])
        // A drop on a row that is no favourite takes that row's place.
        order.move(try ids(start[0]), of: work, onto: try ids(start[3]))
        #expect(albums() == [start[1], start[2], start[3], start[0]])
        // A drop on itself changes nothing. A row that is no favourite can rise above the favourites.
        order.move(try ids(start[0]), of: work, onto: try ids(start[0]))
        #expect(albums() == [start[1], start[2], start[3], start[0]])
        order.move(try ids(start[3]), of: work, onto: try ids(start[1]))
        #expect(albums() == [start[3], start[1], start[2], start[0]])
        let kept = RecordingOrder(library: library, store: store(root))
        #expect(kept.rows(of: work).map(\.recording.album) == albums())
    }

    /// No row needs a favourite mark to move. The whole list is stored, and a new launch reads it.
    @Test func aRowThatIsNoFavouriteMovesAndStaysAfterARelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library(
            [song("a", year: 2003), song("b", year: 2002), song("c", year: 2001)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let order = RecordingOrder(library: library, store: store(root))
        #expect(order.rows(of: work).map(\.recording.album) == ["a", "b", "c"])

        order.move(of: work, from: [2], to: 0)

        #expect(order.rows(of: work).map(\.recording.album) == ["c", "a", "b"])
        #expect(order.reference(of: work)?.album == "c")
        let ids = order.rows(of: work).map(\.id)
        #expect(try store(root).load().recordingOrder[work.id] == ids)
        let relaunched = RecordingOrder(library: library, store: store(root))
        #expect(relaunched.rows(of: work).map(\.recording.album) == ["c", "a", "b"])
    }

    /// The server tells the stars, never the order of rows that the listener placed.
    @Test func aStarReadKeepsTheOrderOfPlacedRows() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let b = song("b", year: 2002, starred: true)
        let library = try await library([song("a", year: 2003), b, song("c", year: 2001)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let server = FavouriteFixture()
        await server.configure(Starred(song: [b]))
        let order = RecordingOrder(library: library, store: store(root), server: server)
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "a", "c"])
        order.move(of: work, from: [2], to: 0)
        #expect(order.rows(of: work).map(\.recording.album) == ["c", "b", "a"])

        await order.refresh()

        #expect(order.rows(of: work).map(\.recording.album) == ["c", "b", "a"])
        #expect(try store(root).load().recordingOrder[work.id]?.count == 3)
    }

    /// A new favourite joins the favourites that the listener placed. A row that loses its star stays in place.
    @Test func aFavouriteJoinsAPlacedOrderAndKeepsItsPlaceWhenUnstarred() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library(
            [song("a", year: 2003), song("b", year: 2002), song("c", year: 2001)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let b = try #require(work.recordings.first { $0.album == "b" })
        let order = RecordingOrder(library: library, store: store(root), server: FavouriteFixture())
        order.move(of: work, from: [2], to: 0)
        #expect(order.rows(of: work).map(\.recording.album) == ["c", "a", "b"])

        await order.toggle(b, of: work)
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "c", "a"])

        await order.toggle(b, of: work)
        #expect(!order.isFavourite(b, of: work))
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "c", "a"])
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

    /// Only a read of the stars shows a change that another device made while this one was offline.
    @Test func reconnectReadsTheStarsAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        let server = SilentServer()
        await server.open()
        let order = RecordingOrder(library: library, store: store(root), server: server)
        var listened = false
        await AppModel.synchronizeAfterReconnect(order: order, listening: { listened = true })
        #expect(await server.calls == 1)
        #expect(listened)
    }

    /// The path can report a connection before the server answers, so the first send after a reconnect can fail.
    /// The app tries again, and the waiting choice clears with no step of the listener.
    @Test func reconnectTriesAgainUntilTheServerAnswers() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let a = try #require(work.recordings.first)
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.offline)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(a, of: work)
        #expect(order.pendingChanges.count == 1)

        await server.configure(Starred(song: [song("a")]))
        await server.dropStars(2)
        await AppModel.synchronizeAfterReconnect(
            order: order, listening: {}, retries: [.milliseconds(10), .milliseconds(10), .milliseconds(10)])
        #expect(order.pendingChanges.isEmpty)
        #expect(order.serverTrouble == nil)
        #expect(await server.writes == [["a-1"]])
        #expect(order.isFavourite(a, of: work))
    }

    /// Flo's check: offline, one favourite changes twice, and Diagnostics lists only the newest choice. A pull to
    /// refresh in Diagnostics checks the server and also sends that choice.
    @Test func diagnosticsRefreshChecksTheServerAndSendsTheNewestChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let a = try #require(work.recordings.first)
        let server = FavouriteFixture()
        await server.configure(Starred(), failure: FavouriteFixture.offline)
        let order = RecordingOrder(library: library, store: store(root), server: server)
        await order.toggle(a, of: work)
        await order.toggle(a, of: work)
        #expect(order.pendingChanges.count == 1)
        #expect(order.pendingChanges.first?.isSet == false)

        await server.configure(Starred())
        var checked = false
        var listened = false
        let ended = await AppModel.refreshServer(
            check: { checked = true }, order: order, listening: { listened = true })
        #expect(ended)
        #expect(checked)
        #expect(listened)
        #expect(order.pendingChanges.isEmpty)
        #expect(order.serverTrouble == nil)
        #expect(await server.writes == [["-a-1"]])
        #expect(!order.isFavourite(a, of: work))
    }

    /// A server that does not answer never keeps the pull spinning. The calls go on and finish later.
    @Test(.timeLimit(.minutes(1)))
    func diagnosticsRefreshEndsWhenTheServerIsSilent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a")], root: root)
        let server = SilentServer()
        let order = RecordingOrder(library: library, store: store(root), server: server)
        _ = order.begin(album: "a")
        #expect(order.pendingChanges.count == 1)

        let started = ContinuousClock.now
        let ended = await AppModel.refreshServer(
            check: { _ = await server.getStarred() }, order: order, listening: {}, limit: .milliseconds(200))
        #expect(!ended)
        #expect(ContinuousClock.now - started < .seconds(10))
        #expect(order.pendingChanges.count == 1)

        await server.open()
        await order.synchronize()
        #expect(order.pendingChanges.isEmpty)
    }

    /// Each favourite control changes its state in the tap itself, while the server has not answered. A star does
    /// not rebuild the index, because the rebuild holds the main actor under the tap (ADR 0052).
    @Test func aTapChangesStateWithNoServerAnswerAndKeepsTheIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await library([song("a", year: 2001), song("b", year: 1990)], root: root)
        let work = try #require(library.index.composers.first?.works.first)
        let b = try #require(work.recordings.first { $0.album == "b" })
        let server = SilentServer()
        let order = RecordingOrder(library: library, store: store(root), server: server)
        let change = IndexChange()
        withObservationTracking {
            _ = library.index
        } onChange: {
            MainActor.assumeIsolated { change.seen = true }
        }

        order.toggleAtOnce(b, of: work)
        #expect(order.isFavourite(b, of: work))
        #expect(order.rows(of: work).map(\.recording.album) == ["b", "a"])
        #expect(order.favouriteRecordings.map(\.recording.album) == ["b"])
        order.toggleAtOnce(album: "a")
        #expect(order.isFavourite(album: "a"))
        order.toggleAtOnce(work)
        #expect(order.isFavourite(work))
        #expect(!change.seen)
        #expect(order.serverTrouble == nil)
        #expect(order.error == nil)

        await server.open()
        await order.synchronize()
        #expect(try store(root).load().pendingFavourites.isEmpty)
        #expect(order.isFavourite(b, of: work))
        #expect(order.isFavourite(album: "a"))
        await library.cacheWrite?.value
        let cached = try LibraryCache.read(from: root.appending(path: "library.json"))
        #expect(cached.songs.first { $0.id == "b-1" }?.starred != nil)
    }

    @Test func troublesJoinIntoOneStatus() {
        let timeout: [any Error] = [URLError(.timedOut)]
        #expect(ServerTrouble(timeout) == .unreachable)
        #expect(ServerTrouble([FavouriteFixture.refusal, URLError(.cannotConnectToHost)]) == .unreachable)
        let refusal: [any Error] = [FavouriteFixture.refusal]
        #expect(ServerTrouble(refusal) == .refused)
        #expect(ServerTrouble([any Error]()) == nil)
        #expect(ServerTrouble.worst([nil, .refused]) == .refused)
        #expect(ServerTrouble.worst([.refused, .unreachable]) == .unreachable)
        #expect(ServerTrouble.worst([nil, nil]) == nil)
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
        #expect(order.serverTrouble == .refused)
        #expect(order.error == nil)
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
