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
        // An offline node keeps no play state, so the engine's own stop point shows the pause.
        let player = GaplessEngine(manualRendering: true, fadeSeconds: 0.05)
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        player.pause()
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20))
        #expect(player.pausedAt == nil)
        #expect(await Self.eventually { player.pausedAt != nil })
        player.discard()
    }

    @Test func aResumeDuringThePauseFadeRampsUpAgainAndKeepsPlaying() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine(manualRendering: true, fadeSeconds: 0.05)
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        player.pause()
        try player.start(node)
        #expect(fade.last == .init(from: nil, target: 1, frames: Self.rate / 20))
        try? await Task.sleep(for: .milliseconds(150))
        #expect(player.pausedAt == nil)
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
        #expect(player.pausedAt == nil)
        #expect(await Self.eventually { player.pausedAt != nil })
        player.discard()
    }

    /// The fade-out of a stall ends at the audio that is left. Audio that arrives before the node pauses plays at once,
    /// so it must neither stay muted nor be cut by the pause.
    @Test func audioThatArrivesDuringAStarvationStopPlaysAndKeepsTheNodeRunning() async throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine(manualRendering: true, fadeSeconds: 0.1)
        player.adopt(engine, node, started: true, fade: fade, scheduledEnd: 1000, decoding: true)
        try player.start(node)
        player.checkStarvation()
        #expect(fade.last == .init(from: nil, target: 0, frames: 1000))
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        player.enqueue(buffer, position: 0, audioStart: 0, last: false, generation: 0)
        #expect(fade.last == .init(from: nil, target: 1, frames: Self.rate / 10))
        try? await Task.sleep(for: .milliseconds(300))
        #expect(player.pausedAt == nil)
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

    /// What the source closure of a load saw when the new load asked for its first track.
    @MainActor private final class Probe {
        var oldEngineRunning: Bool?
    }

    private static func sounding(_ options: FadeOptions) throws -> (
        player: GaplessEngine, old: AVAudioEngine, fade: FadeControl
    ) {
        let (engine, node) = try graph()
        let fade = FadeControl()
        let player = GaplessEngine(manualRendering: true)
        player.fadeOptions = options
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        return (player, engine, fade)
    }

    private static func load(_ player: GaplessEngine, old: AVAudioEngine, probe: Probe) {
        player.load([PlaybackTrack(id: "a")], from: 0, offset: 0) { _ in
            probe.oldEngineRunning = old.isRunning
            throw CancellationError()
        }
    }

    private static let fiftyMilliseconds = FadeOptions(outSeconds: 0.05, inSeconds: 0.05)

    /// The today mode asks for the new track while the old sound still fades out, so the two can overlap.
    @Test func aLoadInTheTodayModeFadesTheOldSoundOutAndAsksForTheNewTrackAtOnce() async throws {
        let (player, old, fade) = try Self.sounding(Self.fiftyMilliseconds)
        defer { old.stop() }
        let probe = Probe()
        Self.load(player, old: old, probe: probe)
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20))
        #expect(await Self.eventually { probe.oldEngineRunning != nil })
        #expect(probe.oldEngineRunning == true)
        #expect(await Self.eventually { !old.isRunning })
        player.discard()
    }

    /// The silence mode builds the new graph only after the old engine stopped and the gap passed.
    @Test func aLoadInTheSilenceModeWaitsUntilTheOldSoundStoppedAndTheGapPassed() async throws {
        var options = Self.fiftyMilliseconds
        options.seek = .silence(seconds: 0.05)
        let (player, old, fade) = try Self.sounding(options)
        defer { old.stop() }
        let probe = Probe()
        let start = ContinuousClock.now
        Self.load(player, old: old, probe: probe)
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20))
        #expect(await Self.eventually { probe.oldEngineRunning != nil })
        #expect(probe.oldEngineRunning == false)
        // The fade-out and the stop margin take 80 ms, and the gap adds 50 ms.
        #expect(ContinuousClock.now - start >= .milliseconds(125))
        player.discard()
    }

    @Test func aLoadInTheSilenceModeOverASilentEngineDoesNotWait() async throws {
        var options = Self.fiftyMilliseconds
        options.seek = .silence(seconds: 0.3)
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine(manualRendering: true)
        player.fadeOptions = options
        player.adopt(engine, node, started: false, fade: FadeControl())
        let probe = Probe()
        let start = ContinuousClock.now
        Self.load(player, old: engine, probe: probe)
        #expect(await Self.eventually { probe.oldEngineRunning != nil })
        #expect(ContinuousClock.now - start < .milliseconds(250))
        player.discard()
    }

    /// The crossfade mode leaves the old sound alone until the new graph sounds, then both ramp with equal power
    /// over the length of the fade-out.
    @Test func aLoadInTheCrossfadeModeKeepsTheOldSoundUntilTheNewOneIsReady() async throws {
        var options = Self.fiftyMilliseconds
        options.seek = .crossfade
        let (player, old, fade) = try Self.sounding(options)
        defer { old.stop() }
        let before = fade.last
        let probe = Probe()
        Self.load(player, old: old, probe: probe)
        #expect(await Self.eventually { probe.oldEngineRunning != nil })
        try? await Task.sleep(for: .milliseconds(200))
        #expect(probe.oldEngineRunning == true)
        #expect(old.isRunning)
        #expect(fade.last == before)

        // The new graph is ready.
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let incoming = FadeControl()
        player.adopt(engine, node, started: false, fade: incoming)
        try player.start(node)
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20, curve: .equalPower))
        #expect(incoming.last == .init(from: 0, target: 1, frames: Self.rate / 20, curve: .equalPower))
        #expect(await Self.eventually { !old.isRunning })
        player.discard()
    }

    @Test func aDiscardDuringTheWaitForTheNewSoundFadesTheOldSoundOutAndStopsIt() async throws {
        var options = Self.fiftyMilliseconds
        options.seek = .crossfade
        options.outCurve = .smootherstep
        let (player, old, fade) = try Self.sounding(options)
        defer { old.stop() }
        Self.load(player, old: old, probe: Probe())
        #expect(old.isRunning)
        player.discard()
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20, curve: .smootherstep))
        #expect(await Self.eventually { !old.isRunning })
    }

    @Test func aPauseDuringTheWaitForTheNewSoundFadesTheOldSoundOut() async throws {
        var options = Self.fiftyMilliseconds
        options.seek = .crossfade
        let (player, old, fade) = try Self.sounding(options)
        defer { old.stop() }
        Self.load(player, old: old, probe: Probe())
        player.pause()
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20))
        #expect(await Self.eventually { !old.isRunning })
        player.discard()
    }

    @Test func aLoadInTheCrossfadeModeOverASilentEngineStopsItAtOnce() throws {
        var options = Self.fiftyMilliseconds
        options.seek = .crossfade
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let player = GaplessEngine(manualRendering: true)
        player.fadeOptions = options
        player.adopt(engine, node, started: false, fade: FadeControl())
        Self.load(player, old: engine, probe: Probe())
        #expect(!engine.isRunning)
        player.discard()
    }

    @Test func theFadeOutAndFadeInUseTheirOwnCurvesAndLengths() throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine(manualRendering: true)
        player.fadeOptions = FadeOptions(
            outCurve: .equalPower, inCurve: .smootherstep, outSeconds: 0.05, inSeconds: 0.1)
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        #expect(fade.last == .init(from: 0, target: 1, frames: Self.rate / 10, curve: .smootherstep))
        player.pause()
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20, curve: .equalPower))
        player.discard()
    }
}
