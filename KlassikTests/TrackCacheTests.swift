import Foundation
import Testing

@testable import Klassik

struct CacheEvictionTests {
    private func entry(_ id: String, size: Int64, age: Double) -> TrackCache.Entry {
        TrackCache.Entry(
            id: id, url: URL(fileURLWithPath: "/cache/\(id).mp3"), size: size,
            lastUsed: Date(timeIntervalSince1970: 1_000_000 - age))
    }

    @Test func evictsLeastRecentlyPlayedFirst() {
        let entries = [entry("new", size: 10, age: 1), entry("old", size: 10, age: 30), entry("mid", size: 10, age: 20)]

        let result = TrackCache.evictions(entries, limit: 15, protecting: [])

        #expect(result.map(\.id) == ["old", "mid"])
    }

    @Test func keepsEverythingUnderLimit() {
        let entries = [entry("a", size: 10, age: 1), entry("b", size: 10, age: 2)]

        #expect(TrackCache.evictions(entries, limit: 20, protecting: []).isEmpty)
    }

    @Test func neverEvictsDownloadedTracks() {
        let entries = [entry("loaded", size: 100, age: 50), entry("a", size: 10, age: 2), entry("b", size: 10, age: 1)]

        let result = TrackCache.evictions(entries, limit: 10, protecting: ["loaded"])

        #expect(result.map(\.id) == ["a"])
    }

    @Test func downloadedTracksDoNotCountTowardLimit() {
        let entries = [entry("loaded", size: 1_000, age: 5), entry("a", size: 10, age: 1)]

        #expect(TrackCache.evictions(entries, limit: 10, protecting: ["loaded"]).isEmpty)
    }

    @Test func breaksTiesByID() {
        let entries = [entry("b", size: 10, age: 1), entry("a", size: 10, age: 1)]

        #expect(TrackCache.evictions(entries, limit: 10, protecting: []).map(\.id) == ["a"])
    }
}

@MainActor
struct TrackCacheTests {
    private func makeCache(limit: Int64) -> (TrackCache, URL) {
        let folder = URL.temporaryDirectory.appending(path: "klassik-cache-\(UUID().uuidString)")
        let cache = TrackCache(folder: folder, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        cache.limit = limit
        return (cache, folder)
    }

    private func song(_ id: String) -> Song {
        Song(id: id, title: id, suffix: "mp3")
    }

    private func load(_ id: String, bytes: Int, into cache: TrackCache, protecting: Set<String> = []) throws {
        let temporary = URL.temporaryDirectory.appending(path: "load-\(UUID().uuidString)")
        try Data(count: bytes).write(to: temporary)
        _ = try cache.store(temporary, for: song(id), protecting: protecting)
    }

    private func setDate(_ seconds: Double, of id: String, in folder: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: seconds)],
            ofItemAtPath: folder.appending(path: "\(id).mp3").path())
    }

    @Test func storeRemovesOldestTrackOverLimit() throws {
        let (cache, folder) = makeCache(limit: 25)
        defer { try? FileManager.default.removeItem(at: folder) }
        try load("a", bytes: 10, into: cache)
        try setDate(1, of: "a", in: folder)
        try load("b", bytes: 10, into: cache)

        try load("c", bytes: 10, into: cache)

        #expect(cache.ids == ["b", "c"])
        #expect(cache.size == 20)
    }

    @Test func playingATrackMakesItRecent() throws {
        let (cache, folder) = makeCache(limit: 25)
        defer { try? FileManager.default.removeItem(at: folder) }
        try load("a", bytes: 10, into: cache)
        try load("b", bytes: 10, into: cache)
        try setDate(1, of: "a", in: folder)
        try setDate(2, of: "b", in: folder)

        #expect(cache.url(for: song("a")) != nil)
        try load("c", bytes: 10, into: cache)

        #expect(cache.ids == ["a", "c"])
    }

    @Test func storeKeepsDownloadedTrack() throws {
        let (cache, folder) = makeCache(limit: 5)
        defer { try? FileManager.default.removeItem(at: folder) }
        try load("loaded", bytes: 10, into: cache, protecting: ["loaded"])

        try load("x", bytes: 4, into: cache, protecting: ["loaded"])

        #expect(cache.ids == ["loaded", "x"])
    }

    @Test func takeMovesTrackOutOfCache() throws {
        let (cache, folder) = makeCache(limit: 100)
        defer { try? FileManager.default.removeItem(at: folder) }
        try load("a", bytes: 10, into: cache)

        let taken = try #require(cache.take(song("a")))

        #expect(FileManager.default.fileExists(atPath: taken.path()))
        #expect(cache.ids.isEmpty)
        try? FileManager.default.removeItem(at: taken)
    }

    @Test func clearEmptiesCache() throws {
        let (cache, folder) = makeCache(limit: 100)
        defer { try? FileManager.default.removeItem(at: folder) }
        try load("a", bytes: 10, into: cache)

        cache.clear()

        #expect(cache.size == 0)
        #expect(cache.ids.isEmpty)
    }

    @Test func limitSurvivesRestart() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let folder = URL.temporaryDirectory.appending(path: "klassik-cache-\(UUID().uuidString)")
        TrackCache(folder: folder, defaults: defaults).limit = 5_000_000_000

        #expect(TrackCache(folder: folder, defaults: defaults).limit == 5_000_000_000)
        let fresh = UserDefaults(suiteName: UUID().uuidString)!
        #expect(TrackCache(folder: folder, defaults: fresh).limit == 2_000_000_000)
    }
}

struct OfflineStatusTests {
    @Test func downloadedBeatsCached() {
        #expect(OfflineStatus(songIDs: ["a", "b"], downloaded: ["a", "b"], cached: ["a"]) == .downloaded)
    }

    @Test func mixOfBothMeansCached() {
        #expect(OfflineStatus(songIDs: ["a", "b"], downloaded: ["a"], cached: ["b"]) == .cached)
    }

    @Test func missingTrackMeansNone() {
        #expect(OfflineStatus(songIDs: ["a", "b"], downloaded: ["a"], cached: []) == .none)
        #expect(OfflineStatus(songIDs: [], downloaded: ["a"], cached: ["a"]) == .none)
    }
}
