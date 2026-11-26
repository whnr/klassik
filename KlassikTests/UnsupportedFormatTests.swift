import Testing

@testable import KlassikEngine

/// Opus and Ogg files fail with a name, not with a general decoder error (sz-u8f4).
@MainActor
struct UnsupportedFormatTests {
    @Test func opusFailsWithItsName() async throws {
        let engine = GaplessEngine(manualRendering: true, watchesStarvation: false)
        var failures: [String] = []
        engine.onEvent = { event in
            if case .failed(let text) = event { failures.append(text) }
        }
        defer { engine.discard() }
        engine.load([PlaybackTrack(id: "o", duration: 1, suffix: "opus")], from: 0, offset: 0) { _ in
            throw CancellationError()
        }
        for _ in 0..<500 where failures.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(failures == ["Opus is not supported on iOS."])
    }

    @Test func onlyOpusAndOggAreUnsupported() {
        #expect(PlaybackTrack(id: "a", suffix: "OPUS").unsupportedFormat == "Opus is not supported on iOS.")
        #expect(PlaybackTrack(id: "a", suffix: "ogg").unsupportedFormat == "Ogg is not supported on iOS.")
        #expect(PlaybackTrack(id: "a", suffix: "flac").unsupportedFormat == nil)
        #expect(PlaybackTrack(id: "a").unsupportedFormat == nil)
    }
}
