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
}
