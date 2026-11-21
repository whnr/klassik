import AVFoundation
import AudioToolbox

/// Decodes a track while its bytes arrive (ADR 0060). The system decoder reads through callbacks; each callback
/// waits on the decoder's worker queue for missing bytes. Call every method on that one queue.
final class StreamDecoder: @unchecked Sendable {
    enum Failure: Error, Equatable {
        /// The format has not passed the early-start gate, so the track must be complete first.
        case unsupported
        /// The server sent no length; the callbacks cannot report the file size.
        case unknownLength
        case status(OSStatus)
        case prematureEnd(expected: Int64, actual: Int64)
    }

    /// Formats whose decoders produced sound from the first bytes on iOS 27 (EarlyPlaybackTests).
    static let earlyFormats: Set<String> = ["mp3", "flac"]
    /// Each wait for bytes ends with an error after this time, so that a dead connection does not hang playback.
    static let readTimeout = Duration.seconds(30)

    static func canStartEarly(_ song: Song) -> Bool {
        earlyFormats.contains(song.suffix?.lowercased() ?? "")
    }

    /// The decoded format: the same standard format that AVAudioFile gives a complete file.
    let format: AVAudioFormat
    /// The decoded frames that belong to the recording, when the file declares them: MP3 without encoder delay and
    /// padding, FLAC from STREAMINFO. Nil means that the end of the file ends the track.
    let playable: Range<Int64>?
    var sampleRate: Double { format.sampleRate }
    /// The furthest sequential byte that the decoder read. Tail metadata never counts as consumed audio.
    var consumed: Int64 { context.consumed }

    private let context: Context
    private let file: AudioFileID
    private let decoder: ExtAudioFileRef
    /// The decoded frame that the next read returns.
    private var cursor: Int64 = 0
    /// Bytes the decoder consumed against the frames it returned, for the bitrate estimate.
    private var history: [(frames: Int64, bytes: Int64)] = []

    /// Opens the decoder. It waits for the response head of `transfer`, then for the bytes that the format needs.
    init(transfer: TrackTransfer, suffix: String, cancelled: CancelFlag) throws {
        let suffix = suffix.lowercased()
        guard Self.earlyFormats.contains(suffix) else { throw Failure.unsupported }
        let length = try transfer.length(timeout: Self.readTimeout, isCancelled: { cancelled.isSet })
        guard let length else { throw Failure.unknownLength }
        let context = Context(transfer: transfer, length: length, cancelled: cancelled)
        let playable = try Self.declaredRange(suffix: suffix, context: context)
        var opened: AudioFileID?
        let type = suffix == "flac" ? kAudioFileFLACType : kAudioFileMP3Type
        let status = AudioFileOpenWithCallbacks(
            Unmanaged.passUnretained(context).toOpaque(),
            { context, position, requested, destination, actual in
                Unmanaged<Context>.fromOpaque(context).takeUnretainedValue()
                    .read(position: position, requested: requested, into: destination, actual: actual)
            }, nil,
            { context in
                Unmanaged<Context>.fromOpaque(context).takeUnretainedValue().length
            }, nil, type, &opened)
        guard status == noErr, let opened else { throw Self.error(context, status) }
        var wrapped: ExtAudioFileRef?
        let wrap = ExtAudioFileWrapAudioFileID(opened, false, &wrapped)
        guard wrap == noErr, let wrapped else {
            AudioFileClose(opened)
            throw Failure.status(wrap)
        }
        var source = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var result = ExtAudioFileGetProperty(wrapped, kExtAudioFileProperty_FileDataFormat, &size, &source)
        guard result == noErr,
            let format = AVAudioFormat(
                standardFormatWithSampleRate: source.mSampleRate, channels: source.mChannelsPerFrame)
        else {
            ExtAudioFileDispose(wrapped)
            AudioFileClose(opened)
            throw Failure.status(result)
        }
        var client = format.streamDescription.pointee
        result = ExtAudioFileSetProperty(
            wrapped, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &client)
        guard result == noErr else {
            ExtAudioFileDispose(wrapped)
            AudioFileClose(opened)
            throw Failure.status(result)
        }
        self.context = context
        self.file = opened
        self.decoder = wrapped
        self.format = format
        self.playable = playable
    }

    deinit {
        ExtAudioFileDispose(decoder)
        AudioFileClose(file)
    }

    /// Moves to a decoded frame, as AVAudioFile's frame position does for a complete file.
    func seek(to frame: Int64) throws {
        let status = ExtAudioFileSeek(decoder, frame)
        guard status == noErr else { throw Self.error(context, status) }
        cursor = frame
        history = []
    }

    /// The next decoded frames of the recording, at most `frames`, or nil at its end. Encoder delay and padding
    /// never leave the decoder.
    func read(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        while true {
            let end = playable?.upperBound ?? .max
            guard cursor < end else { return nil }
            let wanted = AVAudioFrameCount(min(Int64(frames), end - cursor))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: wanted) else { return nil }
            // ExtAudioFileRead takes the byte sizes in the buffer list as the space it may fill.
            buffer.frameLength = buffer.frameCapacity
            var count = UInt32(wanted)
            let status = ExtAudioFileRead(decoder, &count, buffer.mutableAudioBufferList)
            guard status == noErr else { throw Self.error(context, status) }
            guard count > 0 else {
                if let playable, cursor < playable.upperBound {
                    throw Failure.prematureEnd(expected: playable.upperBound, actual: cursor)
                }
                return nil
            }
            buffer.frameLength = count
            let start = cursor
            cursor += Int64(count)
            record()
            // The frames before the recording are encoder delay.
            let first = max(playable?.lowerBound ?? 0, start)
            if first >= cursor { continue }
            return first == start ? buffer : Self.slice(buffer, from: AVAudioFrameCount(first - start))
        }
    }

    /// The encoded rate over the latest two decoded seconds, in bits per second.
    var observedBitrate: Double? {
        guard let last = history.last,
            let first = history.first(where: { Double(last.frames - $0.frames) <= 2 * sampleRate }),
            last.frames > first.frames
        else { return nil }
        return Double(last.bytes - first.bytes) * 8 / (Double(last.frames - first.frames) / sampleRate)
    }

    /// A failed read explains a decoder error better than the decoder's own status.
    private static func error(_ context: Context, _ status: OSStatus) -> any Error {
        if let failure = context.failure { return failure }
        return Failure.status(status)
    }

    private func record() {
        history.append((cursor, context.consumed))
        history.removeAll { Double(cursor - $0.frames) > 2 * sampleRate }
    }

    private static func slice(_ buffer: AVAudioPCMBuffer, from offset: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let count = buffer.frameLength - offset
        guard let part = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count),
            let source = buffer.floatChannelData, let target = part.floatChannelData
        else { return nil }
        part.frameLength = count
        for channel in 0..<Int(buffer.format.channelCount) {
            target[channel].update(from: source[channel].advanced(by: Int(offset)), count: Int(count))
        }
        return part
    }

    /// The frames of the recording, from the header bytes alone. The decoder must never learn the end of a track
    /// from missing bytes.
    private static func declaredRange(suffix: String, context: Context) throws -> Range<Int64>? {
        switch suffix {
        case "mp3":
            let head = try context.bytes(at: 0, count: 10)
            let tag = MP3GaplessInfo.id3Size(head)
            let frames = try context.bytes(at: Int64(tag), count: MP3GaplessInfo.headerSearch)
            guard let info = MP3GaplessInfo.parse(afterTag: frames) else { return nil }
            // iOS decoders remove only their own delay, so the decoded length exceeds the recording.
            return info.playableRange(decodedLength: Int64(info.frameCount * info.samplesPerFrame))
        case "flac":
            let head = try context.bytes(at: 0, count: 42)
            return FLACStreamInfo.parse(head).map { 0..<$0.totalSamples }
        default:
            return nil
        }
    }

    /// What the callbacks share with the decoder. Only the worker queue touches it.
    private final class Context {
        let transfer: TrackTransfer
        let length: Int64
        let cancelled: CancelFlag
        /// The furthest byte that a read reached.
        var consumed: Int64 = 0
        var failure: TrackTransfer.Failure?

        init(transfer: TrackTransfer, length: Int64, cancelled: CancelFlag) {
            self.transfer = transfer
            self.length = length
            self.cancelled = cancelled
        }

        func read(
            position: Int64, requested: UInt32, into destination: UnsafeMutableRawPointer,
            actual: UnsafeMutablePointer<UInt32>
        ) -> OSStatus {
            guard position >= 0 else { return kAudioFilePositionError }
            do {
                let count = try transfer.read(
                    at: position, count: Int(requested), into: destination, timeout: StreamDecoder.readTimeout,
                    isCancelled: { cancelled.isSet })
                actual.pointee = UInt32(count)
                if position + Int64(count) <= transfer.snapshot.available {
                    consumed = max(consumed, position + Int64(count))
                }
                return noErr
            } catch {
                failure = error
                actual.pointee = 0
                // An error, not the end of the file: missing bytes must never end a track.
                return kAudioFileUnspecifiedError
            }
        }

        func bytes(at position: Int64, count: Int) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: count)
            let read = try bytes.withUnsafeMutableBytes { buffer in
                try transfer.read(
                    at: position, count: count, into: buffer.baseAddress!, timeout: StreamDecoder.readTimeout,
                    isCancelled: { cancelled.isSet })
            }
            return Array(bytes.prefix(read))
        }
    }
}

/// The STREAMINFO block at the start of a native FLAC file.
struct FLACStreamInfo: Equatable, Sendable {
    var sampleRate: Int
    var channels: Int
    var bitsPerSample: Int
    var totalSamples: Int64

    /// `bytes` start at the file's "fLaC" marker. A zero sample count means that the encoder did not know it.
    static func parse(_ bytes: [UInt8]) -> FLACStreamInfo? {
        guard bytes.count >= 26, bytes[0..<4] == [0x66, 0x4C, 0x61, 0x43], bytes[4] & 0x7F == 0 else { return nil }
        let packed = bytes[18..<26].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let info = FLACStreamInfo(
            sampleRate: Int(packed >> 44), channels: Int(packed >> 41 & 0x7) + 1,
            bitsPerSample: Int(packed >> 36 & 0x1F) + 1, totalSamples: Int64(packed & 0xF_FFFF_FFFF))
        return info.totalSamples > 0 ? info : nil
    }
}

/// A flag that one thread sets and another reads.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() { lock.withLock { value = true } }
}
