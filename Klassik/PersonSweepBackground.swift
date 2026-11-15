import BackgroundTasks
import Foundation

/// Lets the system run the Wikidata pass (ADR 0042) while Klassik is in the background. The system picks the
/// time, usually when the phone sleeps. The identifier is in `BGTaskSchedulerPermittedIdentifiers`.
enum PersonSweepBackground {
    static let identifier = "de.whnr.klassik.people"

    /// BGTask is not Sendable. The system calls its expiry handler and the code that ends it from other threads.
    private struct Box: @unchecked Sendable {
        let task: BGTask
    }

    /// Call once at launch, before the app finishes starting.
    @MainActor
    static func register(_ model: AppModel) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let box = Box(task: task)
            let work = Task { @MainActor in
                await model.sweepPeopleInBackground()
                box.task.setTaskCompleted(success: true)
                schedule()
            }
            task.expirationHandler = {
                work.cancel()
                Task { @MainActor in model.sweep.stop() }
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
