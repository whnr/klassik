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
        /// The track is larger than the Music limit, and its format cannot play from a rolling window.
        case exceedsStorage
    }

    /// How the store keeps a track, decided when the response head gives its length (ADR 0060).
    enum Sizing: Equatable, Sendable {
        /// The whole file, inside the shared Music limit.
        case whole
        /// A rolling window of this many bytes, for a track larger than the limit. It never becomes a cache file.
        case rolling(Int64)
        case refuse
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
    private var published = false
    private var failure: Failure?
    private var meter = ThroughputMeter()
    private var chunks: [Int64: Data] = [:]
    /// The server refused a range once, so later reads wait for the sequential bytes.
    private var rangesRefused = false
    private var finishHandlers: [@Sendable (Result<URL, Failure>) -> Void] = []
    private var waiters: [UUID: CheckedContinuation<URL, any Error>] = [:]
    private var storage: PartialAudioFile?
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var capacity: Int64?
    private let budget: AudioStorageBudget?
    private let sizing: (@Sendable (Int64?) -> Sizing)?
    /// An explicit download owns the bytes: they stay whole and outside the Music limit.
    private var promoted = false
    /// Read-ahead holds a speculative request while current playback has little buffered audio.
    private var held = false
    /// A blocked write suspended the request and resumes it when it returns.
    private var writing = false
    private var lastPressure = -Double.infinity
    /// Called on the transport queue, with the transfer lock held, when the Music limit blocks a write.
    /// It must not wait for this transfer.
    private let pressure: (@Sendable (TrackTransfer) -> Void)?

    init(
        songID: String, partial: URL, target: URL, url: URL?, capacity: Int64? = nil,
        budget: AudioStorageBudget? = nil, sizing: (@Sendable (Int64?) -> Sizing)? = nil,
        pressure: (@Sendable (TrackTransfer) -> Void)? = nil
    ) {
        self.songID = songID
        self.partial = partial
        self.target = target
        self.url = url
        self.capacity = capacity
        self.budget = budget
        self.sizing = sizing
        self.pressure = pressure
        super.init()
        do {
            storage = try PartialAudioFile(url: partial, capacity: capacity, budget: budget)
        } catch {
            failure = .storage
        }
        meter.start(at: Self.now)
    }

    deinit {
        if complete && !published { try? FileManager.default.removeItem(at: partial) }
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
        guard failure == nil, !complete else {
            condition.unlock()
            session.invalidateAndCancel()
            return
        }
        self.session = session
        let task = session.dataTask(with: request)
        dataTask = task
        let held = held
        condition.unlock()
        if !held { task.resume() }
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
        var refusal: Failure?
        var waiting: [CheckedContinuation<URL, any Error>] = []
        if !promoted, let sizing, failure == nil, storage?.received == 0 {
            switch sizing(expected) {
            case .whole: break
            case .rolling(let window):
                do {
                    storage = try PartialAudioFile(url: partial, capacity: window, budget: budget)
                    capacity = window
                    // A rolling window never completes as a file, so whole-file consumers stop waiting now.
                    waiting = Array(waiters.values)
                    waiters = [:]
                } catch {
                    refusal = .storage
                }
            case .refuse: refusal = .exceedsStorage
            }
        }
        condition.broadcast()
        condition.unlock()
        for waiter in waiting { waiter.resume(throwing: Failure.requiresCompleteFile) }
        if let refusal { finish(refusal) }
    }

    /// An explicit download takes over the bytes. It fails when a rolling window already discarded some of them.
    func promote() -> Bool {
        condition.withLock {
            guard failure == nil, let storage else { return false }
            if complete && !published { return false }
            guard storage.promote() else { return false }
            promoted = true
            capacity = nil
            return true
        }
    }

    /// Suspends or resumes the network request, without effect on bytes that already arrived.
    func hold(_ value: Bool) {
        condition.lock()
        defer { condition.unlock() }
        guard held != value else { return }
        held = value
        guard !writing else { return }
        if value { dataTask?.suspend() } else { dataTask?.resume() }
    }

    var isHeld: Bool { condition.withLock { held } }

    /// Finite writes wait on the transport queue. Main-actor and render callbacks must never append there.
    func append(_ data: Data) {
        condition.lock()
        if let expected, Int64(data.count) > expected - available {
            condition.unlock()
            return finish(.truncated)
        }
        var offset = 0
        var suspended = false
        defer {
            if suspended {
                writing = false
                if !held { dataTask?.resume() }
            }
            condition.unlock()
        }
        while offset < data.count {
            guard !complete, failure == nil, let storage else { return }
            let count = min(data.count - offset, Int(min(storage.writableBytes, Int64(Int.max))))
            if count > 0 {
                do {
                    let part = offset == 0 && count == data.count ? data : data.subdata(in: offset..<(offset + count))
                    try storage.append(part)
                    offset += count
                    available += Int64(count)
                    meter.record(count, at: Self.now)
                    condition.broadcast()
                    continue
                } catch PartialAudioFile.Failure.full {
                } catch {
                    condition.unlock()
                    finish(.storage)
                    condition.lock()
                    return
                }
            }
            if !suspended {
                dataTask?.suspend()
                suspended = true
                writing = true
            }
            if storage.isBlockedByBudget, Self.now - lastPressure >= 0.5 {
                lastPressure = Self.now
                pressure?(self)
            }
            _ = condition.wait(until: Date.now.addingTimeInterval(0.1))
        }
    }

    /// Receiving the resource end does not restore discarded bytes. Only a whole file can publish to its target.
    func finish(_ failed: Failure?) {
        condition.lock()
        guard !complete, failure == nil else { return condition.unlock() }
        var outcome = failed
        if outcome == nil, let expected, available != expected { outcome = .truncated }
        if let outcome {
            failure = outcome
            try? FileManager.default.removeItem(at: partial)
            // Closing the file releases its reservation, so the Music limit frees the bytes at once.
            storage = nil
        } else {
            do {
                guard let storage else { throw Failure.storage }
                if storage.isWhole {
                    try storage.publish(to: target)
                    published = true
                }
                complete = true
                expected = available
            } catch {
                failure = .storage
                try? FileManager.default.removeItem(at: partial)
                self.storage = nil
            }
        }
        chunks = [:]
        let handlers = finishHandlers
        finishHandlers = []
        let waiters = self.waiters.values
        self.waiters = [:]
        let result = completionResult()
        let stoppedSession = failure == nil ? nil : session
        condition.broadcast()
        condition.unlock()
        stoppedSession?.invalidateAndCancel()
        for handler in handlers { handler(result) }
        for waiter in waiters { waiter.resume(with: result.mapError { $0 as any Error }) }
    }

    /// Calls `handler` once, when the transfer ends. A transfer that already ended calls it at once.
    func whenFinished(_ handler: @escaping @Sendable (Result<URL, Failure>) -> Void) {
        condition.lock()
        if complete || failure != nil {
            let result = completionResult()
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
                } else if capacity != nil && failure == nil {
                    condition.unlock()
                    continuation.resume(throwing: Failure.requiresCompleteFile)
                } else if complete || failure != nil {
                    let result = completionResult()
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

    var hasCompleteFile: Bool { condition.withLock { published } }

    /// Call with the transfer lock held. A received rolling resource still lacks discarded file bytes.
    private func completionResult() -> Result<URL, Failure> {
        if let failure { return .failure(failure) }
        return published ? .success(target) : .failure(.requiresCompleteFile)
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
            if complete && position >= available {
                condition.unlock()
                return 0
            }
            let end = expected.map { min(position + Int64(count), $0) } ?? position + Int64(count)
            if available >= end || complete, storage?.contains(position..<max(position, end)) == true {
                let wanted = Int(max(0, min(end, available) - position))
                if wanted == 0 {
                    condition.unlock()
                    return 0
                }
                do {
                    guard let storage else { throw Failure.storage }
                    let copied = try storage.read(at: position, count: wanted, into: destination)
                    if let capacity {
                        storage.discard(before: position + Int64(copied) - min(Self.rangeChunk, capacity / 4))
                        condition.broadcast()
                    }
                    condition.unlock()
                    return copied
                } catch {
                    condition.unlock()
                    throw .storage
                }
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
            let arrivedEnd = min(end, available)
            let discarded = position < arrivedEnd && storage?.contains(position..<arrivedEnd) != true
            if let url, let expected, discarded || position >= available + Self.rangeLead {
                guard let validator, Self.isSafeValidator(validator), !rangesRefused else {
                    condition.unlock()
                    throw .requiresCompleteFile
                }
                condition.unlock()
                let length = min(Self.rangeChunk, expected - position)
                let data = Self.fetchRange(url, from: position, length: length, total: expected, validator: validator)
                condition.lock()
                if failure != nil { continue }
                if let data {
                    chunks[position] = data
                    while chunks.count > Self.keptChunks, let oldest = chunks.keys.min() { chunks[oldest] = nil }
                    continue
                }
                rangesRefused = true
            }
            if discarded {
                condition.unlock()
                throw .requiresCompleteFile
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

extension TrackTransfer.Failure: LocalizedError {
    /// Storage failures are the listener's to fix, so they name Local Storage (ADR 0060).
    var errorDescription: String? {
        switch self {
        case .storage: "The device could not store this track. Free some space and play again."
        case .exceedsStorage: "This track is larger than the Music limit. Raise the limit in Local Storage."
        // Playback meets this only when a rolling window cannot serve a decoder that needs the whole file.
        case .requiresCompleteFile:
            "This track must load whole, and it is larger than the Music limit. Raise the limit in Local Storage."
        default: nil
        }
    }
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
