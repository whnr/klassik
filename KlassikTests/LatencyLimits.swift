import Foundation

/// Wall-clock limits depend on the speed of the runner, so a shared CI runner makes them flaky.
/// Only the measure job sets `KLASSIK_LATENCY_LIMITS=1`; every other run still executes the test body.
enum LatencyLimits {
    static let enforced = ProcessInfo.processInfo.environment["KLASSIK_LATENCY_LIMITS"] == "1"
}
