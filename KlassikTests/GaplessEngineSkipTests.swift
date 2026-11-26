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
        #expect(fade.last == .init(from: 0, target: 1, frames: Self.rate * 3 / 10, onSignal: true))
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
            // The open lasts until the load is replaced or discarded.
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
    }

    private struct SourceFailure: Error {}

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

    /// The silence mode starts the load at once, and only the first sound waits for the fade-out and the gap.
    @Test func aLoadInTheSilenceModeAsksForTheNewTrackAtOnceAndHoldsOnlyTheFirstSound() async throws {
        var options = Self.fiftyMilliseconds
        options.seek = .silence(seconds: 0.05)
        let (player, old, fade) = try Self.sounding(options)
        defer { old.stop() }
        let probe = Probe()
        let start = ContinuousClock.now
        Self.load(player, old: old, probe: probe)
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20))
        #expect(await Self.eventually { probe.oldEngineRunning != nil })
        #expect(ContinuousClock.now - start < .milliseconds(40))
        // The fade-out takes 50 ms and the gap adds 50 ms. The stop margin is not silence.
        let earliest = try #require(player.earliestSound)
        #expect(earliest - start >= .milliseconds(95) && earliest - start < .milliseconds(140))
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

    /// The crossfade mode leaves the old sound alone until the new graph sounds, then the old one follows the
    /// fade-out curve and the new one the fade-in curve.
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
        // Both ramps wait for the first sounding frame of the new position: the new one fires the flag, the old one
        // waits on it, and the old engine stays up until the flag is set and the fade-out is over.
        let oldCommand = try #require(fade.last)
        let newCommand = try #require(incoming.last)
        #expect(oldCommand.target == 0 && oldCommand.frames == Self.rate / 20 && oldCommand.onSignal)
        #expect(newCommand.target == 1 && newCommand.from == 0 && newCommand.onSignal)
        let trigger = try #require(newCommand.fires)
        #expect(oldCommand.after == trigger)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(old.isRunning)
        #expect(trigger.fire())
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

    @Test func aFailedLoadInTheCrossfadeModeStopsTheOldSound() async throws {
        var options = Self.fiftyMilliseconds
        options.seek = .crossfade
        let (player, old, fade) = try Self.sounding(options)
        defer { old.stop() }
        var failed = false
        player.onEvent = { event in
            if case .failed = event { failed = true }
        }
        player.load([PlaybackTrack(id: "a")], from: 0, offset: 0) { _ in throw SourceFailure() }
        #expect(await Self.eventually { failed })
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20))
        #expect(await Self.eventually { !old.isRunning })
        player.discard()
    }

    /// A second seek before the new graph sounds keeps the first old graph, stops the silent graph at once, and
    /// the first old graph still crossfades with the graph that finally sounds.
    @Test func aSecondLoadDuringTheCrossfadeWaitKeepsTheFirstOldSound() async throws {
        var options = Self.fiftyMilliseconds
        options.seek = .crossfade
        let (player, old, fade) = try Self.sounding(options)
        defer { old.stop() }
        Self.load(player, old: old, probe: Probe())

        let (silent, silentNode) = try Self.graph()
        defer { silent.stop() }
        player.adopt(silent, silentNode, started: false, fade: FadeControl())
        Self.load(player, old: old, probe: Probe())
        #expect(!silent.isRunning)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(old.isRunning)

        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let incoming = FadeControl()
        player.adopt(engine, node, started: false, fade: incoming)
        try player.start(node)
        // Both ramps wait for the first sounding frame of the new position: the new one fires the flag, the old one
        // waits on it, and the old engine stays up until the flag is set and the fade-out is over.
        let oldCommand = try #require(fade.last)
        let newCommand = try #require(incoming.last)
        #expect(oldCommand.target == 0 && oldCommand.frames == Self.rate / 20 && oldCommand.onSignal)
        #expect(newCommand.target == 1 && newCommand.from == 0 && newCommand.onSignal)
        let trigger = try #require(newCommand.fires)
        #expect(oldCommand.after == trigger)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(old.isRunning)
        #expect(trigger.fire())
        #expect(await Self.eventually { !old.isRunning })
        player.discard()
    }

    /// A second seek while the crossfade ramp runs parks the sounding graph. The first old graph retires on its own
    /// timer, and the parked graph crossfades with the next one.
    @Test func aSecondLoadDuringTheCrossfadeRampParksTheNewSoundAndRetiresTheFirstOneOnItsOwn() async throws {
        var options = Self.fiftyMilliseconds
        options.seek = .crossfade
        let (player, first, _) = try Self.sounding(options)
        defer { first.stop() }
        Self.load(player, old: first, probe: Probe())

        let (second, secondNode) = try Self.graph()
        defer { second.stop() }
        let secondFade = FadeControl()
        player.adopt(second, secondNode, started: true, fade: secondFade)
        try player.start(secondNode)
        #expect(first.isRunning)
        // The first old graph fades out with the first sound of the second one.
        #expect(try #require(secondFade.last?.fires).fire())
        Self.load(player, old: second, probe: Probe())

        #expect(await Self.eventually { !first.isRunning })
        try? await Task.sleep(for: .milliseconds(200))
        #expect(second.isRunning)

        let (third, thirdNode) = try Self.graph()
        defer { third.stop() }
        let thirdFade = FadeControl()
        player.adopt(third, thirdNode, started: false, fade: thirdFade)
        try player.start(thirdNode)
        let parked = try #require(secondFade.last)
        #expect(parked.target == 0 && parked.frames == Self.rate / 20 && parked.curve == .raisedCosine)
        #expect(try #require(thirdFade.last?.fires).fire())
        #expect(await Self.eventually { !second.isRunning })
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
        #expect(fade.last == .init(from: 0, target: 1, frames: Self.rate / 10, curve: .smootherstep, onSignal: true))
        player.pause()
        #expect(fade.last == .init(from: nil, target: 0, frames: Self.rate / 20, curve: .equalPower))
        player.discard()
    }

    /// A start after a seek asks for the chosen fade-in curve and length in every mode that starts a new graph, and
    /// the ramp waits for the first sound of the node.
    @Test(arguments: FadeCurve.allCases, [SeekMode.today, .silence(seconds: 0.1)])
    func aStartAfterASeekFadesInWithTheChosenCurve(curve: FadeCurve, mode: SeekMode) throws {
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let fade = FadeControl()
        let player = GaplessEngine(manualRendering: true)
        player.fadeOptions = FadeOptions(inCurve: curve, outSeconds: 0.15, inSeconds: 0.2, seek: mode)
        player.adopt(engine, node, started: true, fade: fade)
        try player.start(node)
        #expect(fade.last == .init(from: 0, target: 1, frames: Self.rate / 5, curve: curve, onSignal: true))
        player.discard()
    }

    /// Renders both gains of a crossfade with different curves and lengths and compares them with the formulas.
    @Test func aCrossfadeFollowsTheFadeOutCurveForTheOldSoundAndTheFadeInCurveForTheNewOne() async throws {
        var options = FadeOptions(outCurve: .decibelLinear, inCurve: .smootherstep, outSeconds: 0.05, inSeconds: 0.1)
        options.seek = .crossfade
        let (player, old, fade) = try Self.sounding(options)
        defer { old.stop() }
        let probe = Probe()
        Self.load(player, old: old, probe: probe)
        #expect(await Self.eventually { probe.oldEngineRunning != nil })
        let (engine, node) = try Self.graph()
        defer { engine.stop() }
        let incoming = FadeControl()
        player.adopt(engine, node, started: false, fade: incoming)
        try player.start(node)
        let oldCommand = try #require(fade.last)
        let newCommand = try #require(incoming.last)
        #expect(oldCommand.curve == .decibelLinear && oldCommand.frames == Self.rate / 20)
        #expect(newCommand.curve == .smootherstep && newCommand.frames == Self.rate / 10)
        let oldGains = try Self.render(oldCommand, count: Self.rate / 10, start: 1)
        let newGains = try Self.render(newCommand, count: Self.rate / 10 + 10, start: 1)
        for index in 0..<oldCommand.frames - 1 {
            let expected = Float(FadeCurve.decibelLinear.fall(Double(index + 1) / Double(oldCommand.frames)))
            #expect(abs(oldGains[index] - expected) < 1e-4, "old frame \(index)")
        }
        for index in 0..<newCommand.frames - 1 {
            let expected = Float(FadeCurve.smootherstep.rise(Double(index + 1) / Double(newCommand.frames)))
            #expect(abs(newGains[index] - expected) < 1e-4, "new frame \(index)")
        }
        #expect(oldGains[oldCommand.frames + 5] == 0)
        #expect(newGains[newCommand.frames + 5] == 1)
        player.discard()
    }

    /// The gains that a fade stage gives to a signal of ones, with the first sound at frame 0.
    private static func render(_ command: FadeControl.Command, count: Int, start: Float) throws -> [Float] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let control = FadeControl()
        control.ramp(
            from: command.from ?? start, to: command.target, frames: command.frames, curve: command.curve,
            onSignal: command.onSignal)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
        buffer.frameLength = AVAudioFrameCount(count)
        for channel in 0..<2 { for index in 0..<count { buffer.floatChannelData![channel][index] = 1 } }
        control.process(buffer.mutableAudioBufferList, frames: count)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: count))
    }

    // MARK: Rendered output

    private static let silenceThreshold: Float = 1e-4

    /// Renders the two gains of a silence-mode seek, one block at a time: the old sound fades out from frame 0, and the
    /// new node starts at the frame that `soundStart` gives. Returns the length of the silent span in frames.
    private static func silentFrames(options: FadeOptions, ready: Double) throws -> Int {
        let rate = 44_100.0
        let stopWait = options.outSeconds + FadeOptions.stopMargin
        let start = Int((options.soundStart(ready: ready, stopWait: stopWait) * rate).rounded())
        let count = start + Int(options.inSeconds * rate) + 2_000
        let old = FadeControl()
        old.ramp(to: 0, frames: Int((options.outSeconds * rate).rounded()), curve: options.outCurve)
        let new = FadeControl()
        new.ramp(
            from: 0, to: 1, frames: Int((options.inSeconds * rate).rounded()), curve: options.inCurve, onSignal: true)
        let oldMix = try render(old, ones: 0..<count, count: count)
        let newMix = try render(new, ones: start..<count, count: count)
        let mix = zip(oldMix, newMix).map { $0 + $1 }
        let quiet = mix.indices.filter { abs(mix[$0]) < silenceThreshold }
        guard let first = quiet.first, let last = quiet.last else { return 0 }
        #expect(last - first + 1 == quiet.count, "one silent span")
        return quiet.count
    }

    /// Runs a signal that is 1 inside `ones` and 0 outside through a fade stage, in blocks of 64 frames.
    private static func render(_ control: FadeControl, ones: Range<Int>, count: Int) throws -> [Float] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        var result: [Float] = []
        var done = 0
        while done < count {
            let size = min(64, count - done)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(size)))
            buffer.frameLength = AVAudioFrameCount(size)
            for channel in 0..<2 {
                for index in 0..<size { buffer.floatChannelData![channel][index] = ones.contains(done + index) ? 1 : 0 }
            }
            control.process(buffer.mutableAudioBufferList, frames: size)
            result += UnsafeBufferPointer(start: buffer.floatChannelData![0], count: size)
            done += size
        }
        return result
    }

    private static let silenceOptions = FadeOptions(
        outCurve: .equalPower, inCurve: .equalPower, outSeconds: 0.15, inSeconds: 0.15, seek: .silence(seconds: 0.1))

    /// The silence is the set gap when the new audio is ready before the fade-out and the gap end.
    @Test(arguments: [0.0, 0.05, 0.25]) func theSilenceEqualsTheGapWhenTheLoadIsFast(ready: Double) throws {
        let frames = try Self.silentFrames(options: Self.silenceOptions, ready: ready)
        #expect(abs(frames - Self.rate / 10) <= 2, "silent frames: \(frames)")
    }

    /// A slow load adds only its late part: the time after the fade-out and the gap.
    @Test func theSilenceIsTheGapPlusOnlyTheLatePartOfASlowLoad() throws {
        let frames = try Self.silentFrames(options: Self.silenceOptions, ready: 0.4)
        // The first sound can start at 0.25 s. The load is ready at 0.4 s, so 0.15 s is late: 0.1 + 0.15 s of silence.
        #expect(abs(frames - Int(0.25 * 44_100)) <= 2, "silent frames: \(frames)")
    }

    /// A crossfade starts both ramps at the first sounding frame of the new position, also when the new node sounds
    /// late, so the mix does not dip.
    @Test func aCrossfadeStartsBothRampsAtTheFirstSoundOfTheNewPosition() throws {
        let rate = 44_100
        let late = 3_000
        let count = late + rate / 10 + 400
        let trigger = FadeTrigger()
        let old = FadeControl()
        old.ramp(to: 0, frames: rate / 20, curve: .equalPower, after: trigger)
        let new = FadeControl()
        new.ramp(from: 0, to: 1, frames: rate / 20, curve: .equalPower, onSignal: true, fires: trigger)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        var oldMix: [Float] = []
        var newMix: [Float] = []
        var done = 0
        while done < count {
            let size = min(64, count - done)
            for (control, silent, into) in [(new, late, 0), (old, 0, 1)] {
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(size)))
                buffer.frameLength = AVAudioFrameCount(size)
                for channel in 0..<2 {
                    for index in 0..<size { buffer.floatChannelData![channel][index] = done + index < silent ? 0 : 1 }
                }
                control.process(buffer.mutableAudioBufferList, frames: size)
                let block = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: size))
                if into == 0 { newMix += block } else { oldMix += block }
            }
            done += size
        }
        // The old sound plays at full level until the new one starts, then follows its curve.
        // The old stage reads the flag at the start of the block in which the new one fires it.
        #expect(oldMix[0..<(late - 64)].allSatisfy { $0 == 1 })
        #expect(oldMix[late + 64 + 100] < 1)
        #expect(oldMix[late + rate / 20 + 64 + 5] == 0)
        // Equal power: the two powers add up to one, so the mix does not dip. Allow the 64 frames of block delay.
        for index in (late + 64)..<(late + rate / 20) {
            let power = oldMix[index] * oldMix[index] + newMix[index] * newMix[index]
            #expect(abs(power - 1) < 0.05, "frame \(index): \(power)")
        }
    }

    /// A seek in the silence mode, dB-linear fade-out: the level of the rendered output follows the curve at 25, 50
    /// and 75 percent of the fade. The engine's own load asks for the fade-out of a real graph with the fade stage.
    @Test func aSilenceModeSeekFallsEvenlyInDecibels() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let made = try #require(FadeAudioUnit.make())
        engine.attach(node)
        engine.attach(made.stage)
        try engine.connectNode(node, to: made.stage, format: format)
        try engine.connectNode(made.stage, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1_024)
        try engine.start()
        defer { engine.stop() }
        let seconds = 4
        let capacity = AVAudioFrameCount(seconds * 44_100)
        let audio = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity))
        audio.frameLength = capacity
        for channel in 0..<2 {
            for index in 0..<Int(capacity) { audio.floatChannelData![channel][index] = 0.5 }
        }
        node.scheduleBuffer(audio, completionHandler: nil)

        let player = GaplessEngine(manualRendering: true)
        player.fadeOptions = FadeOptions(
            outCurve: .decibelLinear, inCurve: .equalPower, outSeconds: 0.15, inSeconds: 0.05,
            seek: .silence(seconds: 0.1))
        player.adopt(engine, node, started: true, fade: made.control)
        try player.start(node)

        let output = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1_024))
        func render(blocks: Int) throws -> [Float] {
            var result: [Float] = []
            for _ in 0..<blocks {
                #expect(try engine.renderOffline(1_024, to: output) == .success)
                result += UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
            }
            return result
        }
        var samples = try render(blocks: 8)
        #expect(abs(samples.last! - 0.5) < 1e-4, "the fade-in is over")
        let loadAt = samples.count
        Self.load(player, old: engine, probe: Probe())
        samples += try render(blocks: 10)
        let length = Self.rate * 15 / 100
        for progress in [0.25, 0.5, 0.75] {
            let level = samples[loadAt + Int(progress * Double(length)) - 1] / 0.5
            let decibels = 20 * log10(Double(level))
            #expect(abs(decibels - FadeCurve.floorDecibels * progress) < 1, "\(progress): \(decibels) dB")
        }
        player.discard()
    }
}
