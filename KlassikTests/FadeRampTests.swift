import AVFoundation
import Testing

@testable import KlassikEngine

/// The fade runs on the samples: one gain for each frame, over the set length, whatever the block size.
@Suite(.serialized)
struct FadeRampTests {
    static let rate = 44_100.0

    private static func frames(milliseconds: Double) -> Int { Int((milliseconds / 1000 * rate).rounded()) }

    /// The gain that a raised-cosine ramp has after `done` of `length` frames.
    private static func expected(_ done: Int, of length: Int, from: Float, to: Float) -> Float {
        from + (to - from) * Float(0.5 - 0.5 * cos(Double.pi * Double(done) / Double(length)))
    }

    private static func fadedOnes(count: Int, from: Float? = nil, to: Float, frames: Int) -> [Float] {
        var ramp = FadeRamp()
        ramp.start(from: from, to: to, frames: frames)
        var samples = [Float](repeating: 1, count: count)
        samples.withUnsafeMutableBufferPointer { ramp.apply(to: $0) }
        return samples
    }

    @Test(arguments: [0.0, 100.0, 300.0]) func aFadeOutFollowsTheCurveOverTheSetLength(milliseconds: Double) {
        let length = Self.frames(milliseconds: milliseconds)
        let samples = Self.fadedOnes(count: length + 500, to: 0, frames: length)
        for index in 0..<length {
            #expect(abs(samples[index] - Self.expected(index + 1, of: length, from: 1, to: 0)) < 1e-5)
        }
        // After the set length, the sound stays silent, and the length is exact.
        for index in length..<samples.count { #expect(samples[index] == 0) }
        if length > 0 { #expect(samples[length - 1] == 0) }
        if length > 1 { #expect(samples[length - 2] >= 0) }
        if length > 1 { #expect(samples[length / 2] > 0) }
    }

    @Test func aFadeInStartsAtTheOriginAndEndsAtFullLevel() {
        let length = Self.frames(milliseconds: 100)
        let samples = Self.fadedOnes(count: length + 10, from: 0, to: 1, frames: length)
        #expect(samples[0] < 1e-3)
        #expect(samples[length - 1] == 1)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $1 >= $0 })
    }

    @Test func theLargestStepShrinksAsTheFadeGrowsLonger() {
        func step(_ milliseconds: Double) -> Float {
            let length = Self.frames(milliseconds: milliseconds)
            let samples = Self.fadedOnes(count: length, to: 0, frames: length)
            return zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        }
        #expect(step(100) < 0.001)
        #expect(step(300) < step(100))
    }

    @Test func aNewRampStartsFromTheLevelThatTheLastOneReached() {
        var ramp = FadeRamp()
        ramp.start(to: 0, frames: 1000)
        for _ in 0..<500 { _ = ramp.next() }
        let middle = ramp.gain
        #expect(middle > 0 && middle < 1)
        ramp.start(to: 1, frames: 1000)
        #expect(ramp.gain == middle)
    }

    @Test func theBlockSizeDoesNotChangeTheShape() throws {
        let length = Self.frames(milliseconds: 100)
        let whole = Self.fadedOnes(count: 5000, to: 0, frames: length)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2))
        let control = FadeControl()
        control.ramp(to: 0, frames: length)
        var blocks: [Float] = []
        for size in [64, 480, 1024, 2000, 1432] {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(size)))
            buffer.frameLength = AVAudioFrameCount(size)
            for channel in 0..<2 { for index in 0..<size { buffer.floatChannelData![channel][index] = 1 } }
            control.process(buffer.mutableAudioBufferList, frames: size)
            blocks += UnsafeBufferPointer(start: buffer.floatChannelData![1], count: size)
        }
        #expect(blocks.count == whole.count)
        for index in whole.indices { #expect(abs(blocks[index] - whole[index]) < 1e-5) }
    }

    /// The same ramp through a real graph: player node, the fade stage, the mixer, rendered offline.
    @Test func theFadeStageRampsTheAudioOfARealGraph() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2))
        let made = try #require(FadeAudioUnit.make())
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.attach(made.stage)
        try engine.connectNode(node, to: made.stage, format: format)
        try engine.connectNode(made.stage, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try engine.start()
        defer { engine.stop() }
        let total = 8000
        let wave = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)))
        wave.frameLength = AVAudioFrameCount(total)
        for channel in 0..<2 { for index in 0..<total { wave.floatChannelData![channel][index] = 0.5 } }
        node.scheduleBuffer(wave, at: nil, options: [], completionHandler: nil)
        let length = 4410
        made.control.ramp(from: 1, to: 0, frames: length)
        try node.playAudio()
        let out = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        var samples: [Float] = []
        while samples.count < total {
            let status = try engine.renderOffline(512, to: out)
            #expect(status == .success, "offline render status \(status.rawValue)")
            guard status == .success else { break }
            samples += UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))
        }
        #expect(samples.count >= total)
        #expect(samples[length + 100] == 0)
        #expect(abs(samples[length / 2] - 0.25) < 0.02)
        #expect(samples[10] > 0.49)
    }
    /// The node can begin to play after the ramp was asked for: the fade-in then still starts at the first sample
    /// with sound, follows the curve and ends after the set length.
    @Test(arguments: FadeCurve.allCases, [0, 700, 6_000])
    func aFadeInStartsAtTheFirstSoundOfAGraphThatStartedPlayingLate(curve: FadeCurve, silentFrames: Int) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2))
        let made = try #require(FadeAudioUnit.make())
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.attach(made.stage)
        try engine.connectNode(node, to: made.stage, format: format)
        try engine.connectNode(made.stage, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try engine.start()
        defer { engine.stop() }
        let length = Self.frames(milliseconds: 150)
        let total = 20_000
        let wave = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)))
        wave.frameLength = AVAudioFrameCount(total)
        for channel in 0..<2 { for index in 0..<total { wave.floatChannelData![channel][index] = 0.5 } }
        node.scheduleBuffer(wave, at: nil, options: [], completionHandler: nil)
        made.control.ramp(from: 0, to: 1, frames: length, curve: curve, onSignal: true)
        let out = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        var rendered = 0
        while rendered < silentFrames {
            let status = try engine.renderOffline(512, to: out)
            #expect(status == .success, "offline render status \(status.rawValue)")
            rendered += Int(out.frameLength)
        }
        try node.playAudio()
        var samples: [Float] = []
        while samples.count < length + 2_000 {
            let status = try engine.renderOffline(512, to: out)
            #expect(status == .success, "offline render status \(status.rawValue)")
            guard status == .success else { break }
            samples += UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))
        }
        let first = try #require(samples.firstIndex { $0 != 0 })
        #expect(first < 512)
        // The first sample is at the level of the first frame of the curve, never at full gain.
        #expect(samples[first] < 0.01)
        for index in stride(from: 0, to: length, by: 97) {
            let level = Float(0.5 * curve.rise(Double(index + 1) / Double(length)))
            #expect(abs(samples[first + index] - level) < 2e-3, "frame \(index) of \(curve.rawValue)")
        }
        #expect(samples[first + length + 10] == 0.5)
    }

    @Test func aWaitingRampHoldsItsFirstGainUntilReleased() {
        var ramp = FadeRamp()
        ramp.start(from: 0, to: 1, frames: 100, waiting: true)
        #expect(!ramp.isIdle)
        for _ in 0..<500 { #expect(ramp.next() == 0) }
        ramp.release()
        #expect(ramp.next() > 0)
        for _ in 0..<99 { _ = ramp.next() }
        #expect(ramp.gain == 1 && ramp.isIdle)
    }
}
