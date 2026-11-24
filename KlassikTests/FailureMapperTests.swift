import Foundation
import Testing

@testable import Klassik
@testable import KlassikEngine

/// Which errors show the one quiet server status, and that the app gives its mapper to the engine.
@Suite(.serialized)
@MainActor
struct FailureMapperTests {
    @MainActor private final class Recorder {
        var events: [PlaybackEngineEvent] = []

        /// The events that end a load. The engine also reports its waiting state.
        var ends: [PlaybackEngineEvent] {
            events.filter {
                switch $0 {
                case .serverFailed, .failed: true
                default: false
                }
            }
        }
    }

    @Test func theAppMapperNamesTheAppErrors() {
        let mapper = AppFailureMapper()
        #expect(mapper.serverFailure(for: TrackStore.Failure.offline) == .unreachable)
        #expect(mapper.serverFailure(for: SubsonicError.http(status: 500)) == .refused)
        #expect(mapper.serverFailure(for: URLError(.timedOut)) == .unreachable)
        #expect(mapper.serverFailure(for: TrackTransfer.Failure.http(404)) == .refused)
        #expect(mapper.serverFailure(for: TrackTransfer.Failure.storage) == nil)
    }

    /// The default mapper does not know the app's errors. This is why the app passes its own.
    @Test func theDefaultMapperDoesNotKnowTheAppErrors() {
        let mapper = TransferFailureMapper()
        #expect(mapper.serverFailure(for: TrackStore.Failure.offline) == nil)
        #expect(mapper.serverFailure(for: SubsonicError.http(status: 500)) == nil)
        #expect(mapper.serverFailure(for: URLError(.timedOut)) == .unreachable)
    }

    @Test func theAppGivesItsMapperToTheEngine() throws {
        let model = AppModel(
            store: CredentialStore(), library: Library(), listener: ListenerData(),
            defaults: UserDefaults(suiteName: "FailureMapperTests.\(UUID().uuidString)")!)
        let engine = try #require(model.playback.engine as? GaplessEngine)
        #expect(engine.failureMapper is AppFailureMapper)
    }

    @Test func offlineEndsALoadWithTheQuietStatus() async throws {
        let recorder = Recorder()
        let engine = GaplessEngine(failureMapper: AppFailureMapper())
        engine.onEvent = { recorder.events.append($0) }
        let song = Song(id: "a-0", title: "Movement 1", duration: 10, suffix: "wav")
        engine.load([song.playbackTrack], from: 0, offset: 0) { _ in throw TrackStore.Failure.offline }
        try engine.resume()
        defer { engine.discard() }
        for _ in 0..<200 where recorder.ends.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.ends.count == 1)
        guard case .serverFailed(let failure)? = recorder.ends.first else {
            Issue.record("Expected a server failure, got \(recorder.events)")
            return
        }
        #expect(failure == .unreachable)
    }

    @Test func theDefaultMapperShowsOfflineAsAFailureText() async throws {
        let recorder = Recorder()
        let engine = GaplessEngine()
        engine.onEvent = { recorder.events.append($0) }
        let song = Song(id: "a-0", title: "Movement 1", duration: 10, suffix: "wav")
        engine.load([song.playbackTrack], from: 0, offset: 0) { _ in throw TrackStore.Failure.offline }
        try engine.resume()
        defer { engine.discard() }
        for _ in 0..<200 where recorder.ends.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.ends.count == 1)
        guard case .failed(let text)? = recorder.ends.first else {
            Issue.record("Expected a failure text, got \(recorder.events)")
            return
        }
        #expect(text == TrackStore.Failure.offline.localizedDescription)
    }
}
