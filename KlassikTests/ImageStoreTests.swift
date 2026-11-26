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

    func makeStore(folder: String = "images") async throws -> ImageStore {
        let store = ImageStore(folder: root.appending(path: folder))
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

    @Test func identicalBytesShareOneContentFile() async throws {
        let store = try await makeStore()
        let data = try png()
        let name = try #require(await store.store(content: data))
        #expect(name == ImageStore.contentName(data))
        #expect(await store.store(content: data) == name)
        #expect(store.bytes == Int64(data.count))
        #expect(await store.data(named: name) == data)
        store.remove(named: name)
        #expect(!store.contains(named: name))
        #expect(store.bytes == 0)
        #expect(await store.data(named: name) == nil)
    }

    @Test func storedFilesCountAndStayAfterARelaunch() async throws {
        let store = try await makeStore()
        await store.store(Data(count: 100), for: "a")
        await store.store(Data(count: 50), for: "b")
        #expect(store.bytes == 150)
        #expect(store.contains("a"))
        #expect(await store.data(for: "a") == Data(count: 100))
        #expect(await store.data(for: "missing") == nil)

        let again = try await makeStore()
        #expect(again.bytes == 150)
        #expect(again.contains("b"))
        again.clear()
        #expect(again.bytes == 0)
        #expect(!again.contains("a"))
        #expect(await again.data(for: "a") == nil)
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

    /// Answers picture requests with one answer and records each request.
    @MainActor final class PictureServer {
        var answer: (Data, Int)
        private(set) var requests: [URLRequest] = []
        init(_ answer: (Data, Int)) { self.answer = answer }
        func fetch(_ request: URLRequest) -> (Data, Int) {
            requests.append(request)
            return answer
        }
    }

    func png(_ colour: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: format).image { context in
            colour.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        return try #require(image.pngData())
    }

    @Test func aLookupKeepsThePictureAndALaterLookupReplacesIt() async throws {
        let store = try await makeStore()
        let screen = PortraitSize.Screen(hero: CGSize(width: 400, height: 470), scale: 3)
        let first = PersonPortrait(url: URL(string: "https://upload.wikimedia.org/a.png")!)
        let second = PersonPortrait(url: URL(string: "https://upload.wikimedia.org/b.png")!)
        let red = try png(.red)
        let blue = try png(.blue)
        let server = PictureServer((red, 200))
        let fetch: MusicBrainz.Fetch = { await server.fetch($0) }
        #expect(await PortraitLoader.keep(first, replacing: nil, screen: screen, store: store, fetch: fetch))
        #expect(await store.data(for: first.url.absoluteString) == red)
        #expect(PortraitLoader.ready(first, store: store) != nil)
        #expect(server.requests.allSatisfy { $0.allowsConstrainedNetworkAccess })

        let identity = PersonHero.PortraitTask(portrait: first, screen: screen, store: store)
        let read = PortraitLoader.stored({ _ in throw URLError(.notConnectedToInternet) }, in: { store })
        let shown = try #require(await PortraitLoader.load(first, screen: screen, fetch: read, store: store))

        let other = PersonPortrait(url: URL(string: "https://upload.wikimedia.org/c.png")!)
        #expect(await PortraitLoader.keep(other, replacing: nil, screen: screen, store: store, fetch: fetch))
        #expect(PersonHero.PortraitTask(portrait: first, screen: screen, store: store) == identity)

        server.answer = (blue, 200)
        #expect(await PortraitLoader.keep(first, replacing: first, screen: screen, store: store, fetch: fetch))
        #expect(await store.data(for: first.url.absoluteString) == blue)
        let replacement = PersonHero.PortraitTask(portrait: first, screen: screen, store: store)
        #expect(identity != replacement)
        let refreshed = try #require(await PortraitLoader.load(first, screen: screen, fetch: read, store: store))
        #expect(shown.image.pngData() != refreshed.image.pngData())
        server.answer = (Data(), 500)
        #expect(!(await PortraitLoader.keep(first, replacing: first, screen: screen, store: store, fetch: fetch)))
        #expect(await store.data(for: first.url.absoluteString) == blue)

        server.answer = (red, 200)
        #expect(await PortraitLoader.keep(second, replacing: first, screen: screen, store: store, fetch: fetch))
        #expect(!store.contains(first.url.absoluteString))
        #expect(PortraitLoader.ready(first, store: store) == nil)
        #expect(store.contains(second.url.absoluteString))
    }

    @Test func aPageShowsThePictureThatTheLookupKeptWithoutTheNetwork() async throws {
        let store = try await makeStore()
        let commons = "https://upload.wikimedia.org/wikipedia/commons"
        let portrait = PersonPortrait(
            url: URL(string: "\(commons)/thumb/a/ab/B.jpg/1280px-B.jpg")!,
            original: URL(string: "\(commons)/a/ab/B.jpg")!, width: 6000, height: 6000)
        let device = PortraitSize.Screen(hero: CGSize(width: 440, height: 470), scale: 3)
        let page = PortraitSize.Screen(hero: CGSize(width: 200, height: 236), scale: 2)
        let wanted = PortraitSize.candidates(portrait, screen: page)
        #expect(PortraitSize.candidates(portrait, screen: device).first != wanted.first)
        let server = PictureServer((try png(.red), 200))
        #expect(
            await PortraitLoader.keep(
                portrait, replacing: nil, screen: device, store: store, fetch: { await server.fetch($0) }))
        let offline = PortraitLoader.stored({ _ in throw URLError(.notConnectedToInternet) }, in: { store })
        #expect(await PortraitLoader.load(portrait, screen: page, fetch: offline, store: store, kept: device) != nil)
        store.clear()
        #expect(PortraitLoader.ready(portrait, store: store) == nil)
    }

    @Test func storedPixelsPrepareWithoutANetworkBeforeThePageOpens() async throws {
        let store = try await makeStore()
        let portrait = PersonPortrait(url: URL(string: "https://upload.wikimedia.org/local.png")!)
        await store.store(try png(.red), for: portrait.url.absoluteString)
        #expect(PortraitLoader.ready(portrait, store: store) == nil)
        let local = PortraitLoader.stored({ _ in throw URLError(.notConnectedToInternet) }, in: { store })
        let screen = PortraitSize.Screen(hero: CGSize(width: 400, height: 470), scale: 3)
        #expect(await PortraitLoader.load(portrait, screen: screen, fetch: local, store: store) != nil)
        #expect(PortraitLoader.ready(portrait, store: store) != nil)
    }

    @Test func aKeptFileCountsWithoutDecodingOrANetwork() async throws {
        let store = try await makeStore()
        let portrait = PersonPortrait(url: URL(string: "https://upload.wikimedia.org/corrupt.png")!)
        #expect(!PortraitLoader.isKept(portrait, store: store))
        await store.store(Data("not an image".utf8), for: portrait.url.absoluteString)
        #expect(PortraitLoader.isKept(portrait, store: store))
        #expect(PortraitLoader.ready(portrait, store: store) == nil)
    }

    @Test func aCorruptStoredFileNeverPreparesPixels() async throws {
        let store = try await makeStore()
        let portrait = PersonPortrait(url: URL(string: "https://upload.wikimedia.org/corrupt.png")!)
        await store.store(Data("not an image".utf8), for: portrait.url.absoluteString)
        let local = PortraitLoader.stored({ _ in throw URLError(.notConnectedToInternet) }, in: { store })
        let screen = PortraitSize.Screen(hero: CGSize(width: 400, height: 470), scale: 3)
        #expect(await PortraitLoader.load(portrait, screen: screen, fetch: local, store: store) == nil)
        #expect(PortraitLoader.ready(portrait, store: store) == nil)
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
}
