import CoreGraphics
import Testing

@testable import Klassik

@MainActor
struct FavouriteTitleTests {
    @Test func theMarkTakesTapsInAHitTargetAroundItself() {
        let mark = CGRect(x: 200, y: 20, width: 22, height: 14)
        let area = FermataShape.hitArea(around: mark)
        #expect(area.width == Measure.hitTarget)
        #expect(area.height == Measure.hitTarget)
        #expect(area.midX == mark.midX)
        #expect(area.midY == mark.midY)
        // The words before the mark take no tap.
        #expect(!area.contains(CGPoint(x: 20, y: 27)))
        #expect(!area.contains(CGPoint(x: mark.minX - Measure.hitTarget, y: mark.midY)))
    }

    @Test func aLargeMarkKeepsItsOwnFrame() {
        let mark = CGRect(x: 0, y: 0, width: Measure.hitTarget * 2, height: Measure.hitTarget * 2)
        #expect(FermataShape.hitArea(around: mark) == mark)
    }

    @Test func noMarkTakesNoTap() {
        #expect(FermataShape.hitArea(around: .null).isNull)
        #expect(!FermataShape.hitArea(around: .null).contains(CGPoint.zero))
    }
}
