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

/// Converts already trimmed PCM on the decoder worker. A followable instance keeps the resampler state across
/// consecutive tracks of one source format, so a continuous join interpolates between real samples, never zeros.
final class PCMConversion: @unchecked Sendable {
    typealias Read = (AVAudioFrameCount) throws -> AVAudioPCMBuffer?

    /// One read of the current track.
    enum Output {
        case audio(AVAudioPCMBuffer)
        /// The last frames of the track need the samples that follow it. `append` or `finish` supplies them.
        case waiting
        /// The track ended at its declared frame count. The next read returns the next appended track.
        case end
    }

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
    let inputFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    /// The sources of the tracks, in order. The input reads them as one continuous signal.
    private var sources: [Read]
    private var source = 0
    /// The declared output frames of each track. `track` is the one whose frames `next` returns.
    private var lengths: [Int64?]
    private var track = 0
    private var emitted: Int64 = 0
    /// Converted frames past the end of the current track. They open the next track.
    private var overflow: AVAudioPCMBuffer?
    /// No track follows: the input ends with zero extension for the resampler's final interpolation.
    private var finishing: Bool
    private var extended = false

    /// `followable` keeps the input open at the end of the track, for `append`. Otherwise the track ends the input.
    init(
        from input: AVAudioFormat, to output: AVAudioFormat, frames: Int64?, followable: Bool = false,
        read: @escaping Read
    ) throws {
        format = output
        inputFormat = input
        sources = [read]
        lengths = [frames]
        // A track without a declared length, or one that needs no conversion, never continues into the next.
        finishing = !followable || frames == nil || input == output
        if input == output {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: output) else { throw Failure.format }
            // Normal priming has zero output latency. Codec priming was already removed in source coordinates.
            converter.primeMethod = .normal
            converter.downmix = true
            // A mono track plays in both ears of a stereo node, as the mixer upmixes a mono node.
            if input.channelCount == 1, output.channelCount > 1 {
                converter.channelMap = Array(repeating: NSNumber(value: 0), count: Int(output.channelCount))
            }
            self.converter = converter
        }
    }

    /// True when a track of `input` format can continue this resampler.
    func continues(from input: AVAudioFormat) -> Bool {
        converter != nil && !finishing && input == inputFormat
    }

    /// The next track of the same source format. Its first samples complete the interpolation of the track before.
    func append(frames: Int64, read: @escaping Read) {
        sources.append(read)
        lengths.append(frames)
    }

    /// No track follows. The last track ends with the converter's final interpolation against zeros.
    func finish() throws {
        finishing = true
        if track >= lengths.count { try validateRemainingInput() }
    }

    /// The next frames of the current track, at most `frames`, or nil at its end. A single track only.
    func read(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        switch try next(frames: frames) {
        case .audio(let buffer): return buffer
        case .end: return nil
        case .waiting: throw Failure.conversion
        }
    }

    func next(frames: AVAudioFrameCount) throws -> Output {
        guard track < lengths.count else { return .end }
        let expected = lengths[track]
        if let expected, emitted >= expected { return try endTrack() }
        if let overflow {
            self.overflow = nil
            return .audio(take(overflow))
        }
        guard let converter else {
            guard let buffer = try sources[source](frames) else {
                if let expected, emitted != expected { throw Failure.prematureEnd(expected: expected, actual: emitted) }
                source += 1
                return try endTrack()
            }
            return .audio(take(buffer))
        }
        // Keep the converter's output capacity stable through its final flush. Trim only the emitted PCM.
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw Failure.allocation
        }
        var conversionError: NSError?
        var inputError: (any Error)?
        // Converter properties take its lock. The input callback runs while conversion already holds that lock.
        let trailingFrames = converter.primeInfo.trailingFrames
        let status = converter.convert(to: output, error: &conversionError) { requested, status in
            while self.source < self.sources.count {
                do {
                    if let buffer = try self.sources[self.source](requested) {
                        status.pointee = .haveData
                        return buffer
                    }
                } catch {
                    inputError = error
                    status.pointee = .endOfStream
                    return nil
                }
                self.source += 1
            }
            guard self.finishing else {
                status.pointee = .noDataNow
                return nil
            }
            if !self.extended, self.lengths.last.flatMap({ $0 }) != nil {
                self.extended = true
                // Zero extension supplies the resampler's final interpolation. The output length excludes it.
                let count = max(
                    trailingFrames, AVAudioFrameCount(ceil(self.inputFormat.sampleRate / self.format.sampleRate)) + 1)
                guard let padding = AVAudioPCMBuffer(pcmFormat: self.inputFormat, frameCapacity: count) else {
                    inputError = Failure.allocation
                    status.pointee = .endOfStream
                    return nil
                }
                padding.frameLength = count
                for buffer in UnsafeMutableAudioBufferListPointer(padding.mutableAudioBufferList) {
                    buffer.mData?.initializeMemory(as: UInt8.self, repeating: 0, count: Int(buffer.mDataByteSize))
                }
                status.pointee = .haveData
                return padding
            }
            status.pointee = .endOfStream
            return nil
        }
        if let inputError { throw inputError }
        if let conversionError { throw conversionError }
        guard status != .error else { throw Failure.conversion }
        guard output.frameLength > 0 else {
            if status == .inputRanDry { return .waiting }
            if let expected, emitted != expected { throw Failure.prematureEnd(expected: expected, actual: emitted) }
            return try endTrack()
        }
        return .audio(take(output))
    }

    /// Returns the part of `buffer` that belongs to the current track and keeps the rest for the next one.
    private func take(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let expected = lengths[track], Int64(buffer.frameLength) > expected - emitted else {
            emitted += Int64(buffer.frameLength)
            return buffer
        }
        let count = AVAudioFrameCount(expected - emitted)
        // Frames after the last track are the converter's flush, never audio.
        if track + 1 < lengths.count || !finishing {
            overflow = Self.slice(buffer, from: count, count: buffer.frameLength - count)
        }
        buffer.frameLength = count
        emitted = expected
        return buffer
    }

    private func endTrack() throws -> Output {
        track += 1
        emitted = 0
        if track >= lengths.count && finishing {
            overflow = nil
            try validateRemainingInput()
        }
        return .end
    }

    /// Output rounding can finish before the last source frame. Still validate the source's declared sample count.
    private func validateRemainingInput() throws {
        while source < sources.count {
            guard let buffer = try sources[source](4096) else {
                source += 1
                continue
            }
            guard buffer.frameLength > 0 else { throw Failure.conversion }
        }
    }

    private static func slice(_ buffer: AVAudioPCMBuffer, from offset: AVAudioFrameCount, count: AVAudioFrameCount)
        -> AVAudioPCMBuffer?
    {
        guard count > 0, let part = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count),
            let source = buffer.floatChannelData, let target = part.floatChannelData
        else { return nil }
        part.frameLength = count
        for channel in 0..<Int(buffer.format.channelCount) {
            target[channel].update(from: source[channel].advanced(by: Int(offset)), count: Int(count))
        }
        return part
    }
}

/// Decoded PCM of one track, read on the decoder worker.
protocol PCMSource: AnyObject, Sendable {
    var format: AVAudioFormat { get }
    func read(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer?
}

/// Reads a complete file in valid sample coordinates on the decoder worker.
final class FilePCMDecoder: PCMSource, @unchecked Sendable {
    let file: AVAudioFile
    let playable: Range<Int64>
    var format: AVAudioFormat { file.processingFormat }

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
