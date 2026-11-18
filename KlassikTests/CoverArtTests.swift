import AVFoundation
import Testing
import UIKit

@testable import Klassik

/// A server that answers `getCoverArt` from a table of cover IDs.
@MainActor final class CoverServer {
    var covers: [String: Data] = [:]
    var isDown = false
    private(set) var requests: [URLRequest] = []

    var ids: [String] { requests.map(Self.id) }

    static func id(_ request: URLRequest) -> String {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
        return items?.first { $0.name == "id" }?.value ?? ""
    }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if isDown { throw URLError(.notConnectedToInternet) }
        let data = covers[Self.id(request)]
        let url = try #require(request.url)
        let status = data == nil ? 404 : 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        return (data ?? Data(), try #require(response))
    }

    func reset() { requests = [] }
}

@MainActor
struct CoverArtTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let credentials = ServerCredentials(
        url: URL(string: "https://music.example.org")!, username: "fixture", password: "fixture")
    let server = CoverServer()

    static func picture(_ colour: UIColor = .red, width: Int = 8, height: Int = 8) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            colour.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func png(_ colour: UIColor = .red) throws -> Data { try #require(picture(colour).pngData()) }

    static func song(_ id: String, album: String, disc: Int? = nil, track: Int? = nil, cover: String?) -> Song {
        var song = Song(id: id, title: "Track \(id)")
        song.albumId = album
        song.discNumber = disc
        song.track = track
        song.coverArt = cover
        return song
    }

    func makeStore(limit: Int64? = nil, folder: String = "art") throws -> ImageStore {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        if let limit { defaults.set(limit, forKey: "test.limit") }
        return ImageStore(folder: root.appending(path: folder), limitKey: "test.limit", defaults: defaults)
    }

    func makeCovers(_ store: ImageStore, songs: [Song], classical: [Song]? = nil, links: String = "links")
        -> AlbumCovers
    {
        let server = server
        let covers = AlbumCovers(store: store, folder: root.appending(path: links)) { try await server.fetch($0) }
        covers.attach(credentials)
        covers.plan(classical: classical ?? songs, library: songs)
        return covers
    }

    // MARK: Keys

    @Test func eachDiscHasAKeyAndADiscWithoutACoverTakesTheAlbumCover() {
        let songs = [
            Self.song("late", album: "a", disc: 1, track: 2, cover: "a-late"),
            Self.song("first", album: "a", disc: 1, track: 1, cover: "a-first"),
            Self.song("bare", album: "a", disc: 2, track: 1, cover: nil),
            Self.song("own", album: "a", disc: 3, track: 1, cover: "a-3"),
            Self.song("unnumbered", album: "a", cover: "a-unknown"),
            Self.song("none", album: "b", disc: 1, cover: nil),
        ]
        #expect(
            CoverPlan.jobs(songs) == [
                CoverJob(key: CoverPlan.key(album: "a", disc: 1), album: "a", source: "a-first"),
                CoverJob(key: CoverPlan.key(album: "a", disc: 2), album: "a", source: "a-first"),
                CoverJob(key: CoverPlan.key(album: "a", disc: 3), album: "a", source: "a-3"),
                CoverJob(key: CoverPlan.key(album: "a", disc: nil), album: "a", source: "a-unknown"),
            ])
        #expect(CoverPlan.key(album: "a", disc: nil) != CoverPlan.key(album: "a", disc: 1))
    }

    // MARK: Queue

    @Test func pagesAndPlaybackGoInFrontOfThePass() {
        var queue = CoverQueue()
        queue.append(["a", "b", "c", "d"])
        queue.front(["c"], reason: .page)
        queue.front(["d", "b", "d"], reason: .playback)
        queue.append(["a", "e"])
        #expect(queue.keys == ["d", "b", "c", "a", "e"])
        queue.dropPass()
        #expect(queue.keys == ["d", "b", "c"])
        queue.front(["b"], reason: .page)
        var popped: [String] = []
        var reasons: [CoverQueue.Reason] = []
        while let next = queue.pop() {
            popped.append(next.key)
            reasons.append(next.reason)
        }
        #expect(popped == ["b", "d", "c"])
        #expect(reasons == [.playback, .playback, .page])
    }

    @Test func aPageRequestAndAPersonPageJumpTheQueue() async throws {
        let songs = (1...4).map { Self.song("\($0)", album: "album \($0)", cover: "al-\($0)") }
        for index in 1...4 { server.covers["al-\(index)"] = try Self.png() }
        let covers = makeCovers(try makeStore(), songs: songs)
        covers.keepAll()
        covers.prefer([songs[2], songs[1]])
        covers.request(songs[3])
        await covers.idle()
        #expect(server.ids == ["al-4", "al-3", "al-2", "al-1"])
    }

    // MARK: Fetch ahead

    @Test func discsWithOneCoverKeepOneFile() async throws {
        let data = try Self.png()
        let shared = (1...20).map { (disc: Int) in
            Self.song("s\(disc)", album: "box", disc: disc, track: 1, cover: "al-box")
        }
        let own = (1...20).map { (disc: Int) in
            Self.song("o\(disc)", album: "set", disc: disc, track: 1, cover: "mf-o\(disc)")
        }
        server.covers["al-box"] = data
        for index in 1...20 { server.covers["mf-o\(index)"] = data }
        let store = try makeStore()
        let covers = makeCovers(store, songs: shared + own)
        covers.keepAll()
        await covers.idle()
        // One request for the shared ID and one for each own ID, but one file for the same bytes.
        #expect(server.ids.filter { $0 == "al-box" }.count == 1)
        #expect(server.ids.count == 21)
        #expect(store.bytes == Int64(data.count))
        let hashes = Set((shared + own).flatMap { covers.candidates(for: $0) })
        #expect(hashes == [ImageStore.contentName(data)])
    }

    @Test func anOrdinarySyncFetchesOnlyMissingAndChangedCovers() async throws {
        var songs = [Self.song("1", album: "a", cover: "al-a"), Self.song("2", album: "b", cover: "al-b")]
        let red = try Self.png(.red)
        let blue = try Self.png(.blue)
        let green = try Self.png(.green)
        server.covers = ["al-a": red, "al-b": blue, "al-b2": green]
        let store = try makeStore()
        let first = makeCovers(store, songs: songs)
        first.keepAll()
        await first.idle()
        #expect(server.ids == ["al-a", "al-b"])

        server.reset()
        let relaunch = makeCovers(store, songs: songs)
        #expect(relaunch.links == first.links)
        relaunch.keepAll()
        await relaunch.idle()
        #expect(server.ids.isEmpty)

        songs[1].coverArt = "al-b2"
        relaunch.plan(classical: songs, library: songs)
        relaunch.keepAll()
        await relaunch.idle()
        #expect(server.ids == ["al-b2"])
        #expect(relaunch.candidates(for: songs[1]) == [ImageStore.contentName(green)])
        // No link needs the blue file any more.
        #expect(!store.contains(named: ImageStore.contentName(blue)))

        server.reset()
        store.remove(named: ImageStore.contentName(red))
        relaunch.keepAll()
        await relaunch.idle()
        #expect(server.ids == ["al-a"])
    }

    @Test func aFullSyncReplacesEachCoverAndKeepsItWhenTheRefreshFails() async throws {
        let songs = [Self.song("1", album: "a", cover: "al-a"), Self.song("2", album: "b", cover: "al-b")]
        let red = try Self.png(.red)
        let blue = try Self.png(.blue)
        server.covers = ["al-a": red, "al-b": red]
        let store = try makeStore()
        let covers = makeCovers(store, songs: songs)
        covers.keepAll()
        await covers.idle()
        let before = covers.links

        server.reset()
        server.isDown = true
        covers.keepAll(full: true)
        await covers.idle()
        #expect(server.ids.count == 1)
        #expect(covers.links.discs == before.discs)
        #expect(covers.links.refresh.count == 2)
        #expect(store.contains(named: ImageStore.contentName(red)))

        server.reset()
        server.isDown = false
        server.covers["al-a"] = blue
        covers.keepAll()
        await covers.idle()
        #expect(server.ids == ["al-a", "al-b"])
        #expect(covers.links.refresh.isEmpty)
        #expect(covers.candidates(for: songs[0]) == [ImageStore.contentName(blue)])
        // The other disc still needs the red file.
        #expect(store.contains(named: ImageStore.contentName(red)))

        server.covers["al-b"] = blue
        covers.keepAll(full: true)
        await covers.idle()
        #expect(!store.contains(named: ImageStore.contentName(red)))
        #expect(store.bytes == Int64(blue.count))
    }

    @Test func onlyAlbumsThatPassTheFilterGetCovers() async throws {
        let classical = Self.song("1", album: "bach", cover: "al-bach")
        let other = Self.song("2", album: "pop", cover: "al-pop")
        server.covers = ["al-bach": try Self.png(), "al-pop": try Self.png(.blue)]
        let covers = makeCovers(try makeStore(), songs: [classical, other], classical: [classical])
        covers.keepAll()
        covers.request(other, playback: true)
        covers.prefer([other])
        await covers.idle()
        #expect(server.ids == ["al-bach"])
        #expect(covers.candidates(for: other).isEmpty)
    }

    @Test func lowDataModeDefersAllButTheCoverOfWhatPlays() async throws {
        let songs = (1...3).map { Self.song("\($0)", album: "album \($0)", cover: "al-\($0)") }
        for index in 1...3 { server.covers["al-\(index)"] = try Self.png() }
        let covers = makeCovers(try makeStore(), songs: songs)
        covers.request(songs[0])
        covers.request(songs[1], playback: true)
        await covers.idle()
        covers.keepAll()
        await covers.idle()
        let allowed = Dictionary(server.requests.map { (CoverServer.id($0), $0.allowsConstrainedNetworkAccess) }) {
            $1
        }
        #expect(allowed == ["al-1": false, "al-2": true, "al-3": false])
        let sizes = server.requests.map { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?
                .first { $0.name == "size" }?.value
        }
        #expect(sizes == Array(repeating: String(CoverArt.storedPixels), count: 3))
    }

    @Test func thePassStopsAtTheLimitAndOnFailuresButPagesStillLoad() async throws {
        let songs = (1...3).map { Self.song("\($0)", album: "album \($0)", cover: "al-\($0)") }
        let red = try Self.png(.red)
        server.covers = ["al-1": red, "al-2": try Self.png(.blue), "al-3": try Self.png(.green)]
        let full = makeCovers(try makeStore(limit: Int64(red.count), folder: "full"), songs: songs)
        full.keepAll()
        await full.idle()
        #expect(server.ids == ["al-1"])
        full.request(songs[2])
        await full.idle()
        #expect(server.ids == ["al-1", "al-3"])

        server.reset()
        server.isDown = true
        let offline = makeCovers(try makeStore(folder: "offline"), songs: songs, links: "offline-links")
        offline.keepAll()
        await offline.idle()
        #expect(server.ids.count == 1)
        #expect(offline.store.bytes == 0)
        #expect(offline.candidates(for: songs[0]).isEmpty)

        server.reset()
        server.isDown = false
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A file in place of the folder makes each write fail, as a full disk does.
        try Data().write(to: root.appending(path: "broken"))
        let broken = makeCovers(try makeStore(folder: "broken"), songs: songs, links: "broken-links")
        broken.keepAll()
        await broken.idle()
        #expect(server.ids.count == 1)
        #expect(broken.candidates(for: songs[0]).isEmpty)
    }

    @Test func aServerWithoutAValidImageLeavesTheCoverAsItIs() async throws {
        var songs = [Self.song("1", album: "a", cover: "al-a")]
        server.covers = ["al-a": try Self.png(), "al-bad": Data("no image".utf8)]
        let covers = makeCovers(try makeStore(), songs: songs)
        covers.keepAll()
        await covers.idle()
        let kept = covers.candidates(for: songs[0])
        #expect(kept.count == 1)
        for source in ["al-bad", "al-missing"] {
            songs[0].coverArt = source
            covers.plan(classical: songs, library: songs)
            covers.keepAll()
            await covers.idle()
            #expect(covers.candidates(for: songs[0]) == kept)
        }
    }

    @Test func clearDropsTheLinksAndTheNextSyncFetchesAgain() async throws {
        let songs = [Self.song("1", album: "a", cover: "al-a")]
        server.covers = ["al-a": try Self.png()]
        let store = try makeStore()
        let covers = makeCovers(store, songs: songs)
        covers.keepAll()
        await covers.idle()
        store.clear()
        covers.clear()
        #expect(covers.candidates(for: songs[0]).isEmpty)
        covers.keepAll()
        await covers.idle()
        #expect(server.ids == ["al-a", "al-a"])
        #expect(covers.candidates(for: songs[0]).count == 1)
    }

    @Test func linksBelongToTheAccountAndGoAtSignOut() async throws {
        let songs = [Self.song("1", album: "a", cover: "al-a")]
        server.covers = ["al-a": try Self.png()]
        let store = try makeStore()
        let covers = makeCovers(store, songs: songs)
        covers.keepAll()
        await covers.idle()
        var other = credentials
        other.username = "someone else"
        covers.attach(other)
        #expect(covers.candidates(for: songs[0]).isEmpty)
        var password = credentials
        password.password = "replacement"
        covers.attach(password)
        #expect(covers.candidates(for: songs[0]).count == 1)
        covers.signOut()
        await covers.idle()
        #expect(makeCovers(store, songs: songs).candidates(for: songs[0]).isEmpty)
    }

    @Test func theAlbumFilesOfOlderBuildsShowUntilTheDiscCoverArrives() async throws {
        let songs = [
            Self.song("1", album: "a", disc: 1, cover: "mf-1"), Self.song("2", album: "a", disc: 2, cover: "mf-2"),
            Self.song("3", album: "pop", cover: "al-pop"),
        ]
        let old = try Self.png(.red)
        let blue = try Self.png(.blue)
        let green = try Self.png(.green)
        let store = try makeStore()
        await store.loaded()
        await store.store(old, for: CoverArt.storeKey(album: "a", credentials: credentials))
        await store.store(old, for: CoverArt.storeKey(album: "pop", credentials: credentials))
        server.isDown = true
        let covers = makeCovers(store, songs: songs, classical: Array(songs.prefix(2)))
        covers.keepAll()
        await covers.idle()
        #expect(covers.candidates(for: songs[0]) == [ImageStore.contentName(old)])
        #expect(covers.candidates(for: songs[1]) == [ImageStore.contentName(old)])
        #expect(!store.contains(CoverArt.storeKey(album: "a", credentials: credentials)))
        #expect(!store.contains(CoverArt.storeKey(album: "pop", credentials: credentials)))

        server.isDown = false
        server.covers = ["mf-1": blue, "mf-2": green]
        covers.keepAll()
        await covers.idle()
        #expect(covers.candidates(for: songs[0]) == [ImageStore.contentName(blue)])
        #expect(covers.candidates(for: songs[1]) == [ImageStore.contentName(green)])
        #expect(!store.contains(named: ImageStore.contentName(old)))
    }

    // MARK: Embedded art

    func flac(with png: Data) throws -> URL {
        let file = root.appending(path: UUID().uuidString + ".flac")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func integer(_ value: Int) -> Data {
            withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
        }
        let pictureBlock =
            integer(3) + integer(9) + Data("image/png".utf8) + integer(0)
            + integer(8) + integer(8) + integer(24) + integer(0) + integer(png.count) + png
        let data = Data("fLaC".utf8) + Data([0x86]) + integer(pictureBlock.count).dropFirst() + pictureBlock
        try data.write(to: file)
        return file
    }

    @Test func embeddedArtReplacesTheCoverOfItsTrackOnly() async throws {
        let songs = [
            Self.song("1", album: "a", disc: 1, track: 1, cover: "al-a"),
            Self.song("2", album: "a", disc: 1, track: 2, cover: "al-a"),
        ]
        let disc = try Self.png(.red)
        let embedded = try Self.png(.green)
        server.covers = ["al-a": disc]
        let covers = makeCovers(try makeStore(), songs: songs)
        covers.keepAll()
        await covers.idle()
        let discLinks = covers.links.discs
        covers.inspect(songs[0], file: try flac(with: embedded))
        covers.inspect(songs[1], file: root.appending(path: "absent.mp3"))
        await covers.idle()
        let discHash = ImageStore.contentName(disc)
        #expect(covers.candidates(for: songs[0]) == [ImageStore.contentName(embedded), discHash])
        #expect(covers.candidates(for: songs[1]) == [discHash])
        #expect(covers.links.discs == discLinks)
        #expect(makeCovers(covers.store, songs: songs).links.tracks == covers.links.tracks)
    }

    @Test func readsArtworkFromAnM4AFile() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let wav = root.appending(path: "tone.wav")
        let output = root.appending(path: "tone.m4a")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = buffer.frameCapacity
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<Int(buffer.frameLength) { samples[index] = 0 }
        do {
            let file = try AVAudioFile(forWriting: wav, settings: format.settings)
            try file.write(from: buffer)
        }
        let exporter = try #require(
            AVAssetExportSession(asset: AVURLAsset(url: wav), presetName: AVAssetExportPresetAppleM4A))
        let artwork = AVMutableMetadataItem()
        artwork.identifier = .commonIdentifierArtwork
        artwork.value = try Self.png() as NSData
        exporter.metadata = [artwork]
        try await exporter.export(to: output, as: .m4a)
        let data = try #require(await CoverArt.embeddedCover(in: output))
        #expect(UIImage(data: data)?.size == CGSize(width: 8, height: 8))
        #expect(await CoverArt.embeddedCover(in: wav) == nil)
    }

    @Test func largeArtScalesToTheKeptSize() async throws {
        let side = CoverArt.storedPixels
        let large = try #require(Self.picture(width: side * 2, height: side).pngData())
        let scaled = try #require(await CoverArt.normalized(large))
        #expect(UIImage(data: scaled)?.size == CGSize(width: side, height: side / 2))
        let small = try Self.png()
        #expect(await CoverArt.normalized(small) == small)
        #expect(await CoverArt.normalized(Data("no image".utf8)) == nil)
    }

    @Test func decodedCoversAreKeptByFileAndSize() {
        let cache = CoverArt.Cache()
        let cover = Self.picture()
        cache.store(cover, hash: "a", pixels: 160)
        #expect(cache.image(hash: "a", pixels: 160) === cover)
        #expect(cache.image(hash: "a", pixels: 320) == nil)
        #expect(cache.image(hash: "b", pixels: 160) == nil)
        cache.clear()
        #expect(cache.image(hash: "a", pixels: 160) == nil)
    }
    @Test func aLargeQueueKeepsPriorityAfterManyPops() {
        var queue = CoverQueue()
        let keys = (0..<20_000).map(String.init)
        queue.append(keys)
        for key in keys.prefix(10_000) { #expect(queue.pop()?.key == key) }
        queue.front(["15000", "10001"], reason: .playback)
        queue.front(["10001"], reason: .page)
        #expect(queue.pop()?.reason == .playback)
        #expect(queue.pop()?.key == "15000")
        let expected = keys.dropFirst(10_000).filter { $0 != "15000" && $0 != "10001" }
        for key in expected { #expect(queue.pop()?.key == key) }
        #expect(queue.isEmpty)
        queue.append(["again"])
        #expect(queue.pop()?.key == "again")
    }

    @Test func anIdlePassFetchesAlbumsAdmittedByTheFilter() async throws {
        let songs = [Self.song("1", album: "a", cover: "a"), Self.song("2", album: "b", cover: "b")]
        server.covers = ["a": try Self.png(), "b": try Self.png(.blue)]
        let covers = makeCovers(try makeStore(), songs: songs, classical: [songs[0]])
        await covers.idle()
        #expect(server.ids == ["a"])
        covers.plan(classical: songs, library: songs)
        await covers.idle()
        #expect(server.ids == ["a", "b"])
        #expect(!covers.candidates(for: songs[1]).isEmpty)
    }

    @Test func excludedEmbeddedArtStaysOutAndArtWithoutAServerIDStillWorks() async throws {
        let songs = [Self.song("1", album: "a", cover: nil), Self.song("2", album: "b", cover: nil)]
        let store = try makeStore()
        let covers = makeCovers(store, songs: songs, classical: [songs[0]])
        let art = try Self.png(.green)
        let audio = try flac(with: art)
        covers.inspect(songs[1], file: audio)
        await covers.idle()
        #expect(covers.links.tracks.isEmpty)
        #expect(!store.contains(named: ImageStore.contentName(art)))
        covers.inspect(songs[0], file: audio)
        await covers.idle()
        #expect(covers.candidates(for: songs[0]) == [ImageStore.contentName(art)])
        covers.plan(classical: [songs[1]], library: songs)
        #expect(covers.candidates(for: songs[0]).isEmpty)
    }

    @Test func aFailedAdoptionKeepsTheLegacyFileAndRetries() async throws {
        let songs = [Self.song("1", album: "a", cover: "a")]
        let art = try Self.png()
        let store = try makeStore()
        await store.loaded()
        let legacy = CoverArt.storeKey(album: "a", credentials: credentials)
        await store.store(art, for: legacy)
        let blocked = root.appending(path: "art/" + ImageStore.contentName(art))
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        server.isDown = true
        let covers = makeCovers(store, songs: songs)
        await covers.idle()
        #expect(store.contains(legacy))
        #expect(await store.data(for: legacy) == art)
        #expect(covers.candidates(for: songs[0]) == [ImageStore.name(legacy)])
        try FileManager.default.removeItem(at: blocked)
        covers.keepAll()
        await covers.idle()
        #expect(covers.candidates(for: songs[0]) == [ImageStore.contentName(art)])
        #expect(!store.contains(legacy))
    }

    @Test func aFailedAdoptionLinkCommitKeepsTheLegacyFile() async throws {
        let songs = [Self.song("1", album: "a", cover: "a")]
        let art = try Self.png()
        let store = try makeStore()
        await store.loaded()
        let legacy = CoverArt.storeKey(album: "a", credentials: credentials)
        await store.store(art, for: legacy)
        let file = root.appending(path: "links/" + ImageStore.name(CoverArt.account(credentials)) + ".json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        server.isDown = true
        let covers = makeCovers(store, songs: songs)
        await covers.idle()
        #expect(await store.data(for: legacy) == art)
        #expect(store.contains(named: ImageStore.contentName(art)))
        try FileManager.default.removeItem(at: file)
        covers.keepAll()
        await covers.idle()
        #expect(!store.contains(legacy))
        #expect(makeCovers(store, songs: songs).links.discs.values.first?.hash == ImageStore.contentName(art))
    }

    @Test func aFailedEmbeddedLinkCommitKeepsTheCommittedDisc() async throws {
        let songs = [Self.song("1", album: "a", cover: "a")]
        let red = try Self.png()
        let green = try Self.png(.green)
        server.covers = ["a": red]
        let store = try makeStore()
        let covers = makeCovers(store, songs: songs)
        await covers.idle()
        let file = root.appending(path: "links/" + ImageStore.name(CoverArt.account(credentials)) + ".json")
        let saved = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        covers.inspect(songs[0], file: try flac(with: green))
        await covers.idle()
        #expect(store.contains(named: ImageStore.contentName(red)))
        try FileManager.default.removeItem(at: file)
        try saved.write(to: file)
        let restored = AlbumCovers(store: store, folder: root.appending(path: "links"))
        restored.attach(credentials)
        #expect(restored.links.tracks.isEmpty)
        #expect(restored.links.discs.values.first?.hash == ImageStore.contentName(red))
        covers.keepAll()
        await covers.idle()
        #expect(makeCovers(store, songs: songs).links.tracks[songs[0].id] == ImageStore.contentName(green))
    }

    @Test func aFailedLinksWritePreservesCommittedDiscAndTrackFiles() async throws {
        let songs = [Self.song("1", album: "a", cover: "a")]
        let red = try Self.png()
        let blue = try Self.png(.blue)
        server.covers = ["a": red]
        let store = try makeStore()
        let covers = makeCovers(store, songs: songs)
        await covers.idle()
        let green = try Self.png(.green)
        covers.inspect(songs[0], file: try flac(with: green))
        await covers.idle()
        let committed = covers.links
        let file = root.appending(path: "links/" + ImageStore.name(CoverArt.account(credentials)) + ".json")
        let saved = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        server.covers = ["a": blue]
        covers.keepAll(full: true)
        await covers.idle()
        #expect(store.contains(named: ImageStore.contentName(red)))
        try FileManager.default.removeItem(at: file)
        try saved.write(to: file)
        let restored = AlbumCovers(store: store, folder: root.appending(path: "links"))
        restored.attach(credentials)
        #expect(restored.links == committed)
        #expect(store.contains(named: try #require(restored.links.discs.values.first?.hash)))
        covers.keepAll()
        await covers.idle()
        #expect(makeCovers(store, songs: songs).links.discs.values.first?.hash == ImageStore.contentName(blue))
        // The track keeps its own content after the disc replacement commits.
        #expect(!store.contains(named: ImageStore.contentName(red)))
        #expect(store.contains(named: ImageStore.contentName(green)))
    }

}
