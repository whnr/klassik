import AVFoundation
import Testing

@testable import Klassik

struct PCMConversionTests {
    @Test func fractionalFramesAccumulateAcrossTheQueue() {
        var count = ConvertedFrameCount()
        let total = (0..<1000).reduce(Int64(0)) { frames, _ in frames + count.frames(100, from: 44_100, to: 48_000) }
        #expect(total == Int64((100_000.0 * 48_000 / 44_100).rounded()))
    }

    /// Changing decoder chunk sizes must not change converted samples, length, or resampler latency.
    @Test(arguments: [(44_100.0, 48_000.0, 1, 2), (48_000.0, 44_100.0, 2, 1)])
    func resamplingIsIndependentOfInputChunks(
        sourceRate: Double, targetRate: Double, channels: Int, outputChannels: Int
    ) throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: UInt32(channels)))
        let output = try #require(
            AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: UInt32(outputChannels)))
        let length = 48_017
        func converted(chunk: Int) throws -> [[Float]] {
            var cursor = 0
            let expected = Int64((Double(length) * targetRate / sourceRate).rounded())
            let converter = try PCMConversion(from: input, to: output, frames: expected) { requested in
                guard cursor < length else { return nil }
                let count = min(Int(requested), chunk, length - cursor)
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: UInt32(count)))
                buffer.frameLength = UInt32(count)
                for channel in 0..<channels {
                    for index in 0..<count {
                        buffer.floatChannelData![channel][index] = Float(
                            sin(Double(cursor + index) * 2 * .pi * 440 / sourceRate) * 0.25)
                    }
                }
                cursor += count
                return buffer
            }
            var samples = Array(repeating: [Float](), count: outputChannels)
            while let buffer = try converter.read(frames: 4096) {
                for channel in 0..<outputChannels {
                    samples[channel] += Array(
                        UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
                }
            }
            #expect(samples[0].count == expected)
            if outputChannels == 2 { #expect(samples[0] == samples[1]) }
            return samples
        }
        #expect(try converted(chunk: 127) == converted(chunk: 4096))
    }

    @Test(arguments: [(44_100.0, 48_000.0), (48_000.0, 44_100.0), (32_000.0, 44_100.0)])
    func resamplingRetainsTheImpulsePosition(sourceRate: Double, targetRate: Double) throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 1))
        let output = try #require(AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: 1))
        let length = 8_017
        let impulse = 2_048
        var cursor = 0
        let expected = Int64((Double(length) * targetRate / sourceRate).rounded())
        let converter = try PCMConversion(from: input, to: output, frames: expected) { requested in
            guard cursor < length else { return nil }
            let count = min(Int(requested), length - cursor)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: UInt32(count)))
            buffer.frameLength = UInt32(count)
            for index in 0..<count { buffer.floatChannelData![0][index] = cursor + index == impulse ? 1 : 0 }
            cursor += count
            return buffer
        }
        var samples: [Float] = []
        while let buffer = try converter.read(frames: 127) {
            samples += Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
        let peak = try #require(samples.indices.max { abs(samples[$0]) < abs(samples[$1]) })
        #expect(samples.count == expected)
        #expect(abs(Double(peak) - Double(impulse) * targetRate / sourceRate) <= 1)
        print("conversion impulse: \(sourceRate) -> \(targetRate), frames=\(samples.count), peak=\(peak)")
    }

    @Test func sourceErrorsReachTheScheduler() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let output = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let converter = try PCMConversion(from: input, to: output, frames: nil) { _ in
            throw TrackTransfer.Failure.storage
        }
        #expect(throws: TrackTransfer.Failure.storage) { try converter.read(frames: 128) }
    }

    @Test(arguments: [(44_100.0, 48_000.0, 8_017), (32_000.0, 44_100.0, 16_013)])
    func theFinalFrameMatchesAZeroExtendedReference(sourceRate: Double, targetRate: Double, length: Int) throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 1))
        let output = try #require(AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: 1))
        let expected = Int64((Double(length) * targetRate / sourceRate).rounded())
        func converted(extensionFrames: Int, declared: Int64?) throws -> [Float] {
            var cursor = 0
            let converter = try PCMConversion(from: input, to: output, frames: declared) { requested in
                guard cursor < length + extensionFrames else { return nil }
                let count = min(Int(requested), length + extensionFrames - cursor)
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: UInt32(count)))
                buffer.frameLength = UInt32(count)
                for sample in 0..<count {
                    let index = cursor + sample
                    buffer.floatChannelData![0][sample] =
                        index < length ? Float(sin(Double(index) * 2 * .pi * 440 / sourceRate) * 0.25) : 0
                }
                cursor += count
                return buffer
            }
            var samples: [Float] = []
            while let buffer = try converter.read(frames: 127) {
                samples += Array(
                    UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            }
            return samples
        }
        let finite = try converted(extensionFrames: 0, declared: expected)
        let reference = try converted(extensionFrames: 1024, declared: nil)
        #expect(finite.count == expected)
        #expect(reference.count >= finite.count)
        let error = zip(finite, reference).map { abs($0 - $1) }.max() ?? .infinity
        #expect(error < 0.000001)
    }
}
