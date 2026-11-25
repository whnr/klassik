import Testing

@testable import KlassikLab

struct LabThrottleTests {
    @Test func offNeverWaits() {
        let throttle = LabThrottle(mode: .off)
        #expect(throttle.delay(bytes: 16_384, elapsed: 0, passed: 10_000_000) == 0)
    }

    @Test func slowLinkHoldsTheTransferToItsRate() {
        let throttle = LabThrottle(mode: .slow)
        let rate = LabThrottle.slowBytesPerSecond
        // The first second of bytes may pass at second 1, no sooner.
        #expect(throttle.delay(bytes: Int(rate), elapsed: 0, passed: 0) == 1)
        // A transfer that is behind its rate waits no more.
        #expect(throttle.delay(bytes: 1000, elapsed: 10, passed: 1000) == 0)
    }

    @Test func dropoutsStallAfterTheRunAndEndAtTheCycle() {
        let throttle = LabThrottle(mode: .dropouts)
        let run = LabThrottle.dropoutRun
        let stall = LabThrottle.dropoutStall
        #expect(throttle.delay(bytes: 100, elapsed: 1, passed: 0) == 0)
        #expect(throttle.delay(bytes: 100, elapsed: run, passed: 0) == stall)
        #expect(throttle.delay(bytes: 100, elapsed: run + 1, passed: 0) == stall - 1)
        // The next cycle starts with a run.
        #expect(throttle.delay(bytes: 100, elapsed: run + stall + 1, passed: 0) == 0)
        #expect(throttle.delay(bytes: 100, elapsed: 2 * (run + stall) - 1, passed: 0) == 1)
    }
}
