import AVFoundation
import Testing

@testable import Klassik

/// The engine ramps a skip: a discard of a sounding engine stops it after the fade-out, and a start fades in.
/// The graph is real and renders offline, so the tests see the node volume and the engine state.
@Suite(.serialized)
@MainActor
struct GaplessEngineSkipTests {
    private static func graph() throws -> (AVAudioEngine, AVAudioPlayerNode) {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        try engine.connectNode(node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        return (engine, node)
    }

    /// Waits until the condition holds, for at most a second.
    private static func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func aDiscardOfASoundingEngineStopsItAfterTheRamp() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine()
        player.adopt(engine, node, started: true)
        try player.start(node)
        #expect(await Self.eventually { node.volume == 1 })
        player.discard()
        #expect(engine.isRunning)
        #expect(await Self.eventually { !engine.isRunning })
        #expect(node.volume < 1)
    }

    @Test func aDiscardOfAPausedEngineStopsItAtOnce() throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine()
        player.adopt(engine, node, started: true)
        try player.start(node)
        player.pause()
        player.discard()
        #expect(!engine.isRunning)
    }

    @Test func aDiscardOfASilentEngineStopsItAtOnce() throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine()
        player.adopt(engine, node, started: false)
        player.discard()
        #expect(!engine.isRunning)
    }

    @Test func aStartFadesInFromSilence() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine()
        player.adopt(engine, node, started: true)
        try player.start(node)
        #expect(node.isPlaying)
        #expect(node.volume == 0)
        #expect(await Self.eventually { node.volume == 1 })
        player.discard()
    }

    @Test func aSecondStartOfAPlayingNodeKeepsItsLevel() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine()
        player.adopt(engine, node, started: true)
        try player.start(node)
        #expect(await Self.eventually { node.volume == 1 })
        try player.start(node)
        #expect(node.volume == 1)
        player.discard()
    }

    @Test func aDiscardDuringTheFadeInStopsTheEngineWithoutRaisingTheLevel() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine()
        player.adopt(engine, node, started: true)
        try player.start(node)
        player.discard()
        #expect(await Self.eventually { !engine.isRunning })
        #expect(node.volume == 0)
    }
}
