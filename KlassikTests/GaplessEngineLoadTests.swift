import Testing

@testable import Klassik

@Suite(.serialized)
@MainActor
struct GaplessEngineLoadTests {
    @MainActor private final class Recorder {
        var events: [PlaybackEngineEvent] = []
        var fileRequests = 0
    }

    /// A load starts its task on the main actor. A `discard()` before that task runs must leave the engine silent.
    @Test func aLoadThatADiscardReplacedSendsNothing() async throws {
        let recorder = Recorder()
        let engine = GaplessEngine()
        engine.onEvent = { recorder.events.append($0) }
        let song = Song(id: "a-0", title: "Movement 1", duration: 10, suffix: "wav")
        engine.load([song], from: 0, offset: 0) { _ in
            recorder.fileRequests += 1
            throw CancellationError()
        }
        engine.discard()
        try await Task.sleep(for: .milliseconds(200))
        #expect(recorder.events.isEmpty)
        #expect(recorder.fileRequests == 0)
        #expect(!engine.isRunning)
    }
}
