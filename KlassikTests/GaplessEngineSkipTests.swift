import AVFoundation
import Testing

@testable import Klassik
@testable import KlassikEngine

/// The engine ramps a skip, a pause and an underrun on the samples: a discard of a sounding engine stops it after
/// the fade-out, and a start fades in. The graph is real and renders offline. The tests read the ramp that the
/// engine asks the fade stage for, and the engine state.
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

    private static let rate = 44_100

    @Test func aDiscardOfASoundingEngineFadesOutThenStopsIt() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine(fadeSeconds: 0.05)
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        player.discard()
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20))
        #expect(engine.isRunning)
        #expect(await Self.eventually { !engine.isRunning })
    }

    /// A paused node is the same case: `pause()` waits for a render thread that an offline graph does not run.
    @Test func aDiscardOfAStoppedNodeStopsTheEngineAtOnce() throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine()
        player.adopt(engine, node, started: true, fade: FadeControl())
        #expect(!node.isPlaying)
        player.discard()
        #expect(!engine.isRunning)
    }

    @Test func aDiscardOfASilentEngineStopsItAtOnce() throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine()
        player.adopt(engine, node, started: false, fade: FadeControl())
        player.discard()
        #expect(!engine.isRunning)
    }

    @Test func aStartFadesInFromSilenceOverTheSetLength() throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine(fadeSeconds: 0.3)
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        #expect(node.isPlaying)
        #expect(fade.last == .init(from: 0, target: 1, frames: Self.rate * 3 / 10))
        player.discard()
    }

    @Test func aSecondStartOfAPlayingNodeAsksForNoRamp() throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine()
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        let first = fade.last
        try player.start(node)
        #expect(fade.last == first)
        player.discard()
    }

    @Test func aPauseFadesOutBeforeTheNodeStops() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine(fadeSeconds: 0.05)
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        player.pause()
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20))
        #expect(node.isPlaying)
        #expect(await Self.eventually { !node.isPlaying })
        player.discard()
    }

    @Test func aResumeDuringThePauseFadeRampsUpAgainAndKeepsPlaying() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine(fadeSeconds: 0.05)
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        player.pause()
        try player.start(node)
        #expect(fade.last == .init(from: nil, target: 1, frames: Self.rate / 20))
        try? await Task.sleep(for: .milliseconds(150))
        #expect(node.isPlaying)
        player.discard()
    }

    @Test func aStarvationStopFadesOutOverTheAudioThatIsLeft() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        // The offline engine reports its pumped frames as the position, which is 0 here: 1000 frames are left.
        let player = GaplessEngine(manualRendering: true, fadeSeconds: 0.1)
        player.adopt(engine, node, started: true, fade: fade, scheduledEnd: 1000, decoding: true)
        try player.start(node)
        player.checkStarvation()
        #expect(fade.last == .init(from: nil, target: 0, frames: 1000))
        #expect(node.isPlaying)
        #expect(await Self.eventually { !node.isPlaying })
        player.discard()
    }

    @Test func aNodeWithPlentyOfAudioLeftIsNotStopped() throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine(manualRendering: true, fadeSeconds: 0.1)
        player.adopt(engine, node, started: true, fade: fade, scheduledEnd: Int64(Self.rate * 5), decoding: true)
        try player.start(node)
        let first = fade.last
        player.checkStarvation()
        #expect(fade.last == first)
        #expect(node.isPlaying)
        player.discard()
    }
}
