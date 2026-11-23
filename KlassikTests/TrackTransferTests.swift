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

    /// Blocking byte reads need a dispatch worker; they must not occupy the cooperative task executor.
    nonisolated static func readOnWorker(_ transfer: TrackTransfer, at position: Int64, count: Int) async throws
        -> [UInt8]
    {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try Self.read(transfer, at: position, count: count) })
            }
        }
    }

    nonisolated static func appendOnWorker(_ data: Data, to transfer: TrackTransfer) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                transfer.append(data)
                transfer.finish(nil)
                continuation.resume()
            }
        }
    }

    @Test func aRollingTransferPreservesEverySequentialByte() async throws {
        let budget = AudioStorageBudget(limit: 16)
        let transfer = TrackTransfer(
            songID: "rolling", partial: root.appending(path: "rolling.partial"),
            target: root.appending(path: "rolling.flac"),
            url: nil, capacity: 16, budget: budget)
        transfer.begin(length: 200, validator: nil)
        defer {
            transfer.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        let expected = Data(0..<200)
        let producer = Task { await Self.appendOnWorker(expected, to: transfer) }
        var actual = Data()
        for position in stride(from: 0, to: 200, by: 4) {
            actual.append(contentsOf: try await Self.readOnWorker(transfer, at: Int64(position), count: 4))
            #expect(budget.storedBytes <= 16)
        }
        await producer.value
        #expect(actual == expected)
        #expect(transfer.snapshot.complete)
        #expect(!transfer.hasCompleteFile)
        #expect(!FileManager.default.fileExists(atPath: transfer.target.path()))
        #expect(try Self.read(transfer, at: 0, count: 4) == Array(0..<4))
        #expect(throws: TrackTransfer.Failure.requiresCompleteFile) { try Self.read(transfer, at: 4, count: 4) }
        await #expect(throws: TrackTransfer.Failure.requiresCompleteFile) { try await transfer.finished() }
        #expect(try Data(contentsOf: transfer.partial).count == 16)
    }

    @Test func cancellingAFullWindowWakesItsWriter() async throws {
        let transfer = TrackTransfer(
            songID: "rolling", partial: root.appending(path: "rolling.partial"),
            target: root.appending(path: "rolling.flac"),
            url: nil, capacity: 16)
        transfer.begin(length: 200, validator: nil)
        let producer = Task { await Self.appendOnWorker(Data(0..<200), to: transfer) }
        for _ in 0..<100 where transfer.snapshot.available < 16 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(transfer.snapshot.available == 16)
        #expect(!transfer.snapshot.complete)
        transfer.cancel()
        await producer.value
        await #expect(throws: TrackTransfer.Failure.cancelled) { try await transfer.finished() }
        #expect(!FileManager.default.fileExists(atPath: transfer.partial.path()))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func anOversizedResponseFailsBeforeAFullWindowCanBlock() async throws {
        let transfer = TrackTransfer(
            songID: "rolling", partial: root.appending(path: "rolling.partial"),
            target: root.appending(path: "rolling.flac"),
            url: nil, capacity: 4)
        transfer.begin(length: 4, validator: nil)
        transfer.append(Data(0..<8))
        await #expect(throws: TrackTransfer.Failure.truncated) { try await transfer.finished() }
        #expect(!FileManager.default.fileExists(atPath: transfer.partial.path()))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func evictingOtherFilesReleasesABlockedTransfer() async throws {
        let budget = AudioStorageBudget(limit: 16)
        budget.synchronize([root.appending(path: "old.flac"): 8])
        let transfer = TrackTransfer(
            songID: "rolling", partial: root.appending(path: "rolling.partial"),
            target: root.appending(path: "rolling.flac"),
            url: nil, capacity: 32, budget: budget)
        transfer.begin(length: 16, validator: nil)
        defer {
            transfer.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        let producer = Task { await Self.appendOnWorker(Data(0..<16), to: transfer) }
        for _ in 0..<100 where transfer.snapshot.available < 8 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(transfer.snapshot.available == 8)
        #expect(!transfer.snapshot.complete)
        budget.synchronize([:])
        await producer.value
        #expect(transfer.hasCompleteFile)
        #expect(budget.storedBytes == 16)
        #expect(try Self.read(transfer, at: 0, count: 16) == Array(0..<16))
    }

    func completedWindow(partial: URL, target: URL) async throws -> TrackTransfer {
        let transfer = TrackTransfer(songID: "a", partial: partial, target: target, url: nil, capacity: 8)
        transfer.begin(length: 20, validator: nil)
        let producer = Task { await Self.appendOnWorker(Data(0..<20), to: transfer) }
        do {
            for position in stride(from: 0, to: 20, by: 4) {
                _ = try await Self.readOnWorker(transfer, at: Int64(position), count: 4)
            }
            await producer.value
            return transfer
        } catch {
            transfer.cancel()
            await producer.value
            throw error
        }
    }

    @Test func anOldWindowCannotRemoveAReplacementTransfer() async throws {
        let started = Started()
        let store = try makeStore(started)
        defer {
            store.cancelTransfers()
            try? FileManager.default.removeItem(at: root)
        }
        let song = Song(id: "a", title: "Fixture", suffix: "flac")
        let first = store.transfer(for: song, client: InMemoryServer())
        store.cancelTransfers()
        var obsolete: TrackTransfer? = try await completedWindow(partial: first.partial, target: first.target)
        #expect(obsolete?.hasCompleteFile == false)
        let replacement = store.transfer(for: song, client: InMemoryServer())
        replacement.begin(length: 2, validator: nil)
        replacement.append(Data([7, 8]))
        obsolete = nil
        #expect(try Data(contentsOf: replacement.partial) == Data([7, 8]))
        replacement.finish(nil)
        #expect(try await replacement.finished() == replacement.target)
        #expect(try Data(contentsOf: replacement.target) == Data([7, 8]))
    }

    @Test func aReaderWaitsForTheBytes() async throws {
        let transfer = self.transfer()
        transfer.begin(length: 8, validator: nil)
        transfer.append(Data([1, 2, 3, 4]))
        let reader = Task { try await Self.readOnWorker(transfer, at: 2, count: 4) }
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

    @Test func storageFailureBeforeTheFirstByteEndsTheWait() async throws {
        try Data([1]).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let transfer = self.transfer()
        await #expect(throws: TrackTransfer.Failure.storage) { try await transfer.finished() }
        #expect(throws: TrackTransfer.Failure.storage) { try Self.read(transfer, at: 0, count: 1) }
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
        let reader = Task { try await Self.readOnWorker(transfer, at: 0, count: 4) }
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

    @Test(arguments: [false, true])
    func cancellingAWaitKeepsOtherConsumers(waitUntilRegistered: Bool) async throws {
        let transfer = self.transfer()
        transfer.begin(length: 4, validator: nil)
        let cancelled = Task { try await transfer.finished() }
        let kept = Task { try await transfer.finished() }
        if waitUntilRegistered { try await Task.sleep(for: .milliseconds(20)) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        transfer.append(Data([1, 2, 3, 4]))
        transfer.finish(nil)
        #expect(try await kept.value == transfer.target)
        #expect(try Self.read(transfer, at: 0, count: 4) == [1, 2, 3, 4])
        try? FileManager.default.removeItem(at: root)
    }

    @Test(arguments: [200, 206, 416])
    func rangeResponsesRequireTheSameRepresentation(status: Int) throws {
        let url = try #require(URL(string: "https://fixture.invalid/stream"))
        func accepts(_ headers: [String: String], count: Int = 4, validator: String? = "\"a\"") throws -> Bool {
            let response = try #require(
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
            return TrackTransfer.acceptsRange(
                response, bytes: count, start: 100, length: 4, total: 200, validator: validator)
        }
        let valid = ["Content-Range": "bytes 100-103/200", "ETag": "\"a\""]
        #expect(try accepts(valid) == (status == 206))
        #expect(try !accepts(valid, count: 3))
        #expect(try !accepts(valid, validator: nil))
        #expect(try !accepts(valid, validator: "W/\"a\""))
        #expect(try !accepts(["Content-Range": "bytes 100-103/200", "ETag": "\"b\""]))
        #expect(try !accepts(["Content-Range": "bytes 100-103/201", "ETag": "\"a\""]))
        #expect(try !accepts(valid.merging(["Content-Encoding": "gzip"]) { _, new in new }))
    }

    @Test func invalidReadsFailWithoutTouchingTheFile() throws {
        let transfer = self.transfer()
        #expect(throws: TrackTransfer.Failure.invalidRead) { try Self.read(transfer, at: -1, count: 1) }
        #expect(throws: TrackTransfer.Failure.invalidRead) { try Self.read(transfer, at: .max, count: 2) }
        transfer.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func missingDiskBytesNeverBecomeEndOfAudio() throws {
        let transfer = self.transfer()
        transfer.begin(length: 4, validator: nil)
        transfer.append(Data([1, 2, 3, 4]))
        let handle = try FileHandle(forWritingTo: transfer.partial)
        try handle.truncate(atOffset: 0)
        try handle.close()
        #expect(throws: TrackTransfer.Failure.storage) { try Self.read(transfer, at: 0, count: 4) }
        transfer.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    @Test(arguments: [nil, "W/\"weak\""] as [String?])
    func unvalidatedTailReadsRequireACompleteFile(validator: String?) throws {
        let url = try #require(URL(string: "https://fixture.invalid/stream"))
        let transfer = TrackTransfer(
            songID: "tail", partial: root.appending(path: "tail.partial"), target: root.appending(path: "tail.mp3"),
            url: url)
        transfer.begin(length: 100_000_000, validator: validator)
        #expect(throws: TrackTransfer.Failure.requiresCompleteFile) {
            try Self.read(transfer, at: 99_999_872, count: 128)
        }
        transfer.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    /// Serves byte ranges of `data` from memory, as a server that honours Range does. The first `failures` requests
    /// end with a network error, as a timeout does. With `rate`, each range arrives at that many bytes a second.
    final class RangeServer: @unchecked Sendable {
        let data: Data
        let validator = "\"fixture\""
        let status: Int
        let rate: Double?
        private let lock = NSLock()
        private var failures: Int
        private var log: [String] = []
        var requests: [String] { lock.withLock { log } }

        init(data: Data, failures: Int = 0, status: Int = 206, rate: Double? = nil) {
            self.data = data
            self.failures = failures
            self.status = status
            self.rate = rate
        }

        var loader: TrackTransfer.RangeLoader {
            { [self] request, receiver in
                let header = request.value(forHTTPHeaderField: "Range") ?? ""
                let fails = lock.withLock {
                    log.append(header)
                    failures -= 1
                    return failures >= 0
                }
                let bounds = header.dropFirst("bytes=".count).split(separator: "-").compactMap { Int($0) }
                let task = Task.detached { [data, status, validator, rate] in
                    try? await Task.sleep(for: .milliseconds(20))
                    guard !fails, bounds.count == 2, let url = request.url else { return receiver.end(failed: true) }
                    let range = "bytes \(bounds[0])-\(bounds[1])/\(data.count)"
                    let headers = ["Content-Range": range, "ETag": validator]
                    let response = HTTPURLResponse(
                        url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
                    guard let response, receiver.head(response) else { return receiver.end(failed: true) }
                    guard let rate else {
                        _ = receiver.receive(data.subdata(in: bounds[0]..<(bounds[1] + 1)))
                        return receiver.end(failed: false)
                    }
                    let piece = max(1024, Int(rate / 16))
                    let started = ContinuousClock.now
                    var offset = bounds[0]
                    while offset <= bounds[1], !Task.isCancelled {
                        let next = min(offset + piece, bounds[1] + 1)
                        guard receiver.receive(data.subdata(in: offset..<next)) else { return }
                        offset = next
                        try? await Task.sleep(
                            until: started + .seconds(Double(offset - bounds[0]) / rate), clock: .continuous)
                    }
                    receiver.end(failed: Task.isCancelled)
                }
                return { task.cancel() }
            }
        }
    }

    func rangedTransfer(_ server: RangeServer, chunk: Int64 = TrackTransfer.rangeChunk) throws -> TrackTransfer {
        let transfer = TrackTransfer(
            songID: "ranged", partial: root.appending(path: "ranged.partial"),
            target: root.appending(path: "ranged.mp3"),
            url: URL(string: "https://fixture.invalid/stream"), rangeChunk: chunk, rangeLoader: server.loader)
        transfer.begin(length: Int64(server.data.count), validator: server.validator)
        return transfer
    }

    static let resource = Data((0..<3_000_000).map { UInt8($0 % 251) })

    /// A range that fails without an answer leaves ranges on; the next read asks again (ADR 0060).
    @Test func aRangeTimeoutLeavesRangesOn() async throws {
        let server = RangeServer(data: Self.resource, failures: 1)
        let transfer = try rangedTransfer(server)
        defer {
            transfer.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        let bytes = try await Self.readOnWorker(transfer, at: 2_000_000, count: 16)
        #expect(bytes == Array(Self.resource[2_000_000..<2_000_016]))
        let first = try #require(server.requests.first)
        #expect(server.requests.prefix(2) == [first, first])
    }

    /// Only a whole-file answer refuses ranges. Then a far read waits for the sequential bytes.
    @Test func aWholeFileAnswerStopsRanges() async throws {
        let server = RangeServer(data: Self.resource, status: 200)
        let transfer = try rangedTransfer(server)
        defer {
            transfer.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        let reader = Task { try await Self.readOnWorker(transfer, at: 2_000_000, count: 16) }
        try await Task.sleep(for: .milliseconds(300))
        await Self.appendOnWorker(Self.resource, to: transfer)
        #expect(try await reader.value == Array(Self.resource[2_000_000..<2_000_016]))
        #expect(server.requests.count == 1)
    }

    /// Reads past the arrived bytes follow one range after another, and the next range starts before the reader
    /// needs it.
    @Test func rangesReadAheadOfTheReader() async throws {
        let server = RangeServer(data: Self.resource)
        let transfer = try rangedTransfer(server)
        defer {
            transfer.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        let start = 1_500_000
        _ = try await Self.readOnWorker(transfer, at: Int64(start), count: 4096)
        for _ in 0..<100 where server.requests.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        let chunk = Int(TrackTransfer.rangeChunk)
        let ranges = ["bytes=\(start)-\(start + chunk - 1)", "bytes=\(start + chunk)-\(start + 2 * chunk - 1)"]
        #expect(server.requests == ranges)
        let across = try await Self.readOnWorker(transfer, at: Int64(start + chunk - 8), count: 16)
        #expect(across == Array(Self.resource[(start + chunk - 8)..<(start + chunk + 8)]))
    }

    /// A reader that jumps past the arrived bytes and then reads at the bitrate never waits on a range boundary:
    /// at twice the bitrate, the next range streams in before the reader reaches it (ADR 0060).
    @Test func aFarReaderAtTheBitrateNeverWaits() async throws {
        let bitrate = 40_000.0
        let server = RangeServer(data: Data((0..<6_000_000).map { UInt8($0 % 241) }), rate: bitrate * 2)
        let transfer = try rangedTransfer(server, chunk: 64 * 1024)
        defer {
            transfer.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        let waits = try await Task.detached {
            var waits: [Duration] = []
            var position: Int64 = 3_000_000
            let started = ContinuousClock.now
            for step in 0..<60 {
                let before = ContinuousClock.now
                let bytes = try Self.read(transfer, at: position, count: 4_000)
                waits.append(before.duration(to: .now))
                #expect(bytes == Array(server.data[Int(position)..<Int(position) + 4_000]))
                position += 4_000
                // 4,000 bytes last 0.1 s at the bitrate.
                try? await Task.sleep(until: started + .milliseconds(100 * (step + 1)), clock: .continuous)
            }
            return waits
        }.value
        let longest = waits.dropFirst().max() ?? .zero
        print("far reader: first=\(waits[0]), longest later wait=\(longest), ranges=\(server.requests.count)")
        if LatencyLimits.enforced {
            #expect(longest < .milliseconds(150), "the reader waited at a range boundary")
        }
        #expect(server.requests.count >= 3)
    }

    /// A wait for bytes that keep arriving never times out; only a silent transfer does.
    @Test func aWaitTimesOutOnlyWithoutArrivingBytes() async throws {
        let transfer = self.transfer()
        transfer.begin(length: 1_000, validator: nil)
        let feeder = Task.detached {
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(100))
                transfer.append(Data(count: 100))
            }
        }
        let bytes = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    with: Result { try Self.read(transfer, at: 990, count: 10, timeout: .milliseconds(300)) })
            }
        }
        await feeder.value
        #expect(bytes.count == 10)
        transfer.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    /// A server that stops sending is not a slow connection (ADR 0060).
    @Test func aStalledTransferIsNotSlow() async throws {
        let transfer = self.transfer()
        transfer.begin(length: 100_000, validator: nil)
        transfer.append(Data(count: 1_000))
        try await Task.sleep(for: .milliseconds(300))
        #expect(transfer.isSlow(below: 1_000_000))
        try await Task.sleep(for: .milliseconds(1_100))
        #expect(!transfer.isSlow(below: 1_000_000))
        transfer.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func bufferedBytesAndStorageNeedFollowTheFile() throws {
        let whole = self.transfer("whole")
        whole.begin(length: 100, validator: nil)
        whole.append(Data(count: 30))
        #expect(whole.bufferedBytes(from: 10) == 20)
        #expect(whole.storageNeed == 70)
        let rolling = TrackTransfer(
            songID: "rolling", partial: root.appending(path: "rolling.partial"),
            target: root.appending(path: "rolling.flac"), url: nil, capacity: 16)
        rolling.begin(length: 200, validator: nil)
        rolling.append(Data(count: 8))
        #expect(rolling.storageNeed == 8)
        whole.cancel()
        rolling.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func dateValidatorsRequireSeparatedClocks() throws {
        let url = try #require(URL(string: "https://fixture.invalid/stream"))
        let modified = "Fri, 20 Nov 2026 12:00:00 GMT"
        func validator(_ date: String?) throws -> String? {
            var headers = ["Last-Modified": modified]
            headers["Date"] = date
            let response = try #require(
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers))
            return TrackTransfer.validator(of: response)
        }
        #expect(try validator(nil) == nil)
        #expect(try validator(modified) == nil)
        #expect(try validator("Fri, 20 Nov 2026 12:01:00 GMT") == modified)
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

    @Test func cancelledPartialBytesLeaveTheStorageTotal() throws {
        let started = Started()
        let store = try makeStore(started)
        let transfer = store.transfer(for: Song(id: "cancel", title: "Cancel", suffix: "flac"), client: client)
        transfer.begin(length: 100, validator: nil)
        transfer.append(Data(count: 40))
        store.rescan()
        #expect(store.cacheBytes == 40)
        store.cancelTransfers()
        #expect(store.cacheBytes == 0)
        #expect(store.offline.isEmpty)
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

    @Test func offlinePlaybackUsesLocalFilesWithoutStartingATransfer() async throws {
        let started = Started()
        let store = try makeStore(started)
        let song = Song(id: "local", title: "Local", suffix: "flac")
        let local = root.appending(path: "cache/local.flac")
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: local)
        store.networkAllowed = false
        guard case .file(let found) = try await store.source(for: song, client: client) else {
            Issue.record("Offline playback must use the local file")
            return
        }
        #expect(found == local)
        await #expect(throws: TrackStore.Failure.offline) {
            try await store.source(for: Song(id: "missing", title: "Missing", suffix: "flac"), client: client)
        }
        #expect(started.transfers.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func stoppingPreparationKeepsAnExplicitDownload() async throws {
        let started = Started()
        let store = try makeStore(started)
        let song = Song(id: "download", title: "Download", suffix: "flac")
        let recording = WorkIndex.Recording(id: "recording", album: "Fixture", songs: [song])
        store.download(recording, title: "Fixture", client: client)
        for _ in 0..<50 where started.transfers.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let transfer = try #require(started.transfers.first?.transfer)
        store.cancelTransfers()
        transfer.begin(length: 4, validator: nil)
        transfer.append(Data([1, 2, 3, 4]))
        transfer.finish(nil)
        for _ in 0..<50 where !store.isDownloaded(recording) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.isDownloaded(recording))
        #expect(store.isOffline(song))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func completedStreamsInspectEmbeddedArt() async throws {
        let started = Started()
        let store = try makeStore(started)
        let song = Song(id: "art", title: "Art", suffix: "flac")
        var inspected: [String] = []
        store.loaded = { song, _, _ in inspected.append(song.id) }
        let transfer = store.transfer(for: song, client: client)
        transfer.begin(length: 1, validator: nil)
        transfer.append(Data([1]))
        transfer.finish(nil)
        for _ in 0..<50 where inspected.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(inspected == [song.id])
        store.clearAll()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func clearMusicKeepsASharedExplicitDownload() async throws {
        let started = Started()
        let store = try makeStore(started)
        let song = Song(id: "shared", title: "Shared", suffix: "flac")
        let recording = WorkIndex.Recording(id: "shared-recording", album: "Fixture", songs: [song])
        let transfer = store.transfer(for: song, client: client)
        transfer.begin(length: 4, validator: nil)
        transfer.append(Data([1, 2]))
        store.download(recording, title: "Fixture", client: client)
        let obsolete = store.transfer(for: Song(id: "obsolete", title: "Obsolete", suffix: "flac"), client: client)
        obsolete.begin(length: 4, validator: nil)
        obsolete.append(Data([9]))
        store.clearCache()
        #expect(FileManager.default.fileExists(atPath: transfer.partial.path()))
        #expect(!FileManager.default.fileExists(atPath: obsolete.partial.path()))
        #expect(store.cacheBytes == 2)
        #expect(try Self.read(transfer, at: 0, count: 2) == [1, 2])
        transfer.append(Data([3, 4]))
        transfer.finish(nil)
        for _ in 0..<100 where !store.isDownloaded(recording) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.isDownloaded(recording))
        #expect(started.transfers.filter { $0.id == song.id }.count == 1)
        #expect(try Data(contentsOf: root.appending(path: "downloads/shared.flac")) == Data([1, 2, 3, 4]))
        store.clearAll()
        try? FileManager.default.removeItem(at: root)
    }

    @Test(arguments: [false, true])
    func cancellingADownloadReleasesOnlyUnneededTransfers(playbackNeedsTrack: Bool) async throws {
        let started = Started()
        let store = try makeStore(started)
        let song = Song(id: "cancel-download", title: "Cancel download", suffix: "flac")
        let recording = WorkIndex.Recording(id: "cancel-recording", album: "Fixture", songs: [song])
        if playbackNeedsTrack { store.pinned = [song.id] }
        store.download(recording, title: "Fixture", client: client)
        for _ in 0..<100 where started.transfers.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let transfer = try #require(started.transfers.first?.transfer)
        transfer.begin(length: 4, validator: nil)
        transfer.append(Data([1, 2]))
        store.cancelDownload(recording.id)
        #expect(store.progress.isEmpty)
        // The menu shows the cancel at once; the task releases the transfers when it ends.
        for _ in 0..<100 where store.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.failures.isEmpty)
        #expect(store.downloads.isEmpty)
        if playbackNeedsTrack {
            #expect(store.transfers[song.id] === transfer)
            transfer.append(Data([3, 4]))
            transfer.finish(nil)
            #expect(try await transfer.finished() == transfer.target)
        } else {
            #expect(store.transfers.isEmpty)
            await #expect(throws: TrackTransfer.Failure.cancelled) { try await transfer.finished() }
            #expect(!FileManager.default.fileExists(atPath: transfer.partial.path()))
        }
        store.clearAll()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func signOutDiscardsQueuedCompletionCallbacks() async throws {
        let started = Started()
        let store = try makeStore(started)
        let song = Song(id: "account", title: "Account", suffix: "flac")
        var inspected: [String] = []
        store.loaded = { song, _, _ in inspected.append(song.id) }
        let transfer = store.transfer(for: song, client: client)
        transfer.begin(length: 1, validator: nil)
        transfer.append(Data([1]))
        transfer.finish(nil)
        store.clearAll()
        try await Task.sleep(for: .milliseconds(100))
        #expect(inspected.isEmpty)
        #expect(store.offline.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    @Test(arguments: [false, true])
    func failedRecordingsReleaseSharedTracksAfterTheLastOwner(secondSucceeds: Bool) async throws {
        let started = Started()
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults,
            fetch: { _, _ in
                Issue.record("Shared tracks must not start another whole-file request")
                throw TrackTransfer.Failure.storage
            }, transport: { song, _, transfer in started.transfers.append((song.id, transfer)) })
        let shared = Song(id: "shared", title: "Shared", suffix: "flac")
        let first = WorkIndex.Recording(
            id: "first", album: "Fixture", songs: [shared, Song(id: "first-only", title: "First", suffix: "flac")])
        let second = WorkIndex.Recording(
            id: "second", album: "Fixture", songs: [shared, Song(id: "second-only", title: "Second", suffix: "flac")])
        store.download(first, title: "First", client: client)
        store.download(second, title: "Second", client: client)
        for _ in 0..<100 where started.transfers.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let sharedTransfer = try #require(started.transfers.first { $0.id == shared.id }?.transfer)
        sharedTransfer.begin(length: 4, validator: nil)
        sharedTransfer.append(Data([1, 2, 3, 4]))
        sharedTransfer.finish(nil)
        for _ in 0..<100 where started.transfers.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        let firstOnly = try #require(started.transfers.first { $0.id == "first-only" }?.transfer)
        let secondOnly = try #require(started.transfers.first { $0.id == "second-only" }?.transfer)
        firstOnly.finish(.http(500))
        for _ in 0..<100 where store.progress[first.id] != nil { try await Task.sleep(for: .milliseconds(10)) }
        let file = root.appending(path: "downloads/shared.flac")
        #expect(FileManager.default.fileExists(atPath: file.path()))
        if secondSucceeds {
            secondOnly.begin(length: 1, validator: nil)
            secondOnly.append(Data([5]))
            secondOnly.finish(nil)
        } else {
            secondOnly.finish(.http(500))
        }
        for _ in 0..<100 where !store.progress.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.progress.isEmpty)
        #expect(!store.isDownloaded(first))
        #expect(store.isDownloaded(second) == secondSucceeds)
        #expect(FileManager.default.fileExists(atPath: file.path()) == secondSucceeds)
        #expect(started.transfers.filter { $0.id == shared.id }.count == 1)
        store.clearAll()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func sharedDownloadsCountEachPhysicalTrackOnce() async throws {
        let started = Started()
        let store = try makeStore(started)
        let shared = Song(id: "shared", title: "Shared", suffix: "flac")
        let first = WorkIndex.Recording(id: "first", album: "Fixture", songs: [shared])
        let second = WorkIndex.Recording(id: "second", album: "Fixture", songs: [shared])
        store.download(first, title: "First", client: client)
        for _ in 0..<100 where started.transfers.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let transfer = try #require(started.transfers.first?.transfer)
        transfer.begin(length: 4, validator: nil)
        transfer.append(Data([1, 2, 3, 4]))
        transfer.finish(nil)
        for _ in 0..<100 where !store.isDownloaded(first) { try await Task.sleep(for: .milliseconds(10)) }
        store.download(second, title: "Second", client: client)
        for _ in 0..<100 where !store.isDownloaded(second) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.downloads.count == 2)
        #expect(store.downloadBytes == 4)
        #expect(started.transfers.count == 1)
        store.remove(try #require(store.downloads.first { $0.id == first.id }))
        #expect(store.downloadBytes == 4)
        #expect(store.isOffline(shared))
        store.remove(try #require(store.downloads.first { $0.id == second.id }))
        #expect(store.downloadBytes == 0)
        #expect(!store.isOffline(shared))
        store.clearAll()
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
