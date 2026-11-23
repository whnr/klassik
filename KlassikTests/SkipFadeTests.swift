import AVFoundation
import Testing

@testable import Klassik

/// A skip stops one waveform and starts another in the middle of a cycle. The tests render the ramp of
/// `SkipFade` offline, with the same gain steps and step time as the engine, and look for jumps between samples.
@Suite(.serialized)
@MainActor
struct SkipFadeTests {
    static let sampleRate = 44_100.0
    /// The sine of the test has amplitude 0.5. Its own largest step is 0.5 × 2π × 300 / 44100 ≈ 0.021, and a gain
    /// step of `SkipFade.maximumStep` adds at most 0.055. Anything above this is an audible click.
    static let threshold: Float = 0.09
    static let amplitude: Float = 0.5
    /// One gain step lasts this many frames.
    static let block = 88

    /// Renders a sine from the given phase offset, in frames. `steps` change the node volume between blocks.
    /// `before` frames play at the volume `from`, then each gain of `gains` plays for one block, then `after`
    /// frames play at the last gain.
    static func render(
        hertz: Double, phase: Int, from: Float, gains: [Float], before: Int = 2000, after: Int = 2000
    ) throws -> [Float] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let total = before + gains.count * block + after
        let wave = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)))
        wave.frameLength = AVAudioFrameCount(total)
        for frame in 0..<total {
            wave.floatChannelData![0][frame] =
                amplitude * Float(sin(2 * .pi * hertz * Double(frame + phase) / sampleRate))
        }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        defer { engine.stop() }
        node.volume = from
        node.scheduleBuffer(wave, at: nil, options: [], completionHandler: nil)
        node.play()
        let out = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var samples: [Float] = []
        func advance(_ frames: Int) throws {
            guard try engine.renderOffline(AVAudioFrameCount(frames), to: out) == .success else { return }
            samples += UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))
        }
        try advance(before)
        for gain in gains {
            node.volume = gain
            try advance(block)
        }
        try advance(after)
        return samples
    }

    static func largestJump(_ samples: [Float]) -> Float {
        zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
    }

    @Test func theRampsReachTheirTargetsWithSmallSteps() {
        for rising in [true, false] {
            let gains = SkipFade.gains(rising: rising)
            #expect(gains.last == (rising ? 1 : 0))
            var previous: Float = rising ? 0 : 1
            for gain in gains {
                #expect(abs(gain - previous) <= SkipFade.maximumStep)
                #expect(rising ? gain >= previous : gain <= previous)
                previous = gain
            }
        }
        #expect(Double(SkipFade.steps) * 0.002 == SkipFade.seconds)
    }

    @Test func aHardStopInsideAWaveJumpsAboveTheThreshold() throws {
        // The control: the same wave, cut without a ramp, at a phase that is far from a zero crossing.
        let cut = try Self.render(hertz: 300, phase: 0, from: 1, gains: [0])
        #expect(Self.largestJump(cut) > Self.threshold)
    }

    @Test func aFadeOutLeavesNoJump() throws {
        let faded = try Self.render(hertz: 300, phase: 0, from: 1, gains: SkipFade.gains(rising: false))
        #expect(Self.largestJump(faded) <= Self.threshold)
        #expect(abs(faded.last ?? 1) < 0.001)
    }

    @Test func aStartInsideAWaveLeavesNoJump() throws {
        // A seek starts the wave at frame 2000 of its cycle, not at a zero crossing.
        let uncut = try Self.render(hertz: 300, phase: 2000, from: 1, gains: [], before: 2000, after: 2000)
        let started = try Self.render(hertz: 300, phase: 2000, from: 0, gains: SkipFade.gains(rising: true))
        #expect(Self.largestJump(started) <= Self.threshold)
        #expect(abs(started.first ?? 1) < 0.001)
        #expect(Self.largestJump(uncut) <= Self.threshold)
    }

    @Test func aSkipToAnotherWorkLeavesNoJump() throws {
        // The old work fades out, a silent wait follows while the next file loads, the new work fades in mid-wave
        // at another pitch.
        let old = try Self.render(hertz: 300, phase: 0, from: 1, gains: SkipFade.gains(rising: false), after: 0)
        let new = try Self.render(
            hertz: 440, phase: 777, from: 0, gains: SkipFade.gains(rising: true), before: 0, after: 2000)
        let joined = old + Array(repeating: 0, count: 4000) + new
        #expect(Self.largestJump(joined) <= Self.threshold)
    }
}
