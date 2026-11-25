import AVFoundation

/// Reads the decoded PCM of one track up to its declared frame count. It never converts: the samples keep the
/// rate and channel count of the file (sz-u8f4). Only the system converts, when the output cannot run at that rate.
final class PCMReader: @unchecked Sendable {
    typealias Read = (AVAudioFrameCount) throws -> AVAudioPCMBuffer?

    /// One read of the track.
    enum Output {
        case audio(AVAudioPCMBuffer)
        /// The track ended at its declared frame count.
        case end
    }

    enum Failure: LocalizedError, Equatable {
        case format
        case allocation
        case prematureEnd(expected: Int64, actual: Int64)

        var errorDescription: String? {
            switch self {
            case .format: "The audio format cannot be played."
            case .allocation: "This iPhone cannot allocate an audio buffer."
            case .prematureEnd(let expected, let actual):
                "Audio reading ended after \(actual) of \(expected) frames."
            }
        }
    }

    let format: AVAudioFormat
    private let source: Read
    /// The declared frames of the track, or nil when the file declares none.
    private let length: Int64?
    private var emitted: Int64 = 0

    init(format: AVAudioFormat, frames: Int64?, read: @escaping Read) {
        self.format = format
        length = frames
        source = read
    }

    /// The next frames of the track, at most `frames`, or nil at its end.
    func read(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        switch try next(frames: frames) {
        case .audio(let buffer): buffer
        case .end: nil
        }
    }

    func next(frames: AVAudioFrameCount) throws -> Output {
        if let length, emitted >= length {
            try validateRemainingInput()
            return .end
        }
        guard let buffer = try source(frames) else {
            if let length, emitted != length { throw Failure.prematureEnd(expected: length, actual: emitted) }
            return .end
        }
        guard let length, Int64(buffer.frameLength) > length - emitted else {
            emitted += Int64(buffer.frameLength)
            return .audio(buffer)
        }
        buffer.frameLength = AVAudioFrameCount(length - emitted)
        emitted = length
        return .audio(buffer)
    }

    /// The declared length can end before the decoder does. Read on to the decoder's end, so that a source that
    /// breaks off early still fails.
    private func validateRemainingInput() throws {
        while let buffer = try source(4096) {
            guard buffer.frameLength > 0 else { throw Failure.format }
        }
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
            throw PCMReader.Failure.allocation
        }
        try file.read(into: buffer, frameCount: count)
        guard buffer.frameLength > 0 else {
            throw PCMReader.Failure.prematureEnd(expected: playable.upperBound, actual: file.framePosition)
        }
        return buffer
    }
}
