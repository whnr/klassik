import Foundation
import Testing

@testable import Klassik

/// The shared byte store of ADR 0060: readers wait for bytes, never read zeros, and a complete file moves to the
/// cache in one step.
@MainActor
struct TrackTransferTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func transfer(_ id: String = "t") -> TrackTransfer {
        TrackTransfer(
            songID: id, partial: root.appending(path: "\(id).flac.partial"), target: root.appending(path: "\(id).flac"),
            url: nil)
    }

    nonisolated static func read(
        _ transfer: TrackTransfer, at position: Int64, count: Int, timeout: Duration = .seconds(5)
    ) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0xEE, count: count)
        let read = try bytes.withUnsafeMutableBytes { buffer in
            try transfer.read(
                at: position, count: count, into: buffer.baseAddress!, timeout: timeout, isCancelled: { false })
        }
        return Array(bytes.prefix(read))
    }

    @Test func aReaderWaitsForTheBytes() async throws {
        let transfer = self.transfer()
        transfer.begin(length: 8, validator: nil)
        transfer.append(Data([1, 2, 3, 4]))
        let reader = Task.detached { try Self.read(transfer, at: 2, count: 4) }
        try await Task.sleep(for: .milliseconds(200))
        transfer.append(Data([5, 6]))
        #expect(try await reader.value == [3, 4, 5, 6])
        try? FileManager.default.removeItem(at: root)
    }

    /// A missing range ends with an error, never with zeros or a short read.
    @Test func missingBytesTimeOut() throws {
        let transfer = self.transfer()
        transfer.begin(length: 100, validator: nil)
        transfer.append(Data(repeating: 1, count: 10))
        #expect(throws: TrackTransfer.Failure.timedOut) {
            try Self.read(transfer, at: 5, count: 20, timeout: .milliseconds(300))
        }
        try? FileManager.default.removeItem(at: root)
    }

    @Test func theEndOfTheFileGivesAShortRead() throws {
        let transfer = self.transfer()
        transfer.begin(length: 6, validator: nil)
        transfer.append(Data([1, 2, 3, 4, 5, 6]))
        #expect(try Self.read(transfer, at: 4, count: 10) == [5, 6])
        #expect(try Self.read(transfer, at: 6, count: 10).isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func aCompleteTransferMovesToItsTarget() async throws {
        let transfer = self.transfer()
        transfer.begin(length: 3, validator: nil)
        transfer.append(Data([7, 8, 9]))
        transfer.finish(nil)
        #expect(try await transfer.finished() == root.appending(path: "t.flac"))
        #expect(!FileManager.default.fileExists(atPath: transfer.partial.path()))
        #expect(try Data(contentsOf: transfer.target) == Data([7, 8, 9]))
        // The open reader keeps working after the move.
        #expect(try Self.read(transfer, at: 0, count: 3) == [7, 8, 9])
        try? FileManager.default.removeItem(at: root)
    }

    @Test func aShortTransferFailsAndKeepsNothing() async throws {
        let transfer = self.transfer()
        transfer.begin(length: 10, validator: nil)
        transfer.append(Data([1, 2]))
        transfer.finish(nil)
        await #expect(throws: TrackTransfer.Failure.truncated) { try await transfer.finished() }
        #expect(!FileManager.default.fileExists(atPath: transfer.partial.path()))
        #expect(!FileManager.default.fileExists(atPath: transfer.target.path()))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func cancelWakesAWaitingReader() async throws {
        let transfer = self.transfer()
        transfer.begin(length: 10, validator: nil)
        let reader = Task.detached { try Self.read(transfer, at: 0, count: 4) }
        try await Task.sleep(for: .milliseconds(100))
        transfer.cancel()
        await #expect(throws: TrackTransfer.Failure.cancelled) { try await reader.value }
        #expect(!FileManager.default.fileExists(atPath: transfer.partial.path()))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func throughputFollowsTheArrivingBytes() async throws {
        let transfer = self.transfer()
        transfer.begin(length: nil, validator: nil)
        #expect(transfer.throughput == nil)
        transfer.append(Data(count: 1000))
        try await Task.sleep(for: .milliseconds(300))
        #expect((transfer.throughput ?? -1) >= 0)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Store

    func makeStore(_ started: Started) throws -> TrackStore {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        return TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults, transport: { song, _, transfer in started.transfers.append((song.id, transfer)) })
    }

    @MainActor final class Started {
        var transfers: [(id: String, transfer: TrackTransfer)] = []
    }

    let client = InMemoryServer()

    /// Playback, read-ahead and a download of one track use one transfer.
    @Test func oneTransferServesEveryConsumer() async throws {
        let started = Started()
        let store = try makeStore(started)
        let song = Song(id: "s", title: "s", suffix: "flac")
        guard case .stream(let playing) = try await store.source(for: song, client: client) else {
            Issue.record("A FLAC track must stream")
            return
        }
        let reading = Task { try await store.file(for: song, client: client) }
        guard case .stream(let again) = try await store.source(for: song, client: client) else {
            Issue.record("A FLAC track must stream")
            return
        }
        #expect(playing === again)
        #expect(started.transfers.count == 1)
        playing.begin(length: 4, validator: nil)
        playing.append(Data([1, 2, 3, 4]))
        playing.finish(nil)
        #expect(try await reading.value == root.appending(path: "cache/s.flac"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.transfers.isEmpty)
        #expect(store.offline == ["s"])
        guard case .file = try await store.source(for: song, client: client) else {
            Issue.record("A complete track plays from its file")
            return
        }
        try? FileManager.default.removeItem(at: root)
    }

    /// Partial bytes count under Music, but a partial track never plays offline.
    @Test func partialBytesCountButAreNotOffline() async throws {
        let started = Started()
        let store = try makeStore(started)
        let song = Song(id: "p", title: "p", suffix: "mp3")
        guard case .stream(let transfer) = try await store.source(for: song, client: client) else {
            Issue.record("An MP3 track must stream")
            return
        }
        transfer.begin(length: 100, validator: nil)
        transfer.append(Data(count: 40))
        store.rescan()
        #expect(store.cacheBytes == 40)
        #expect(store.offline.isEmpty)
        store.clearCache()
        await #expect(throws: TrackTransfer.Failure.cancelled) { try await transfer.finished() }
        try? FileManager.default.removeItem(at: root)
    }

    /// A format that has not passed the early-start gate loads whole first.
    @Test func otherFormatsWaitForTheWholeFile() async throws {
        let started = Started()
        let store = try makeStore(started)
        let song = Song(id: "w", title: "w", suffix: "m4a")
        let source = Task { try await store.source(for: song, client: client) }
        try await Task.sleep(for: .milliseconds(50))
        let transfer = try #require(started.transfers.first?.transfer)
        transfer.begin(length: 2, validator: nil)
        transfer.append(Data([1, 2]))
        transfer.finish(nil)
        guard case .file(let url) = try await source.value else {
            Issue.record("M4A must load whole")
            return
        }
        #expect(url == root.appending(path: "cache/w.m4a"))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func cancelKeepsTheNamedTransfers() async throws {
        let started = Started()
        let store = try makeStore(started)
        for id in ["a", "b"] { _ = store.transfer(for: Song(id: id, title: id, suffix: "flac"), client: client) }
        store.cancelTransfers(except: ["a"])
        let b = try #require(started.transfers.first { $0.id == "b" }?.transfer)
        await #expect(throws: TrackTransfer.Failure.cancelled) { try await b.finished() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.transfers.keys.sorted() == ["a"])
        store.cancelTransfers()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func theStreamInfoGivesTheSampleCount() throws {
        // fLaC, a last STREAMINFO block of 34 bytes: 44.1 kHz, 2 channels, 16 bits, 132 301 samples.
        var bytes: [UInt8] = [0x66, 0x4C, 0x61, 0x43, 0x80, 0, 0, 34] + Array(repeating: 0, count: 10)
        let packed = UInt64(44_100) << 44 | UInt64(1) << 41 | UInt64(15) << 36 | UInt64(132_301)
        bytes += (0..<8).map { UInt8(packed >> (56 - 8 * $0) & 0xFF) }
        bytes += Array(repeating: 0, count: 16)
        let info = try #require(FLACStreamInfo.parse(bytes))
        #expect(info == FLACStreamInfo(sampleRate: 44_100, channels: 2, bitsPerSample: 16, totalSamples: 132_301))
        #expect(FLACStreamInfo.parse(Array(bytes.prefix(20))) == nil)
    }
}
