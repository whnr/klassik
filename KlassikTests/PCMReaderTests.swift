import AVFoundation
import Testing

@testable import KlassikEngine

struct PCMReaderTests {
    private func buffer(_ format: AVAudioFormat, from start: Int, count: Int) throws -> AVAudioPCMBuffer {
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)))
        buffer.frameLength = UInt32(count)
        for channel in 0..<Int(format.channelCount) {
            for index in 0..<count {
                buffer.floatChannelData![channel][index] = Float(sin(Double(start + index) * 0.37 + Double(channel)))
            }
        }
        return buffer
    }

    /// The decoder's chunk size must change neither the samples nor the length.
    @Test(arguments: [(44_100.0, 1), (96_000.0, 2), (192_000.0, 2)])
    func readingKeepsTheSamplesOfTheFile(rate: Double, channels: Int) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: UInt32(channels)))
        let length = 48_017
        func read(chunk: Int) throws -> [[Float]] {
            var cursor = 0
            let reader = PCMReader(format: format, frames: Int64(length)) { requested in
                guard cursor < length else { return nil }
                let count = min(Int(requested), chunk, length - cursor)
                defer { cursor += count }
                return try buffer(format, from: cursor, count: count)
            }
            var samples = Array(repeating: [Float](), count: channels)
            while let part = try reader.read(frames: 4096) {
                for channel in 0..<channels {
                    samples[channel] += Array(
                        UnsafeBufferPointer(start: part.floatChannelData![channel], count: Int(part.frameLength)))
                }
            }
            return samples
        }
        let whole = try buffer(format, from: 0, count: length)
        let small = try read(chunk: 127)
        #expect(small == (try read(chunk: 4096)))
        for channel in 0..<channels {
            let expected = Array(UnsafeBufferPointer(start: whole.floatChannelData![channel], count: length))
            #expect(small[channel] == expected)
        }
    }

    @Test func sourceErrorsReachTheScheduler() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let reader = PCMReader(format: format, frames: nil) { _ in throw TrackTransfer.Failure.storage }
        #expect(throws: TrackTransfer.Failure.storage) { try reader.read(frames: 128) }
    }

    @Test func reachingTheDeclaredLengthStillValidatesSourceEOF() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        var supplied = false
        let reader = PCMReader(format: format, frames: 1) { _ in
            guard !supplied else { throw StreamDecoder.Failure.prematureEnd(expected: 2, actual: 1) }
            supplied = true
            return try buffer(format, from: 0, count: 1)
        }
        #expect(try reader.read(frames: 1)?.frameLength == 1)
        #expect(throws: StreamDecoder.Failure.prematureEnd(expected: 2, actual: 1)) { try reader.read(frames: 1) }
    }

    @Test func aSourceThatEndsBeforeTheDeclaredLengthFails() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        var supplied = false
        let reader = PCMReader(format: format, frames: 10) { _ in
            guard !supplied else { return nil }
            supplied = true
            return try buffer(format, from: 0, count: 4)
        }
        #expect(try reader.read(frames: 8)?.frameLength == 4)
        #expect(throws: PCMReader.Failure.prematureEnd(expected: 10, actual: 4)) { try reader.read(frames: 8) }
    }

    @Test func aBufferPastTheDeclaredLengthIsCut() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        var cursor = 0
        let reader = PCMReader(format: format, frames: 6) { _ in
            defer { cursor += 4 }
            return cursor < 8 ? try buffer(format, from: cursor, count: 4) : nil
        }
        #expect(try reader.read(frames: 4)?.frameLength == 4)
        #expect(try reader.read(frames: 4)?.frameLength == 2)
        #expect(try reader.read(frames: 4) == nil)
    }
}
