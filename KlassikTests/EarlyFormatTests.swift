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

    /// Partial delivery: long fast-start M4A files, WAV and AIFF.
    static let partial = [("aac-long", "m4a"), ("alac-long", "m4a"), ("wav", "wav"), ("aiff", "aiff")]
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

    /// The system M4A reader reads 8 KB at the start, so the long M4A fixtures (8 s) stand for a real track: half of
    /// the file is still missing when the first frames come.
    @Test(arguments: EarlyFormatTests.partial)
    func soundStartsBeforeTheFileIsComplete(name: String, ext: String) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try Data(contentsOf: FormatFixtures.url("\(name)-1", ext))
        let head = data.count / 2
        let transfer = try transfer(name, length: data.count)
        transfer.append(data.prefix(head))
        defer { transfer.cancel() }
        let first = try await Self.first(transfer, suffix: ext)
        #expect(first.frames > 0)
        #expect(transfer.snapshot.available == Int64(head))
        #expect(!transfer.snapshot.complete)
        let reference = try FormatFixtures.recording("\(name)-1", ext).range
        #expect(first.playable == reference, "The stream cuts the same frames as the complete file")
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
