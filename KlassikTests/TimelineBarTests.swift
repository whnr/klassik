import Testing

@testable import Klassik

/// The geometry of the timeline and what a touch on it does (ADR 0014, 0035).
struct TimelineBarTests {
    /// Three movements of 10, 20 and 10 seconds on a bar of 84 points with gaps of 2: 80 points of segments.
    private let bar = TimelineBar(durations: [10, 20, 10], height: 84, gap: 2)

    // MARK: Segments

    @Test func eachMovementGetsItsShareOfTheBarAfterTheGaps() {
        #expect(
            bar.segments == [
                .init(top: 0, height: 20), .init(top: 22, height: 40), .init(top: 64, height: 20),
            ])
    }

    @Test func movementsWithoutALengthShareTheBarEqually() {
        let bar = TimelineBar(durations: [0, 0], height: 42, gap: 2)
        #expect(bar.segments == [.init(top: 0, height: 20), .init(top: 22, height: 20)])
    }

    @Test func oneMovementFillsTheBar() {
        #expect(TimelineBar(durations: [300], height: 500, gap: 2).segments == [.init(top: 0, height: 500)])
    }

    @Test func aBarTooShortForItsGapsDrawsNoSegments() {
        let bar = TimelineBar(durations: [1, 1, 1], height: 3, gap: 2)
        #expect(bar.segments.map(\.height) == [0, 0, 0])
    }

    @Test func nothingPlayingHasNoSegments() {
        let bar = TimelineBar(durations: [], height: 500, gap: 2)
        #expect(bar.segments.isEmpty)
        #expect(bar.place(at: 10) == nil)
    }

    // MARK: Played part

    @Test func thePlayedPartFillsTheMovementsBeforeAndPartOfTheCurrentOne() {
        #expect(bar.played(movement: 1, position: 5) == [1, 0.25, 0])
    }

    @Test func thePlayedPartNeverPassesTheEndOfAMovement() {
        #expect(bar.played(movement: 0, position: 30) == [1, 0, 0])
        #expect(bar.played(movement: 2, position: -1) == [1, 1, 0])
    }

    // MARK: Scrub

    @Test func aPointInASegmentIsAPlaceInItsMovement() {
        #expect(bar.place(at: 32) == .init(movement: 1, seconds: 5))
    }

    @Test func aPointInAGapIsTheStartOfTheMovementBelow() {
        #expect(bar.place(at: 21) == .init(movement: 1, seconds: 0))
    }

    @Test func aPointAboveTheBarIsTheStartOfTheFirstMovement() {
        #expect(bar.place(at: -40) == .init(movement: 0, seconds: 0))
    }

    @Test func aPointBelowTheBarIsTheEndOfTheLastMovement() {
        #expect(bar.place(at: 400) == .init(movement: 2, seconds: 10))
    }

    @Test func thePlaceOfAPointDrawsAsThePlayedPart() {
        let place = bar.place(at: 74)
        #expect(place == .init(movement: 2, seconds: 5))
        #expect(bar.played(movement: 2, position: 5) == [1, 1, 0.5])
    }

    // MARK: Label

    @Test func theLabelCentresOnTheFinger() {
        #expect(TimelineBar.labelCentre(finger: 300, labelHeight: 40, top: 0, floor: 600) == 300)
    }

    @Test func theLabelStaysWholeAtTheTop() {
        #expect(TimelineBar.labelCentre(finger: 5, labelHeight: 40, top: 0, floor: 600) == 20)
    }

    @Test func theLabelStaysWholeAboveTheFloor() {
        #expect(TimelineBar.labelCentre(finger: 599, labelHeight: 40, top: 0, floor: 600) == 580)
    }

    @Test func aLabelTallerThanTheRoomStartsAtTheTop() {
        #expect(TimelineBar.labelCentre(finger: 50, labelHeight: 120, top: 0, floor: 100) == 60)
    }

    // MARK: Touch

    @Test func aSmallMoveIsStillATap() {
        #expect(TimelineTouch.undecided.moved(dx: 3, dy: 5) == .undecided)
    }

    @Test func aVerticalMoveScrubs() {
        #expect(TimelineTouch.undecided.moved(dx: 4, dy: -12) == .scrub)
    }

    @Test func aSidewaysMoveDoesNotScrub() {
        #expect(TimelineTouch.undecided.moved(dx: 14, dy: 9) == .sideways)
    }

    @Test func aScrubStaysAScrubWhenTheFingerDriftsSideways() {
        #expect(TimelineTouch.scrub.moved(dx: 80, dy: 2) == .scrub)
    }

    @Test func aSidewaysSwipeStaysSidewaysWhenItTurnsDown() {
        #expect(TimelineTouch.sideways.moved(dx: 10, dy: 200) == .sideways)
    }

    @Test func aTapPlaysTheMovementUnderTheFingerFromItsStart() {
        let place = bar.place(at: 74)
        #expect(TimelineTouch.undecided.end(dx: 0, side: .right, at: place) == .play(movement: 2))
    }

    @Test func aScrubMovesToThePlaceUnderTheFinger() {
        let place = bar.place(at: 32)
        #expect(TimelineTouch.scrub.end(dx: 30, side: .left, at: place) == .seek(.init(movement: 1, seconds: 5)))
    }

    /// On the left edge the timeline covers the start of the system back swipe, so it goes back itself.
    @Test func aSwipeToTheRightOnTheLeftEdgeGoesBack() {
        #expect(TimelineTouch.sideways.end(dx: 80, side: .left, at: bar.place(at: 10)) == .back)
    }

    @Test func aShortSwipeOnTheLeftEdgeDoesNothing() {
        #expect(TimelineTouch.sideways.end(dx: 40, side: .left, at: bar.place(at: 10)) == .nothing)
    }

    @Test func aSidewaysSwipeOnTheRightEdgeDoesNothing() {
        #expect(TimelineTouch.sideways.end(dx: -80, side: .right, at: bar.place(at: 10)) == .nothing)
        #expect(TimelineTouch.sideways.end(dx: 80, side: .right, at: bar.place(at: 10)) == .nothing)
    }

    @Test func aTouchWithNothingPlayingDoesNothing() {
        #expect(TimelineTouch.undecided.end(dx: 0, side: .right, at: nil) == .nothing)
        #expect(TimelineTouch.scrub.end(dx: 0, side: .right, at: nil) == .nothing)
    }

    // MARK: Side

    @Test func theTimelineRunsOnTheRightUnlessTheListenerPicksTheLeft() {
        #expect(TimelineSide.standard == .right)
        #expect(TimelineSide(rawValue: "left") == .left)
    }
}
