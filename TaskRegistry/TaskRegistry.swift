import Dispatch

/// The registration call of `BGTaskScheduler`, so a test can launch the handler with a fake.
///
/// This module builds in the Swift 5 language mode, like the Objective-C API that it stands for. Swift 6 then
/// checks the isolation of a handler on entry here too, and a test catches a handler that traps when the system
/// calls it on a background queue.
public protocol TaskRegistry {
    associatedtype Launched
    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (Launched) -> Void
    ) -> Bool
}
