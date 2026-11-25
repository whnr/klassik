import AVFoundation
import Foundation
import Testing

@testable import Klassik
@testable import KlassikEngine

/// M4A (AAC and ALAC), WAV and AIFF decode while their bytes arrive (ADR 0060), so a join does not wait for the
/// next track's complete file. These tests need no server: the fixtures are short, so a partial delivery is a
/// declared length with fewer bytes behind it.
struct EarlyFormatTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "early-formats-\(UUID().uuidString)")

    /// Files whose first bytes are enough: WAV and AIFF, and M4A with its moov box before the audio.
    static let headFirst = [("aac-fast", "m4a"), ("alac-fast", "m4a"), ("wav", "wav"), ("aiff", "aiff")]
    /// Every format that starts early. The plain M4A fixtures carry the moov box last.
    static let all = headFirst + [("aac", "m4a"), ("alac", "m4a")]
    /// Both tracks of each join.
    static let tracks = all.flatMap { format in [1, 2].map { (format.0, format.1, $0) } }

    func transfer(
        _ name: String, length: Int, ranges: TrackTransferTests.RangeServer? = nil, capacity: Int64? = nil
    ) throws -> TrackTransfer {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transfer = TrackTransfer(
            songID: name, partial: root.appending(path: "\(name).partial"), target: root.appending(path: name),
            url: ranges == nil ? nil : URL(string: "https://fixture.invalid/stream"), capacity: capacity,
            budget: capacity.map { AudioStorageBudget(limit: $0) }, rangeLoader: ranges?.loader)
        transfer.begin(length: Int64(length), validator: ranges?.validator)
        return transfer
    }

    /// The first decoded frames of a stream, and the frames that the decoder declares for the recording. The
    /// watchdog turns a decoder that waits for the whole file into a failure.
    static func first(
        _ transfer: TrackTransfer, suffix: String
    ) async throws -> (frames: Int, playable: Range<Int64>?) {
        let flag = CancelFlag()
        let watchdog = Task.detached {
            try? await Task.sleep(for: .seconds(10))
            flag.set()
        }
        defer { watchdog.cancel() }
        return try await Task.detached {
            let decoder = try StreamDecoder(transfer: transfer, suffix: suffix, cancelled: flag)
            let buffer = try decoder.read(frames: 1024)
            return (Int(buffer?.frameLength ?? 0), decoder.playable)
        }.value
    }

    /// The decoder may read the end of a file, as the M4A reader does for its index. A trailing box 2 MB long puts
    /// that end beyond the first range lead, so the read goes by range and the head arrives in order.
    @Test(arguments: EarlyFormatTests.headFirst)
    func soundStartsBeforeTheFileIsComplete(name: String, ext: String) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Data(contentsOf: FormatFixtures.url("\(name)-1", ext))
        let data = ext == "m4a" ? Self.trailed(source, by: 2 << 20) : source
        let server = TrackTransferTests.RangeServer(data: data)
        let head = source.count * 6 / 10
        let transfer = try transfer(name, length: data.count, ranges: server)
        transfer.append(data.prefix(head))
        defer { transfer.cancel() }
        let first = try await Self.first(transfer, suffix: ext)
        print("\(name): first PCM from \(head) of \(data.count) bytes, ranges \(server.requests)")
        #expect(first.frames > 0)
        #expect(transfer.snapshot.available == Int64(head))
        #expect(!transfer.snapshot.complete)
        let reference = try FormatFixtures.recording("\(name)-1", ext).range
        #expect(first.playable == reference, "The stream cuts the same frames as the complete file")
    }

    /// Which bytes the system M4A reader asks for until the first 1024 frames: the reads must stay in the head of the
    /// file, with at most the index at the end.
    @Test(arguments: ["aac-fast", "alac-fast", "aac", "alac"])
    func theM4AReaderStaysNearTheHead(name: String) throws {
        let data = try Data(contentsOf: FormatFixtures.url("\(name)-1", "m4a"))
        let probe = ReadLog(data)
        var file: AudioFileID?
        let opened = AudioFileOpenWithCallbacks(
            Unmanaged.passUnretained(probe).toOpaque(),
            { context, position, requested, destination, actual in
                Unmanaged<ReadLog>.fromOpaque(context).takeUnretainedValue()
                    .read(position: position, requested: requested, into: destination, actual: actual)
            }, nil,
            { context in Int64(Unmanaged<ReadLog>.fromOpaque(context).takeUnretainedValue().data.count) }, nil,
            kAudioFileM4AType, &file)
        #expect(opened == noErr)
        let audioFile = try #require(file)
        defer { AudioFileClose(audioFile) }
        var extended: ExtAudioFileRef?
        #expect(ExtAudioFileWrapAudioFileID(audioFile, false, &extended) == noErr)
        let decoder = try #require(extended)
        defer { ExtAudioFileDispose(decoder) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        var description = format.streamDescription.pointee
        ExtAudioFileSetProperty(
            decoder, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &description)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        var frames: UInt32 = 1024
        #expect(ExtAudioFileRead(decoder, &frames, buffer.mutableAudioBufferList) == noErr)
        print("\(name): \(data.count) bytes, reads \(probe.reads)")
        let furthest = probe.reads.map { $0.upperBound }.max() ?? 0
        if furthest > Int64(data.count * 6 / 10) {
            Issue.record("\(name): \(data.count) bytes, furthest \(furthest), reads \(probe.reads)")
        }
    }

    private final class ReadLog {
        let data: Data
        var reads: [Range<Int64>] = []
        init(_ data: Data) { self.data = data }

        func read(
            position: Int64, requested: UInt32, into destination: UnsafeMutableRawPointer,
            actual: UnsafeMutablePointer<UInt32>
        ) -> OSStatus {
            guard position >= 0, position <= data.count else { return kAudioFilePositionError }
            let count = min(Int(requested), data.count - Int(position))
            data.withUnsafeBytes { bytes in
                if count > 0 {
                    destination.copyMemory(from: bytes.baseAddress!.advanced(by: Int(position)), byteCount: count)
                }
            }
            reads.append(position..<(position + Int64(count)))
            actual.pointee = UInt32(count)
            return noErr
        }
    }

    /// The file with a free box of `size` bytes at its end.
    static func trailed(_ data: Data, by size: Int) -> Data {
        var box = [UInt8](repeating: 0, count: size)
        for index in 0..<4 { box[index] = UInt8(truncatingIfNeeded: size >> (24 - 8 * index)) }
        box.replaceSubrange(4..<8, with: Array("free".utf8))
        return data + Data(box)
    }

    /// Bytes arrive in small chunks, so the decoder waits as on a slow line. The streamed samples are the samples of
    /// the complete file, for both tracks of the join.
    @Test(arguments: EarlyFormatTests.tracks)
    func aStreamedTrackMatchesTheCompleteFile(name: String, ext: String, movement: Int) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try Data(contentsOf: FormatFixtures.url("\(name)-\(movement)", ext))
        let transfer = try transfer("\(name)-\(movement)", length: data.count)
        let feeder = StreamingPlaybackTests.feed(data, into: transfer, chunk: 1024)
        defer {
            feeder.cancel()
            transfer.cancel()
        }
        let buffers = try await StreamingPlaybackTests.decode(transfer, suffix: ext)
        let streamed = StreamingPlaybackTests.samples(buffers)
        let complete = try FormatFixtures.recording("\(name)-\(movement)", ext).samples
        #expect(streamed == complete)
    }

    /// A moov box at the end of a track larger than the Music limit: the decoder asks for the tail by range and
    /// never waits for the sequential bytes in between.
    @Test(arguments: ["aac", "alac"])
    func aMoovBoxAtTheEndComesByRange(name: String) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Self.padded(try Data(contentsOf: FormatFixtures.url("\(name)-1", "m4a")), by: 2 << 20)
        let server = TrackTransferTests.RangeServer(data: data)
        let transfer = try transfer(name, length: data.count, ranges: server, capacity: 64 * 1024)
        transfer.append(data.prefix(8192))
        defer { transfer.cancel() }
        let streamed = try await Task.detached {
            let decoder = try StreamDecoder(transfer: transfer, suffix: "m4a", cancelled: CancelFlag())
            var buffers: [AVAudioPCMBuffer] = []
            while let buffer = try decoder.read(frames: 11_025) { buffers.append(buffer) }
            return (StreamingPlaybackTests.Buffers(buffers), decoder.playable)
        }.value
        let reference = try FormatFixtures.recording("\(name)-1", "m4a")
        #expect(StreamingPlaybackTests.samples(streamed.0.buffers) == reference.samples)
        #expect(streamed.1 == reference.range)
        #expect(!server.requests.isEmpty, "The moov box is far beyond the arrived bytes, so it comes by range")
        #expect(transfer.snapshot.available == 8192)
        #expect(!transfer.snapshot.complete)
    }

    /// A server that answers a range with the whole file leaves a rolling window no way to reach the moov box. The
    /// engine then loads the complete file.
    @Test func aServerWithoutRangesNeedsTheCompleteFile() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Self.padded(try Data(contentsOf: FormatFixtures.url("aac-1", "m4a")), by: 2 << 20)
        let server = TrackTransferTests.RangeServer(data: data, status: 200)
        let transfer = try transfer("refused", length: data.count, ranges: server, capacity: 64 * 1024)
        transfer.append(data.prefix(8192))
        defer { transfer.cancel() }
        let failure = await Task.detached {
            do {
                _ = try StreamDecoder(transfer: transfer, suffix: "m4a", cancelled: CancelFlag())
                return nil as TrackTransfer.Failure?
            } catch { return error as? TrackTransfer.Failure }
        }.value
        #expect(failure == .requiresCompleteFile)
    }

    /// The M4A file with a free box of `padding` bytes before its audio. The chunk offsets move by the same amount.
    static func padded(_ data: Data, by padding: Int) -> Data {
        var bytes = [UInt8](data)
        func word(_ at: Int) -> Int { bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        func store(_ value: Int, at: Int) {
            for index in 0..<4 { bytes[at + index] = UInt8(truncatingIfNeeded: value >> (24 - 8 * index)) }
        }
        let ftyp = word(0)
        let type = Array("stco".utf8)
        let at = bytes.indices.dropLast(3).first { Array(bytes[$0..<$0 + 4]) == type }!
        for entry in 0..<word(at + 8) { store(word(at + 12 + 4 * entry) + padding, at: at + 12 + 4 * entry) }
        var free = [UInt8](repeating: 0, count: padding)
        for index in 0..<4 { free[index] = UInt8(truncatingIfNeeded: padding >> (24 - 8 * index)) }
        free.replaceSubrange(4..<8, with: Array("free".utf8))
        bytes.insert(contentsOf: free, at: ftyp)
        return Data(bytes)
    }
}
