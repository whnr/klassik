import AVFoundation

/// Carries fractional output frames across tracks, so rounding never adds a frame at every movement boundary.
struct ConvertedFrameCount {
    private var remainder = 0.0

    mutating func frames(_ input: Int64, from source: Double, to target: Double) -> Int64 {
        let exact = Double(input) * target / source + remainder
        let result = exact.rounded()
        remainder = exact - result
        return Int64(result)
    }
}

/// Converts already trimmed PCM on the decoder worker. A single instance retains the resampler state within a track.
final class PCMConversion: @unchecked Sendable {
    typealias Read = (AVAudioFrameCount) throws -> AVAudioPCMBuffer?

    enum Failure: LocalizedError {
        case format
        case allocation
        case conversion
        case prematureEnd(expected: Int64, actual: Int64)

        var errorDescription: String? {
            switch self {
            case .format: "The audio formats cannot be converted."
            case .allocation: "This iPhone cannot allocate an audio buffer."
            case .conversion: "This iPhone could not convert the audio."
            case .prematureEnd(let expected, let actual):
                "Audio conversion ended after \(actual) of \(expected) frames."
            }
        }
    }

    let format: AVAudioFormat
    private let inputFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let source: Read
    private let expected: Int64?
    private var emitted: Int64 = 0
    private var inputEnded = false

    init(from input: AVAudioFormat, to output: AVAudioFormat, frames: Int64?, read: @escaping Read) throws {
        format = output
        inputFormat = input
        source = read
        expected = frames
        if input == output {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: output) else { throw Failure.format }
            // Normal priming has zero output latency. Codec priming was already removed in source coordinates.
            converter.primeMethod = .normal
            converter.downmix = true
            self.converter = converter
        }
    }

    func read(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        if let expected, emitted >= expected {
            // Output rounding can finish before the last source frame. Still validate the source's declared sample count.
            while !inputEnded {
                guard let buffer = try source(frames) else {
                    inputEnded = true
                    break
                }
                guard buffer.frameLength > 0 else { throw Failure.conversion }
            }
            return nil
        }
        guard let converter else {
            guard let buffer = try source(frames) else { return try end() }
            emitted += Int64(buffer.frameLength)
            return buffer
        }
        // Keep the converter's output capacity stable through its final flush. Trim only the emitted PCM.
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw Failure.allocation
        }
        var conversionError: NSError?
        var inputError: (any Error)?
        let status = converter.convert(to: output, error: &conversionError) { requested, status in
            guard !self.inputEnded else {
                status.pointee = .endOfStream
                return nil
            }
            do {
                if let buffer = try self.source(requested) {
                    status.pointee = .haveData
                    return buffer
                }
            } catch { inputError = error }
            self.inputEnded = true
            if inputError == nil, let expected = self.expected, self.emitted < expected {
                do {
                    // Zero extension supplies the resampler's final interpolation. The output length excludes that extension.
                    let count = max(
                        converter.primeInfo.trailingFrames,
                        AVAudioFrameCount(ceil(self.inputFormat.sampleRate / self.format.sampleRate)) + 1)
                    guard let padding = AVAudioPCMBuffer(pcmFormat: self.inputFormat, frameCapacity: count) else {
                        throw Failure.allocation
                    }
                    padding.frameLength = count
                    for buffer in UnsafeMutableAudioBufferListPointer(padding.mutableAudioBufferList) {
                        buffer.mData?.initializeMemory(as: UInt8.self, repeating: 0, count: Int(buffer.mDataByteSize))
                    }
                    status.pointee = .haveData
                    return padding
                } catch { inputError = error }
            }
            status.pointee = .endOfStream
            return nil
        }
        if let inputError { throw inputError }
        if let conversionError { throw conversionError }
        guard status != .error else { throw Failure.conversion }
        guard output.frameLength > 0 else { return try end() }
        if let expected { output.frameLength = min(output.frameLength, AVAudioFrameCount(expected - emitted)) }
        emitted += Int64(output.frameLength)
        return output
    }

    private func end() throws -> AVAudioPCMBuffer? {
        if let expected, emitted != expected { throw Failure.prematureEnd(expected: expected, actual: emitted) }
        return nil
    }
}

/// Reads a complete file in valid sample coordinates on the decoder worker.
final class FilePCMDecoder: @unchecked Sendable {
    let file: AVAudioFile
    let playable: Range<Int64>

    init(_ url: URL, playable: Range<Int64>) throws {
        file = try AVAudioFile(forReading: url)
        self.playable = playable
        file.framePosition = playable.lowerBound
    }

    func read(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        let remaining = playable.upperBound - file.framePosition
        guard remaining > 0 else { return nil }
        let count = AVAudioFrameCount(min(Int64(frames), remaining))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else {
            throw PCMConversion.Failure.allocation
        }
        try file.read(into: buffer, frameCount: count)
        guard buffer.frameLength > 0 else {
            throw PCMConversion.Failure.prematureEnd(expected: playable.upperBound, actual: file.framePosition)
        }
        return buffer
    }
}
