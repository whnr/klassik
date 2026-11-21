import Foundation

/// The bytes of one track while they arrive from the server (ADR 0060). Playback, read-ahead and a download share
/// one transfer, so the same bytes never load twice. A decoder reads on its own worker queue and waits there for
/// missing bytes. The main actor and the render thread never wait.
final class TrackTransfer: NSObject, @unchecked Sendable {
    enum Failure: Error, Equatable {
        case timedOut
        case cancelled
        /// The connection ended before the declared length arrived.
        case truncated
        case http(Int)
        case requiresCompleteFile
        case invalidRead
        case storage
    }

    struct Snapshot: Equatable, Sendable {
        var available: Int64
        var expected: Int64?
        var complete: Bool
    }

    /// A read further than this past the arrived bytes asks the server for a range, if the server allows it.
    static let rangeLead: Int64 = 1 << 20
    static let rangeChunk: Int64 = 1 << 19
    static let keptChunks = 4

    let songID: String
    /// Where the bytes arrive. The file moves to `target` once it is complete; open readers keep working.
    let partial: URL
    let target: URL
    /// The stream address for range requests. Nil turns them off.
    private let url: URL?

    private let condition = NSCondition()
    // `condition` guards every variable below.
    private var available: Int64 = 0
    private var expected: Int64?
    private var headReceived = false
    private var validator: String?
    private var complete = false
    private var failure: Failure?
    private var meter = ThroughputMeter()
    private var chunks: [Int64: Data] = [:]
    /// The server refused a range once, so later reads wait for the sequential bytes.
    private var rangesRefused = false
    private var finishHandlers: [@Sendable (Result<URL, Failure>) -> Void] = []
    private var waiters: [UUID: CheckedContinuation<URL, any Error>] = [:]
    private var descriptor: Int32 = -1
    private var writer: FileHandle?
    private var session: URLSession?

    init(songID: String, partial: URL, target: URL, url: URL?) {
        self.songID = songID
        self.partial = partial
        self.target = target
        self.url = url
        super.init()
        try? FileManager.default.createDirectory(
            at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: partial.path(percentEncoded: false), contents: nil)
        writer = try? FileHandle(forWritingTo: partial)
        descriptor = open(partial.path(percentEncoded: false), O_RDONLY)
        meter.start(at: Self.now)
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }

    // MARK: Network

    /// Starts the sequential request. A constrained network may carry it, because a Play request needs it.
    func start() {
        guard let url else { return }
        let configuration = URLSessionConfiguration.default
        configuration.allowsConstrainedNetworkAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        condition.lock()
        self.session = session
        condition.unlock()
        session.dataTask(with: request).resume()
    }

    /// Stops the transfer and removes its partial bytes.
    func cancel() {
        condition.lock()
        let session = self.session
        condition.unlock()
        finish(.cancelled)
        session?.invalidateAndCancel()
    }

    /// A new network path starts a new throughput measurement.
    func restartMeasurement() {
        condition.lock()
        meter.start(at: Self.now)
        condition.unlock()
    }

    // MARK: Delivery

    /// The response head. `validator` is the ETag or Last-Modified value; a range must carry the same one.
    func begin(length: Int64?, validator: String?) {
        condition.lock()
        expected = length.flatMap { $0 >= 0 ? $0 : nil }
        self.validator = validator
        headReceived = true
        condition.broadcast()
        condition.unlock()
    }

    func append(_ data: Data) {
        condition.lock()
        guard !complete, failure == nil, let writer else { return condition.unlock() }
        do {
            try writer.write(contentsOf: data)
        } catch {
            condition.unlock()
            return finish(.storage)
        }
        available += Int64(data.count)
        meter.record(data.count, at: Self.now)
        condition.broadcast()
        condition.unlock()
    }

    /// Ends the transfer. Without a failure the file is complete and moves to its target in one step.
    func finish(_ failed: Failure?) {
        condition.lock()
        guard !complete, failure == nil else { return condition.unlock() }
        var outcome = failed
        if outcome == nil, let expected, available != expected { outcome = .truncated }
        try? writer?.close()
        writer = nil
        if let outcome {
            failure = outcome
            try? FileManager.default.removeItem(at: partial)
        } else {
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: partial, to: target)
                complete = true
                expected = available
            } catch {
                failure = .truncated
                try? FileManager.default.removeItem(at: partial)
            }
        }
        chunks = [:]
        let handlers = finishHandlers
        finishHandlers = []
        let waiters = self.waiters.values
        self.waiters = [:]
        let result: Result<URL, Failure> = failure.map { .failure($0) } ?? .success(target)
        condition.broadcast()
        condition.unlock()
        for handler in handlers { handler(result) }
        for waiter in waiters { waiter.resume(with: result.mapError { $0 as any Error }) }
    }

    /// Calls `handler` once, when the transfer ends. A transfer that already ended calls it at once.
    func whenFinished(_ handler: @escaping @Sendable (Result<URL, Failure>) -> Void) {
        condition.lock()
        if complete || failure != nil {
            let result: Result<URL, Failure> = failure.map { .failure($0) } ?? .success(target)
            condition.unlock()
            return handler(result)
        }
        finishHandlers.append(handler)
        condition.unlock()
    }

    /// Waits for the end of the transfer.
    func finished() async throws -> URL {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                condition.lock()
                if Task.isCancelled {
                    condition.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if complete || failure != nil {
                    let result: Result<URL, Failure> = failure.map { .failure($0) } ?? .success(target)
                    condition.unlock()
                    continuation.resume(with: result.mapError { $0 as any Error })
                } else {
                    waiters[id] = continuation
                    condition.unlock()
                }
            }
        } onCancel: {
            // Cancelling one consumer must not cancel the bytes that another consumer still needs.
            self.condition.lock()
            let waiter = self.waiters.removeValue(forKey: id)
            self.condition.unlock()
            waiter?.resume(throwing: CancellationError())
        }
    }

    var snapshot: Snapshot {
        condition.lock()
        defer { condition.unlock() }
        return Snapshot(available: available, expected: expected, complete: complete)
    }

    /// The delivered rate in bits per second, or nil before the first window of this path.
    var throughput: Double? {
        condition.lock()
        defer { condition.unlock() }
        return complete ? nil : meter.bitsPerSecond(at: Self.now)
    }

    // MARK: Reading

    /// Copies up to `count` bytes from `position`. It waits on the calling thread until they arrive, the transfer
    /// ends, `isCancelled` turns true, or `timeout` passes. It returns fewer bytes only at the end of the file.
    /// A missing range is never read as zeros or as the end of the file.
    func read(
        at position: Int64, count: Int, into destination: UnsafeMutableRawPointer, timeout: Duration,
        isCancelled: () -> Bool
    ) throws(Failure) -> Int {
        guard position >= 0, count >= 0, position <= Int64.max - Int64(count) else { throw .invalidRead }
        let deadline = ContinuousClock.now + timeout
        condition.lock()
        while true {
            if let failure {
                condition.unlock()
                throw failure
            }
            let end = expected.map { min(position + Int64(count), $0) } ?? position + Int64(count)
            if available >= end || complete {
                let copied = Self.copy(
                    descriptor, from: position, count: Int(max(0, min(end, available) - position)), into: destination)
                let wanted = Int(max(0, min(end, available) - position))
                condition.unlock()
                guard copied == wanted else { throw .storage }
                return copied
            }
            if let chunk = chunk(covering: position, end: end) {
                let offset = Int(position - chunk.start)
                let length = Int(end - position)
                chunk.data.withUnsafeBytes { bytes in
                    destination.copyMemory(from: bytes.baseAddress!.advanced(by: offset), byteCount: length)
                }
                condition.unlock()
                return length
            }
            if let url, let expected, position >= available + Self.rangeLead {
                guard let validator, Self.isSafeValidator(validator), !rangesRefused else {
                    condition.unlock()
                    throw .requiresCompleteFile
                }
                condition.unlock()
                let length = min(Self.rangeChunk, expected - position)
                let data = Self.fetchRange(url, from: position, length: length, total: expected, validator: validator)
                condition.lock()
                if failure != nil || complete { continue }
                if let data {
                    chunks[position] = data
                    while chunks.count > Self.keptChunks, let oldest = chunks.keys.min() { chunks[oldest] = nil }
                    continue
                }
                rangesRefused = true
            }
            if isCancelled() {
                condition.unlock()
                throw .cancelled
            }
            let now = ContinuousClock.now
            if now >= deadline {
                condition.unlock()
                throw .timedOut
            }
            // A short wait, so that a cancelled reader leaves soon without a signal of its own.
            _ = condition.wait(until: Date.now.addingTimeInterval(min(0.1, now.duration(to: deadline) / .seconds(1))))
        }
    }

    /// The file length from the response head. It waits like `read`; nil means that the server sent none.
    func length(timeout: Duration, isCancelled: () -> Bool) throws(Failure) -> Int64? {
        let deadline = ContinuousClock.now + timeout
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let failure { throw failure }
            if complete || headReceived { return expected }
            if isCancelled() { throw .cancelled }
            let now = ContinuousClock.now
            if now >= deadline { throw .timedOut }
            _ = condition.wait(until: Date.now.addingTimeInterval(min(0.1, now.duration(to: deadline) / .seconds(1))))
        }
    }

    private func chunk(covering position: Int64, end: Int64) -> (start: Int64, data: Data)? {
        for (start, data) in chunks where start <= position && end <= start + Int64(data.count) {
            return (start, data)
        }
        return nil
    }

    private static func copy(
        _ descriptor: Int32, from position: Int64, count: Int, into destination: UnsafeMutableRawPointer
    ) -> Int {
        guard count > 0, descriptor >= 0 else { return 0 }
        var copied = 0
        while copied < count {
            let offset = off_t(position) + off_t(copied)
            let read = pread(descriptor, destination.advanced(by: copied), count - copied, offset)
            if read <= 0 { break }
            copied += read
        }
        return copied
    }

    /// One validated range from the server. A 200 answer to a range request is a whole-file answer, so its bytes
    /// never go at the requested offset; the reader then waits for the sequential transfer.
    private static func fetchRange(
        _ url: URL, from start: Int64, length: Int64, total: Int64, validator: String?
    ) -> Data? {
        guard length > 0, let validator, isSafeValidator(validator) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("bytes=\(start)-\(start + length - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(validator, forHTTPHeaderField: "If-Range")
        let receiver = RangeReceiver(start: start, length: length, total: total, validator: validator)
        let configuration = URLSessionConfiguration.default
        configuration.allowsConstrainedNetworkAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: receiver, delegateQueue: queue)
        session.dataTask(with: request).resume()
        defer { session.invalidateAndCancel() }
        guard receiver.done.wait(timeout: .now() + 10) == .success else { return nil }
        return receiver.result
    }

    /// Separate responses may share bytes only when their validators identify the same representation.
    static func acceptsRange(
        _ response: HTTPURLResponse, bytes: Int, start: Int64, length: Int64, total: Int64, validator: String?
    ) -> Bool {
        guard let validator, isSafeValidator(validator), response.statusCode == 206,
            Int64(bytes) == length, Self.validator(of: response) == validator,
            response.value(forHTTPHeaderField: "Content-Range") == "bytes \(start)-\(start + length - 1)/\(total)"
        else { return false }
        let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
        return encoding == nil || encoding == "identity"
    }

    static func isSafeValidator(_ value: String) -> Bool {
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { return true }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: value) != nil
    }

    /// Reject ignored ranges at the response head, before URLSession can collect a complete resource in memory.
    private final class RangeReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let start: Int64
        private let length: Int64
        private let total: Int64
        private let validator: String
        private let lock = NSLock()
        private var bytes = Data()
        private var success = false
        var result: Data? { lock.withLock { success ? bytes : nil } }

        init(start: Int64, length: Int64, total: Int64, validator: String) {
            self.start = start
            self.length = length
            self.total = total
            self.validator = validator
        }

        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse
        ) async -> URLSession.ResponseDisposition {
            guard let http = response as? HTTPURLResponse,
                TrackTransfer.acceptsRange(
                    http, bytes: Int(length), start: start, length: length, total: total, validator: validator)
            else { return .cancel }
            return .allow
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let accepted = lock.withLock {
                guard Int64(bytes.count) + Int64(data.count) <= length else { return false }
                bytes.append(data)
                return true
            }
            if !accepted { dataTask.cancel() }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            lock.withLock { success = error == nil && Int64(bytes.count) == length }
            done.signal()
        }
    }

    static func validator(of response: HTTPURLResponse) -> String? {
        if let tag = response.value(forHTTPHeaderField: "ETag"), isSafeValidator(tag) { return tag }
        guard let modified = response.value(forHTTPHeaderField: "Last-Modified"),
            let date = response.value(forHTTPHeaderField: "Date")
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let changed = formatter.date(from: modified), let sent = formatter.date(from: date),
            sent.timeIntervalSince(changed) >= 60
        else { return nil }
        // A conservative age separates the HTTP clocks before a date validator joins separate responses.
        return modified
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }
}

extension TrackTransfer {
    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else { return .allow }
        guard http.statusCode == 200 else {
            finish(.http(http.statusCode))
            return .cancel
        }
        // A compressed body has another length than the file, so it gives no length to check.
        let encoding = http.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
        let identity = encoding == nil || encoding == "identity"
        begin(length: identity ? http.expectedContentLength : nil, validator: Self.validator(of: http))
        return .allow
    }
}

extension TrackTransfer: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        session.finishTasksAndInvalidate()
        finish(error == nil ? nil : .truncated)
    }
}
