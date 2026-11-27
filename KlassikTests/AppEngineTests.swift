import Foundation
import Testing

@testable import Klassik
@testable import KlassikEngine

/// The engine of the app plays with the fades of the owner's spec, the same value as the Playback Lab.
@Suite(.serialized)
@MainActor
struct AppEngineTests {
    private static func store() -> TrackStore {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AppEngineTests-\(UUID().uuidString)")
        return TrackStore(
            cacheFolder: folder.appending(path: "tracks"), downloadFolder: folder.appending(path: "downloads"),
            defaults: UserDefaults(suiteName: "AppEngineTests.\(UUID().uuidString)")!)
    }

    @Test func theAppEnginePlaysWithTheSpecFades() {
        #expect(GaplessEngine.forApp(tracks: Self.store()).fadeOptions == .spec)
    }

    @Test func theAppModelBuildsItsEngineWithTheSpecFades() throws {
        let model = AppModel(
            store: CredentialStore(), library: Library(), listener: ListenerData(),
            defaults: UserDefaults(suiteName: "AppEngineTests.\(UUID().uuidString)")!)
        let engine = try #require(model.playback.engine as? GaplessEngine)
        #expect(engine.fadeOptions == .spec)
    }

    /// A crossfade waits for bytes. A track that is not on the device fades the old sound out at once.
    @Test func aTrackThatIsNotOnTheDeviceIsNotReadyForACrossfade() throws {
        let engine = GaplessEngine.forApp(tracks: Self.store())
        let check = try #require(engine.isOnDisk)
        #expect(!check(PlaybackTrack(id: "not-on-device")))
    }

    /// A complete file in the music cache or in the downloads is on the device. A wrong check would fade out
    /// before every seek and then wait for bytes that are already there.
    @Test func aTrackInTheMusicCacheOrADownloadIsReadyForACrossfade() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AppEngineTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appending(path: "tracks")
        let downloads = folder.appending(path: "downloads")
        for directory in [cache, downloads] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(count: 16).write(to: cache.appending(path: "cached.flac"))
        try Data(count: 16).write(to: downloads.appending(path: "kept.flac"))
        let store = TrackStore(
            cacheFolder: cache, downloadFolder: downloads,
            defaults: UserDefaults(suiteName: "AppEngineTests.\(UUID().uuidString)")!)
        let check = try #require(GaplessEngine.forApp(tracks: store).isOnDisk)
        #expect(check(PlaybackTrack(id: "cached")))
        #expect(check(PlaybackTrack(id: "kept")))
        #expect(!check(PlaybackTrack(id: "elsewhere")))
    }
}
