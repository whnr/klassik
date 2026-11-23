import Foundation
import Testing

@testable import Klassik

/// The wash follows the scroll of the item that the player shows.
@MainActor
struct WashScrollTests {
    @Test func nextItemOpensAtTheTopWhileTheOldListStillScrolls() {
        let scroll = WashScroll()
        let first = UUID()
        let next = UUID()
        scroll.open(first)
        scroll.report(476, from: first)
        #expect(scroll.offset == 476)

        scroll.open(next)
        #expect(scroll.offset == 0)
        // The old list leaves upwards, loses its Next row and clamps its offset.
        scroll.report(350, from: first)
        #expect(scroll.offset == 0)

        scroll.report(12, from: next)
        #expect(scroll.offset == 12)
    }

    @Test func aListOutsideThePlayerDoesNotMoveTheWash() {
        let scroll = WashScroll()
        scroll.open(UUID())
        scroll.report(200, from: nil)
        #expect(scroll.offset == 0)
    }

    @Test func openingTheSameItemKeepsItsScroll() {
        let scroll = WashScroll()
        let item = UUID()
        scroll.open(item)
        scroll.report(80, from: item)
        scroll.open(item)
        #expect(scroll.offset == 80)
    }
}
