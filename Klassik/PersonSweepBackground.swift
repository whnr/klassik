import BackgroundTasks
import Foundation
import TaskRegistry

/// The parts of a launched `BGTask` that the sweep uses.
protocol LaunchedTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: LaunchedTask {}

/// `BGTaskScheduler` behind the Swift 5 boundary of `TaskRegistry`.
private struct SystemScheduler: TaskRegistry {
    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (BGTask) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: queue, launchHandler: launchHandler)
    }
}

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
            on: SystemScheduler(),
            run: { await model.sweepPeopleInBackground() },
            stop: { model.sweep.stop() }
        )
    }

    /// The system calls the launch handler on a background queue. The handler must not inherit the main actor:
    /// Swift 6 checks that isolation on entry and traps.
    @MainActor
    static func register<Registry: TaskRegistry>(
        on registry: Registry,
        run: @escaping @MainActor @Sendable () async -> Void,
        stop: @escaping @MainActor @Sendable () -> Void
    ) where Registry.Launched: LaunchedTask {
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
