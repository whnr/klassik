import Foundation

/// Loads the tracks of explicit downloads through a session that the system owns. The system keeps its transfers
/// running while Klassik is suspended, and starts Klassik again to hand over the result. A foreground session
/// stops with the app.
final class BackgroundDownloads: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = BackgroundDownloads()

    private let lock = NSLock()
    private var waiters: [Int: CheckedContinuation<URL, any Error>] = [:]
    /// Tasks whose answer was no success, by task identifier.
    private var refused: [Int: Int] = [:]
    private let staging: URL
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
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    waiters[task.taskIdentifier] = continuation
                    lock.unlock()
                    if running == nil { task.resume() }
                    // The task can end between the lookup and the registration above.
                    if task.state == .completed { finish(task, error: task.error) }
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Removes the files of transfers that no download waits for.
    func clearStaged() {
        try? FileManager.default.removeItem(at: staging)
    }

    private func stagedFile(_ songID: String) -> URL? {
        let file = staging.appending(path: songID)
        return FileManager.default.fileExists(atPath: file.path()) ? file : nil
    }

    private func finish(_ task: URLSessionTask, error: (any Error)?) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: task.taskIdentifier)
        let status = refused.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let waiter else { return }
        if let status {
            waiter.resume(throwing: SubsonicError.http(status: status))
        } else if let error {
            waiter.resume(throwing: error)
        } else if let id = task.taskDescription, let file = stagedFile(id) {
            waiter.resume(returning: file)
        } else {
            waiter.resume(throwing: URLError(.cannotParseResponse))
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            lock.lock()
            refused[downloadTask.taskIdentifier] = http.statusCode
            lock.unlock()
            return
        }
        guard let id = downloadTask.taskDescription else { return }
        // The system deletes `location` when this method returns, so the file moves now, also without a waiter.
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let target = staging.appending(path: id)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: location, to: target)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        finish(task, error: error)
    }
}
