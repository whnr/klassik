import Foundation
import Testing

@testable import Klassik

struct DownloadStateTests {
    @Test func noTracksMeansNone() {
        #expect(DownloadState(songIDs: [], downloaded: ["a"], pending: []) == .none)
    }

    @Test func allTracksMeansComplete() {
        #expect(DownloadState(songIDs: ["a", "b"], downloaded: ["a", "b", "c"], pending: []) == .complete)
    }

    @Test func someTracksMeansPartial() {
        #expect(DownloadState(songIDs: ["a", "b"], downloaded: ["a"], pending: []) == .partial(done: 1, total: 2))
    }

    @Test func pendingTrackMeansDownloading() {
        #expect(
            DownloadState(songIDs: ["a", "b"], downloaded: ["a"], pending: ["b"]) == .downloading(done: 1, total: 2))
    }

    @Test func noTrackAndNoPendingMeansNone() {
        #expect(DownloadState(songIDs: ["a"], downloaded: [], pending: ["x"]) == .none)
    }

    @Test func repeatedIDCountsOnce() {
        #expect(DownloadState(songIDs: ["a", "a", "b"], downloaded: ["a"], pending: []) == .partial(done: 1, total: 2))
    }

    @Test func labelsStateInWords() {
        #expect(DownloadState.complete.label == "Downloaded")
        #expect(DownloadState.partial(done: 1, total: 3).label == "1 of 3 tracks downloaded")
    }
}

@MainActor
struct DownloadStoreTests {
    let client = SubsonicClient(
        credentials: ServerCredentials(url: URL(string: "https://music.example.org")!, username: "joe", password: "x"))

    private func song(_ id: String, suffix: String? = "mp3") -> Song {
        Song(id: id, title: "Track \(id)", suffix: suffix)
    }

    private func temporaryFolder() -> URL {
        URL.temporaryDirectory.appending(path: "klassik-tests-\(UUID().uuidString)")
    }

    private func cache() -> TrackCache {
        TrackCache(folder: temporaryFolder(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    /// A fetch that writes a small file, as URLSession does for a finished download.
    private static let fetch: DownloadStore.Fetch = { song, _ in
        let url = URL.temporaryDirectory.appending(path: "fetch-\(UUID().uuidString)")
        try Data(song.id.utf8).write(to: url)
        return url
    }

    /// Lets the worker task run until the store has nothing left to load.
    private func settle(_ store: DownloadStore) async {
        for _ in 0..<200 where !store.pending.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func namesFileAfterIDAndSuffix() {
        #expect(DownloadStore.fileName(for: song("a1", suffix: "flac")) == "a1.flac")
        #expect(DownloadStore.fileName(for: song("a1", suffix: nil)) == "a1.mp3")
    }

    @Test func downloadsTracksIntoFolder() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DownloadStore(folder: folder, cache: cache(), fetch: Self.fetch)
        let songs = [song("a"), song("b", suffix: "flac")]

        store.download(songs, client: client)
        await settle(store)

        #expect(store.state(of: songs) == .complete)
        let local = try #require(store.localURL(for: songs[1]))
        #expect(local.lastPathComponent == "b.flac")
        #expect(try Data(contentsOf: local) == Data("b".utf8))
    }

    @Test func findsTracksAfterRestart() async {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let songs = [song("a"), song("b")]
        let first = DownloadStore(folder: folder, cache: cache(), fetch: Self.fetch)
        first.download(songs, client: client)
        await settle(first)

        let second = DownloadStore(folder: folder, cache: cache(), fetch: Self.fetch)

        #expect(second.state(of: songs) == .complete)
    }

    @Test func removesFilesAndState() async {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DownloadStore(folder: folder, cache: cache(), fetch: Self.fetch)
        let songs = [song("a"), song("b")]
        store.download(songs, client: client)
        await settle(store)

        store.remove([songs[0]])

        #expect(store.state(of: songs) == .partial(done: 1, total: 2))
        #expect(store.localURL(for: songs[0]) == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "a.mp3").path()))
    }

    @Test func removeAllEmptiesFolder() async {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DownloadStore(folder: folder, cache: cache(), fetch: Self.fetch)
        store.download([song("a")], client: client)
        await settle(store)

        store.removeAll()

        #expect(store.downloaded.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path()))
    }

    @Test func failureStopsQueueAndKeepsError() async {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DownloadStore(folder: folder, cache: cache()) { _, _ in throw SubsonicError.http(status: 500) }
        let songs = [song("a"), song("b")]

        store.download(songs, client: client)
        await settle(store)

        #expect(store.state(of: songs) == .none)
        #expect(store.error == SubsonicError.http(status: 500).localizedDescription)
    }

    @Test func skipsTracksThatAreAlreadyThere() async {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DownloadStore(folder: folder, cache: cache(), fetch: Self.fetch)
        store.download([song("a")], client: client)
        await settle(store)

        store.download([song("a")], client: client)

        #expect(store.pending.isEmpty)
    }
}
