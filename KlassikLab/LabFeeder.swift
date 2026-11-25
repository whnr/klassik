import Foundation
import KlassikEngine

/// Downloads one track and hands its bytes to a `TrackTransfer`, after the throttle has delayed them. The engine
/// reads the transfer as it reads a real one, so a slow link or a dropout stresses its refill logic.
final class LabFeeder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// A slice is small, so that the throttle shapes the flow within one network read.
    private static let slice = 16_384

    private let transfer: TrackTransfer
    private let throttle: LabThrottle
    private let lock = NSLock()
    private var session: URLSession?
    // The delegate queue is serial, so these three need no lock.
    private var startedAt = 0.0
    private var passed = 0

    init(transfer: TrackTransfer, throttle: LabThrottle) {
        self.transfer = transfer
        self.throttle = throttle
    }

    func start(_ request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        lock.withLock { self.session = session }
        startedAt = ProcessInfo.processInfo.systemUptime
        session.dataTask(with: request).resume()
    }

    func cancel() {
        let session = lock.withLock { self.session }
        session?.invalidateAndCancel()
        transfer.cancel()
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else { return completionHandler(.allow) }
        guard http.statusCode == 200 else {
            transfer.finish(.http(http.statusCode))
            return completionHandler(.cancel)
        }
        transfer.begin(length: http.expectedContentLength, validator: nil)
        completionHandler(.allow)
    }

    // The wait blocks this delegate queue on purpose: the queue stands for the slow link.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var offset = 0
        while offset < data.count {
            let end = min(offset + Self.slice, data.count)
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let wait = throttle.delay(bytes: end - offset, elapsed: elapsed, passed: passed)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            transfer.append(data.subdata(in: offset..<end))
            passed += end - offset
            offset = end
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        session.finishTasksAndInvalidate()
        transfer.finish(error == nil ? nil : .truncated)
    }
}
