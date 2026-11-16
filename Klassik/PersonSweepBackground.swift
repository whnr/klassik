import BackgroundTasks
import Foundation

/// The parts of a launched `BGTask` that the sweep uses.
protocol LaunchedTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: LaunchedTask {}

/// The registration call of `BGTaskScheduler`. `@preconcurrency` gives a fake the isolation checks of the
/// Objective-C API, so a test catches a handler that traps when the system calls it off the main thread.
protocol TaskRegistry {
    associatedtype Launched: LaunchedTask
    @preconcurrency
    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (Launched) -> Void
    ) -> Bool
}

extension BGTaskScheduler: TaskRegistry {}

/// Lets the system run the Wikidata pass (ADR 0042) while Klassik is in the background. The system picks the
/// time, usually when the phone sleeps. The identifier is in `BGTaskSchedulerPermittedIdentifiers`.
enum PersonSweepBackground {
    static let identifier = "de.whnr.klassik.people"

    /// BGTask is not Sendable. The system calls its expiry handler and the code that ends it from other threads.
    private struct Box<Value>: @unchecked Sendable {
        let value: Value
    }

    /// Call once at launch, before the app finishes starting.
    @MainActor
    static func register(_ model: AppModel) {
        register(
            on: BGTaskScheduler.shared,
            run: { await model.sweepPeopleInBackground() },
            stop: { model.sweep.stop() }
        )
    }

    @MainActor
    static func register<Registry: TaskRegistry>(
        on registry: Registry,
        run: @escaping @MainActor @Sendable () async -> Void,
        stop: @escaping @MainActor @Sendable () -> Void
    ) {
        registry.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let box = Box(value: task)
            let work = Task { @MainActor in
                await run()
                box.value.setTaskCompleted(success: true)
                schedule()
            }
            task.expirationHandler = {
                work.cancel()
                Task { @MainActor in stop() }
            }
        }
    }

    /// Asks for a later run. Without network the system does not start it.
    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        BGTaskScheduler.shared.submitTaskRequest(request) { _ in }
    }
}
