import Foundation
import Testing

@testable import Klassik

@MainActor
struct TrackStoreTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    let client = SubsonicClient(
        credentials: ServerCredentials(url: URL(string: "https://music.example.org")!, username: "joe", password: "x"))

    /// Remembers which tracks the store asked the server for.
    @MainActor final class Requests {
        var ids: [String] = []
        var failing: Set<String> = []
    }

    func makeStore(_ requests: Requests = Requests()) throws -> TrackStore {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        return TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "support/downloads"),
            defaults: defaults,
            fetch: { song, _ in
                requests.ids.append(song.id)
                if requests.failing.contains(song.id) { throw SubsonicError.http(status: 500) }
                let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                try Data(count: 100).write(to: file)
                return file
            })
    }

    func song(_ id: String) -> Song { Song(id: id, title: "Track \(id)", suffix: "mp3") }

    func recording(_ id: String, _ songIDs: [String]) -> WorkIndex.Recording {
        WorkIndex.Recording(id: id, album: "Album", year: nil, performers: "Orchestra", songs: songIDs.map(song))
    }

    /// Waits until no download runs.
    func settle(_ store: TrackStore) async {
        for _ in 0..<500 where !store.progress.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Writes a fake track. A later `age` means an older file.
    func write(_ id: String, in folder: String, bytes: Int, age: TimeInterval = 0) throws {
        let url = root.appending(path: folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appending(path: "\(id).mp3")
        try Data(count: bytes).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date.now - age], ofItemAtPath: file.path())
    }

    func exists(_ id: String, in folder: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: "\(folder)/\(id).mp3").path())
    }

    @Test func offlineFollowsBothFolders() throws {
        try write("c1", in: "cache", bytes: 10)
        try write("d1", in: "support/downloads", bytes: 20)
        let store = try makeStore()
        #expect(store.offline == ["c1", "d1"])
        #expect(store.cacheBytes == 10)
    }

    /// The cache drops the track played longest ago first, and a download is not part of the count.
    @Test func fullCacheDropsTheOldestTracks() throws {
        try write("old", in: "cache", bytes: 600_000_000, age: 300)
        try write("middle", in: "cache", bytes: 600_000_000, age: 200)
        try write("new", in: "cache", bytes: 600_000_000, age: 100)
        try write("kept", in: "support/downloads", bytes: 3_000_000_000)
        let store = try makeStore()
        store.cacheLimit = 1_300_000_000
        #expect(!exists("old", in: "cache"))
        #expect(exists("middle", in: "cache"))
        #expect(exists("new", in: "cache"))
        #expect(exists("kept", in: "support/downloads"))
        #expect(store.offline == ["middle", "new", "kept"])
    }

    @Test func trackThatPlaysNowStaysEvenIfOldest() throws {
        try write("playing", in: "cache", bytes: 600_000_000, age: 300)
        try write("other", in: "cache", bytes: 600_000_000, age: 100)
        let store = try makeStore()
        store.cacheLimit = 700_000_000
        store.evict(keeping: root.appending(path: "cache/playing.mp3"))
        #expect(exists("playing", in: "cache"))
        #expect(!exists("other", in: "cache"))
    }

    @Test func clearCacheKeepsDownloads() throws {
        try write("c1", in: "cache", bytes: 10)
        try write("d1", in: "support/downloads", bytes: 10)
        let store = try makeStore()
        store.clearCache()
        #expect(store.offline == ["d1"])
        #expect(store.cacheBytes == 0)
    }

    @Test func clearAllRemovesEverything() throws {
        try write("c1", in: "cache", bytes: 10)
        try write("d1", in: "support/downloads", bytes: 10)
        let store = try makeStore()
        store.clearAll()
        #expect(store.offline.isEmpty)
        #expect(store.downloads.isEmpty)
        #expect(!exists("d1", in: "support/downloads"))
    }

    @Test func limitIsKeptOnDevice() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "support/downloads"),
            defaults: defaults
        ).cacheLimit = TrackStore.limits[0]
        let again = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "support/downloads"),
            defaults: defaults)
        #expect(again.cacheLimit == TrackStore.limits[0])
    }

    @Test func playingATrackFetchesItIntoTheCacheOnce() async throws {
        let requests = Requests()
        let store = try makeStore(requests)
        let first = try await store.file(for: song("a"), client: client)
        let second = try await store.file(for: song("a"), client: client)
        #expect(first == second)
        #expect(requests.ids == ["a"])
        #expect(exists("a", in: "cache"))
        #expect(store.isOffline(song("a")))
        #expect(store.cacheBytes == 100)
    }

    @Test func fetchedTrackPushesOutTheOldestCachedTrack() async throws {
        try write("old", in: "cache", bytes: 100, age: 500)
        let store = try makeStore()
        store.cacheLimit = 150
        _ = try await store.file(for: song("new"), client: client)
        #expect(!exists("old", in: "cache"))
        #expect(exists("new", in: "cache"))
    }

    @Test func playingACachedTrackMakesItRecent() async throws {
        try write("a", in: "cache", bytes: 100, age: 500)
        try write("b", in: "cache", bytes: 100, age: 300)
        let store = try makeStore()
        _ = try await store.file(for: song("a"), client: client)
        store.cacheLimit = 100
        #expect(exists("a", in: "cache"))
        #expect(!exists("b", in: "cache"))
    }

    @Test func downloadedTrackPlaysFromTheDownloadFolder() async throws {
        try write("a", in: "support/downloads", bytes: 10)
        let requests = Requests()
        let store = try makeStore(requests)
        let file = try await store.file(for: song("a"), client: client)
        #expect(file.path().contains("support/downloads"))
        #expect(requests.ids.isEmpty)
    }

    @Test func fetchFailureLeavesNothingBehind() async throws {
        let requests = Requests()
        requests.failing = ["a"]
        let store = try makeStore(requests)
        await #expect(throws: SubsonicError.self) { try await store.file(for: song("a"), client: client) }
        #expect(store.offline.isEmpty)
        #expect(store.cacheBytes == 0)
    }

    @Test func downloadStoresEveryTrackAndTheManifest() async throws {
        let store = try makeStore()
        let recording = recording("r1", ["a", "b", "c"])
        store.download(recording, title: "Work", client: client)
        await settle(store)
        #expect(store.isDownloaded(recording))
        #expect(store.isOffline(recording))
        #expect(store.downloads.map(\.title) == ["Work"])
        #expect(store.downloads.first?.songIDs == ["a", "b", "c"])
        #expect(store.downloadBytes == 300)
        #expect(store.failures.isEmpty)
        #expect(exists("a", in: "support/downloads") && exists("c", in: "support/downloads"))
    }

    @Test func downloadListSurvivesARestart() async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        func open() -> TrackStore {
            TrackStore(
                cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "support/downloads"),
                defaults: defaults,
                fetch: { _, _ in
                    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                    try Data(count: 10).write(to: file)
                    return file
                })
        }
        let first = open()
        first.download(recording("r1", ["a"]), title: "Work", client: client)
        await settle(first)
        let second = open()
        #expect(second.downloads.map(\.id) == ["r1"])
        #expect(second.isOffline(song("a")))
    }

    @Test func downloadMovesCachedTracksInsteadOfFetchingThemAgain() async throws {
        try write("a", in: "cache", bytes: 40)
        let requests = Requests()
        let store = try makeStore(requests)
        store.download(recording("r1", ["a", "b"]), title: "Work", client: client)
        await settle(store)
        #expect(requests.ids == ["b"])
        #expect(!exists("a", in: "cache"))
        #expect(exists("a", in: "support/downloads"))
        #expect(store.downloads.first?.bytes == 140)
    }

    @Test func failedDownloadKeepsNoPartOfTheRecording() async throws {
        let requests = Requests()
        requests.failing = ["c"]
        let store = try makeStore(requests)
        let recording = recording("r1", ["a", "b", "c"])
        store.download(recording, title: "Work", client: client)
        await settle(store)
        #expect(store.downloads.isEmpty)
        #expect(store.offline.isEmpty)
        #expect(store.failures["r1"] != nil)
        #expect(!exists("a", in: "support/downloads"))
    }

    @Test func failedDownloadKeepsATrackThatAnotherDownloadHolds() async throws {
        try write("a", in: "support/downloads", bytes: 10)
        let requests = Requests()
        requests.failing = ["b"]
        let store = try makeStore(requests)
        store.download(recording("r1", ["a", "b"]), title: "Work", client: client)
        await settle(store)
        #expect(exists("a", in: "support/downloads"))
    }

    @Test func recordingDownloadsOnlyOnce() async throws {
        let requests = Requests()
        let store = try makeStore(requests)
        let recording = recording("r1", ["a"])
        store.download(recording, title: "Work", client: client)
        store.download(recording, title: "Work", client: client)
        await settle(store)
        store.download(recording, title: "Work", client: client)
        await settle(store)
        #expect(requests.ids == ["a"])
        #expect(store.downloads.count == 1)
    }

    @Test func removeKeepsATrackThatAnotherDownloadHolds() async throws {
        let store = try makeStore()
        store.download(recording("r1", ["a", "b"]), title: "One", client: client)
        await settle(store)
        store.download(recording("r2", ["b", "c"]), title: "Two", client: client)
        await settle(store)
        let one = try #require(store.downloads.first { $0.id == "r1" })
        store.remove(one)
        #expect(!exists("a", in: "support/downloads"))
        #expect(exists("b", in: "support/downloads"))
        #expect(store.offline == ["b", "c"])
        #expect(store.downloads.map(\.id) == ["r2"])
    }

    @Test func cancelStopsADownloadAndKeepsNothing() async throws {
        let store = try makeStore()
        store.download(recording("r1", ["a", "b", "c"]), title: "Work", client: client)
        store.cancelDownload("r1")
        await settle(store)
        #expect(store.downloads.isEmpty)
        #expect(store.offline.isEmpty)
        #expect(store.failures.isEmpty)
    }

    @Test func recordingIsOfflineOnlyWithEveryTrack() throws {
        try write("a", in: "cache", bytes: 10)
        let store = try makeStore()
        #expect(store.isOffline(recording("r1", ["a"])))
        #expect(!store.isOffline(recording("r1", ["a", "b"])))
        #expect(!store.isOffline(recording("r1", [])))
    }
}
