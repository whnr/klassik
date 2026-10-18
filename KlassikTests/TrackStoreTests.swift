import Foundation
import Testing

@testable import Klassik

@MainActor
struct TrackStoreTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func makeStore() throws -> TrackStore {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        return TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "support/downloads"),
            defaults: defaults)
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
}
