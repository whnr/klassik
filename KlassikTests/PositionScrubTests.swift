import Testing

@testable import Klassik

/// The position bar follows the finger and holds the new place until the player arrives there.
struct PositionScrubTests {
    private let lift = ContinuousClock.now

    @Test func theBarFollowsTheFingerWhileItDrags() {
        var scrub = PositionScrub()
        scrub.drag(to: 120)
        #expect(scrub.shown(elapsed: 10) == 120)
    }

    @Test func aLiftSeeksToThePlaceUnderTheFinger() {
        var scrub = PositionScrub()
        scrub.drag(to: 120)
        #expect(scrub.release(at: lift) == 120)
    }

    @Test func aLiftWithoutADragSeeksNowhere() {
        var scrub = PositionScrub()
        #expect(scrub.release(at: lift) == nil)
    }

    /// A cancelled drag seeks nowhere and gives the bar back to the player. A hold after a lift stays.
    @Test func aCancelledDragShowsThePlayerAgain() {
        var scrub = PositionScrub()
        scrub.drag(to: 120)
        scrub.cancel()
        #expect(scrub.shown(elapsed: 10, at: lift) == 10)
        #expect(scrub.release(at: lift) == nil)
        scrub.drag(to: 120)
        _ = scrub.release(at: lift)
        scrub.cancel()
        #expect(scrub.shown(elapsed: 10, at: lift) == 120)
    }

    /// The player restarts the movement after a seek. Its old position must not pull the bar back.
    @Test func theBarHoldsTheNewPlaceUntilThePlayerReportsIt() {
        var scrub = PositionScrub()
        scrub.drag(to: 120)
        _ = scrub.release(at: lift)
        scrub.observe(elapsed: 10)
        #expect(scrub.shown(elapsed: 10, at: lift + .milliseconds(500)) == 120)
        scrub.observe(elapsed: 120.3)
        #expect(scrub.shown(elapsed: 120.3, at: lift + .milliseconds(600)) == 120.3)
        // After the arrival the bar follows the player, also when it plays on past the new place.
        #expect(scrub.shown(elapsed: 125, at: lift + .seconds(1)) == 125)
    }

    @Test func aPlayerThatNeverArrivesGetsTheBarBackAfterTheLongestHold() {
        var scrub = PositionScrub()
        scrub.drag(to: 120)
        _ = scrub.release(at: lift)
        #expect(scrub.shown(elapsed: 10, at: lift + PositionScrub.longestHold) == 10)
    }

    @Test func aNewDragEndsTheHold() {
        var scrub = PositionScrub()
        scrub.drag(to: 120)
        _ = scrub.release(at: lift)
        scrub.drag(to: 30)
        #expect(scrub.release(at: lift) == 30)
        scrub.observe(elapsed: 30)
        #expect(scrub.shown(elapsed: 31.5, at: lift) == 31.5)
    }

    @Test func theFingerPlaceStaysInsideTheMovement() {
        #expect(PositionScrub.seconds(at: 50, width: 200, duration: 300) == 75)
        #expect(PositionScrub.seconds(at: -20, width: 200, duration: 300) == 0)
        #expect(PositionScrub.seconds(at: 260, width: 200, duration: 300) == 300)
        #expect(PositionScrub.seconds(at: 50, width: 0, duration: 300) == 0)
    }

    @Test func theFillIsTheShareThatPlayed() {
        #expect(PositionScrub.share(75, of: 300) == 0.25)
        #expect(PositionScrub.share(400, of: 300) == 1)
        #expect(PositionScrub.share(10, of: 0) == 0)
    }
}
