import Foundation
import Testing

@testable import Klassik

private final class FakeTask: LaunchedTask, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (() -> Void)?
    private var done: CheckedContinuation<Void, Never>?
    private var finished = false

    var expirationHandler: (() -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    func setTaskCompleted(success: Bool) {
        let waiter = lock.withLock {
            finished = true
            defer { done = nil }
            return done
        }
        waiter?.resume()
    }

    func completion() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if finished { return true }
                done = continuation
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

/// Calls the launch handler on a background queue, as `BGTaskScheduler` does.
private final class BackgroundRegistry: TaskRegistry, @unchecked Sendable {
    private var handler: ((FakeTask) -> Void)?

    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (FakeTask) -> Void
    ) -> Bool {
        handler = launchHandler
        return true
    }

    func launch(_ task: FakeTask) {
        DispatchQueue.global().async { self.handler?(task) }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

@MainActor
struct PersonSweepBackgroundTests {
    @Test func launchOffTheMainThreadRunsTheSweep() async {
        let registry = BackgroundRegistry()
        let ran = Flag()
        PersonSweepBackground.register(on: registry, run: { ran.set() }, stop: {})
        let task = FakeTask()
        registry.launch(task)
        await task.completion()
        #expect(ran.isSet)
    }
}
