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
}
