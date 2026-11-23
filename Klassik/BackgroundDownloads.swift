import Foundation

/// Loads the tracks of explicit downloads through a session that the system owns. The system keeps its transfers
/// running while Klassik is suspended, and starts Klassik again to hand over the result. A foreground session
/// stops with the app.
final class BackgroundDownloads: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = BackgroundDownloads()

    private let lock = NSLock()
    /// Every download that waits for a task. Recordings that share a track join the same task.
    private var waiters: [Int: [(id: UUID, continuation: CheckedContinuation<URL, any Error>)]] = [:]
    /// The system's call that ends a relaunch for background events, held until the session has delivered them.
    private var completion: (() -> Void)?
    /// Tasks whose answer was no success, by task identifier.
    private var refused: [Int: Int] = [:]
    private let staging: URL
    /// Copies the staged file for a later waiter; a test replaces it.
    var copyFile: @Sendable (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }
    private var session: URLSession!

    init(
        identifier: String = "de.whnr.klassik.downloads",
        staging: URL = .applicationSupportDirectory.appending(path: "downloads-incoming")
    ) {
        self.staging = staging
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.allowsConstrainedNetworkAccess = true
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// The file of one track. A transfer that ended while no one waited left its file in the staging folder, so a
    /// download that starts again after a relaunch takes that file, or joins the transfer that still runs.
    func load(_ songID: String, from url: URL) async throws -> URL {
        if let staged = stagedFile(songID) { return staged }
        let running = await session.allTasks.first {
            $0.taskDescription == songID && ($0.state == .running || $0.state == .suspended)
        }
        let task = running ?? session.downloadTask(with: url)
        task.taskDescription = songID
        return try await join(task, resume: running == nil)
    }

    /// Waits for the end of a task. A recording that shares the track joins the same task, so cancelling one wait
    /// stops the task only when no other wait remains.
    func join(_ task: URLSessionTask, resume: Bool) async throws -> URL {
        let id = UUID()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    waiters[task.taskIdentifier, default: []].append((id, continuation))
                    lock.unlock()
                    if resume { task.resume() }
                    // The cancel can run before the registration above.
                    if Task.isCancelled { leave(task, id) }
                    // The task can end between the lookup and the registration above.
                    if task.state == .completed { finish(task, error: task.error) }
                }
            } onCancel: {
                leave(task, id)
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func leave(_ task: URLSessionTask, _ id: UUID) {
        lock.lock()
        let own = waiters[task.taskIdentifier]?.first { $0.id == id }
        waiters[task.taskIdentifier]?.removeAll { $0.id == id }
        let others = !(waiters[task.taskIdentifier] ?? []).isEmpty
        lock.unlock()
        own?.continuation.resume(throwing: CancellationError())
        if !others { task.cancel() }
    }

    /// The number of downloads that wait for a task.
    func waiterCount(_ task: URLSessionTask) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters[task.taskIdentifier]?.count ?? 0
    }

    /// Keeps the system's handler for a relaunch. The session is created by now, so its events arrive and
    /// `urlSessionDidFinishEvents` calls the handler.
    func attach(completion: @escaping () -> Void) {
        lock.lock()
        let earlier = self.completion
        self.completion = {
            earlier?()
            completion()
        }
        lock.unlock()
    }

    private func stagedFile(_ songID: String) -> URL? {
        let file = staging.appending(path: songID)
        return FileManager.default.fileExists(atPath: file.path()) ? file : nil
    }

    func finish(_ task: URLSessionTask, error: (any Error)?) {
        lock.lock()
        let joined = waiters.removeValue(forKey: task.taskIdentifier) ?? []
        let status = refused.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard !joined.isEmpty else { return }
        let staged = task.taskDescription.flatMap(stagedFile)
        // Each download moves its file away, so every waiter after the first gets its own copy. All copies exist
        // before any waiter resumes: the first consumer can move the staged file at once.
        var results: [Result<URL, any Error>] = []
        for index in joined.indices {
            if let status {
                results.append(.failure(SubsonicError.http(status: status)))
            } else if let error {
                results.append(.failure(error))
            } else if let staged {
                if index == 0 {
                    results.append(.success(staged))
                } else {
                    let target = staging.appending(path: "\(staged.lastPathComponent).\(UUID().uuidString)")
                    results.append(Result { try copyFile(staged, target); return target })
                }
            } else {
                results.append(.failure(URLError(.cannotParseResponse)))
            }
        }
        for (entry, result) in zip(joined, results) {
            entry.continuation.resume(with: result)
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        received(location, for: downloadTask, status: status)
    }

    /// Takes the file of a finished transfer. The system deletes `location` when the delegate call returns, so the
    /// file moves now, also when no download waits.
    func received(_ location: URL, for task: URLSessionTask, status: Int?) {
        if let status, !(200..<300).contains(status) {
            lock.lock()
            refused[task.taskIdentifier] = status
            lock.unlock()
            return
        }
        guard let id = task.taskDescription else { return }
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let target = staging.appending(path: id)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: location, to: target)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        finish(task, error: error)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let handler = completion
        completion = nil
        lock.unlock()
        if let handler {
            nonisolated(unsafe) let call = handler
            DispatchQueue.main.async { call() }
        }
    }
}
