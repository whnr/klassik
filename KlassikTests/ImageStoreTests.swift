import Foundation
import Testing
import UIKit

@testable import Klassik

@MainActor
struct ImageStoreTests {
    @MainActor final class Counter {
        var count = 0
        func add() { count += 1 }
    }

    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let credentials = ServerCredentials(
        url: URL(string: "https://music.example.org")!, username: "fixture", password: "fixture")

    func makeStore(limit: Int64? = nil, defaults: UserDefaults? = nil, folder: String = "images") async throws
        -> ImageStore
    {
        let suite = UserDefaults(suiteName: UUID().uuidString)
        let defaults = try #require(defaults ?? suite)
        if let limit { defaults.set(limit, forKey: "test.limit") }
        let store = ImageStore(folder: root.appending(path: folder), limitKey: "test.limit", defaults: defaults)
        await store.loaded()
        return store
    }

    func png() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        return try #require(image.pngData())
    }

    func song(_ id: String, album: String, cover: String?) -> Song {
        var song = Song(id: id, title: "Track \(id)")
        song.albumId = album
        song.coverArt = cover
        return song
    }

    func ok(_ request: URLRequest, _ data: Data) -> (Data, URLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    @Test func storedFilesCountAndStayAfterARelaunch() async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = try await makeStore(defaults: defaults)
        #expect(store.limit == nil)
        #expect(!store.isFull)
        await store.store(Data(count: 100), for: "a")
        await store.store(Data(count: 50), for: "b")
        #expect(store.bytes == 150)
        #expect(store.contains("a"))
        #expect(await store.data(for: "a") == Data(count: 100))
        #expect(await store.data(for: "missing") == nil)

        let again = try await makeStore(defaults: defaults)
        #expect(again.bytes == 150)
        #expect(again.contains("b"))
        again.clear()
        #expect(again.bytes == 0)
        #expect(!again.contains("a"))
        #expect(await again.data(for: "a") == nil)
    }

    @Test func aFullStoreDropsTheFileShownLongestAgo() async throws {
        let store = try await makeStore(limit: 250)
        await store.store(Data(count: 100), for: "old")
        await store.store(Data(count: 100), for: "shown")
        _ = await store.data(for: "old")
        await store.store(Data(count: 100), for: "new")
        #expect(store.contains("old"))
        #expect(!store.contains("shown"))
        #expect(store.contains("new"))
        #expect(store.bytes == 200)
        #expect(!store.isFull)
        store.limit = 100
        #expect(store.bytes == 100)
        #expect(store.isFull)
    }

    @Test func theLimitPersistsAndNoLimitIsTheDefault() async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = try await makeStore(defaults: defaults)
        store.limit = 3 * TrackStore.gigabyte
        #expect(try await makeStore(defaults: defaults).limit == 3 * TrackStore.gigabyte)
        store.limit = nil
        #expect(try await makeStore(defaults: defaults).limit == nil)
    }

    @Test func theStepperEndsInNoLimit() {
        #expect(LimitStepper.step(nil) == TrackStore.limitRange.upperBound + 1)
        #expect(LimitStepper.limit(LimitStepper.noLimit) == nil)
        #expect(LimitStepper.step(5 * TrackStore.gigabyte) == 5)
        #expect(LimitStepper.limit(5) == 5 * TrackStore.gigabyte)
        #expect(LimitStepper.step(TrackStore.gigabyte / 2) == 1)
    }

    @Test func theBarGivesEachStoreItsShare() {
        let part = StoragePart(id: "music", name: "Music", colour: .tint, bytes: 25)
        #expect(part.share(of: 100) == 0.25)
        #expect(part.share(of: 0) == 0)
    }

    @Test func aPictureLoadsOnceAndThenFromTheDevice() async throws {
        let store = try await makeStore()
        let data = try png()
        let requests = Counter()
        let fetch = PortraitLoader.stored({ _ in (data, 200) }, in: { store })
        let counting: MusicBrainz.Fetch = { request in
            await requests.add()
            return try await fetch(request)
        }
        let url = URL(string: "https://upload.wikimedia.org/a.png")!
        #expect(await PortraitLoader.load(url, fetch: counting) != nil)
        #expect(store.contains(url.absoluteString))
        let offline = PortraitLoader.stored({ _ in throw URLError(.notConnectedToInternet) }, in: { store })
        #expect(await PortraitLoader.load(url, fetch: offline) != nil)
        #expect(requests.count == 1)
        let failing = PortraitLoader.stored({ _ in (Data(), 404) }, in: { store })
        _ = try await failing(URLRequest(url: URL(string: "https://upload.wikimedia.org/b.png")!))
        #expect(!store.contains("https://upload.wikimedia.org/b.png"))
    }

    @Test func coverArtComesFromTheDeviceBeforeTheServer() async throws {
        let store = try await makeStore()
        let data = try png()
        let remote = URL(string: "https://music.example.org/cover")!
        var fetched = 0
        let first = await CoverArt.load(
            files: [], remote: remote, pixels: 10, kept: (store: store, key: "album"),
            fetch: { url in
                fetched += 1
                return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        let image = try #require(first)
        #expect(max(image.size.width, image.size.height) * image.scale == 10)
        #expect(store.contains("album"))
        let again = await CoverArt.load(
            files: [], remote: remote, pixels: 0, kept: (store: store, key: "album"),
            fetch: { _ in throw URLError(.notConnectedToInternet) })
        #expect(again?.size.width == 40)
        #expect(fetched == 1)
    }

    @Test func thePassKeepsTheArtOfEachAlbumOnce() async throws {
        let store = try await makeStore()
        let data = try png()
        let kept = CoverArt.storeKey(album: "kept", credentials: credentials)
        await store.store(data, for: kept)
        var requested: [String] = []
        let songs = [
            song("1", album: "a", cover: "al-a"), song("2", album: "a", cover: "mf-2"),
            song("3", album: "kept", cover: "al-kept"), song("4", album: "none", cover: nil),
            song("5", album: "b", cover: "al-b"),
        ]
        await CoverArt.keepAll(songs, credentials: credentials, store: store) { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            requested.append(query.first { $0.name == "id" }?.value ?? "")
            #expect(query.first { $0.name == "size" }?.value == String(CoverArt.storedPixels))
            #expect(!request.allowsConstrainedNetworkAccess)
            return ok(request, data)
        }
        #expect(requested == ["al-a", "al-b"])
        #expect(store.contains(CoverArt.storeKey(album: "a", credentials: credentials)))
        #expect(store.contains(CoverArt.storeKey(album: "b", credentials: credentials)))
    }

    @Test func thePassStopsWhenTheStoreIsFullOrTheNetworkFails() async throws {
        let data = try png()
        let songs = (1...3).map { song("\($0)", album: "album \($0)", cover: "al-\($0)") }
        let full = try await makeStore(limit: Int64(data.count))
        var requests = 0
        await CoverArt.keepAll(songs, credentials: credentials, store: full) { request in
            requests += 1
            return ok(request, data)
        }
        #expect(requests == 1)

        let open = try await makeStore(folder: "open")
        requests = 0
        await CoverArt.keepAll(songs, credentials: credentials, store: open) { _ in
            requests += 1
            throw URLError(.notConnectedToInternet)
        }
        #expect(requests == 1)
        #expect(open.bytes == 0)
    }

    @Test func aNewPasswordKeepsTheAlbumArt() {
        var changed = credentials
        changed.password = "replacement"
        #expect(
            CoverArt.storeKey(album: "a", credentials: credentials)
                == CoverArt.storeKey(album: "a", credentials: changed))
        changed.username = "someone else"
        #expect(
            CoverArt.storeKey(album: "a", credentials: credentials)
                != CoverArt.storeKey(album: "a", credentials: changed))
    }

    @Test func aLimitBetweenFilesKeepsTheFirstAlbumsOnEachPass() async throws {
        let data = try png()
        let songs = (1...4).map { song("\($0)", album: "album \($0)", cover: "al-\($0)") }
        let keys = songs.map { CoverArt.storeKey(album: $0.albumKey, credentials: credentials) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let limit = Int64(data.count) * 5 / 2
        var requests = 0
        let fetch = { (request: URLRequest) async throws -> (Data, URLResponse) in
            requests += 1
            return ok(request, data)
        }
        let first = try await makeStore(limit: limit, defaults: defaults)
        await CoverArt.keepAll(songs, credentials: credentials, store: first, fetch: fetch)
        #expect(requests == 2)
        #expect(first.contains(keys[0]))
        #expect(first.contains(keys[1]))
        #expect(!first.contains(keys[2]))
        #expect(first.bytes == 2 * Int64(data.count))

        requests = 0
        let next = try await makeStore(defaults: defaults)
        await CoverArt.keepAll(songs, credentials: credentials, store: next, fetch: fetch)
        #expect(requests == 0)
        #expect(next.contains(keys[0]))
        #expect(next.contains(keys[1]))
        #expect(next.bytes == 2 * Int64(data.count))
    }

    @Test func thePassStopsWhenAWriteFails() async throws {
        let data = try png()
        let songs = (1...3).map { song("\($0)", album: "album \($0)", cover: "al-\($0)") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A file in place of the folder makes each write fail, as a full disk does.
        try Data().write(to: root.appending(path: "images"))
        let store = try await makeStore()
        var requests = 0
        await CoverArt.keepAll(songs, credentials: credentials, store: store) { request in
            requests += 1
            return ok(request, data)
        }
        #expect(requests == 1)
        #expect(store.bytes == 0)
    }
}
