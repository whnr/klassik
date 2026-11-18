import Testing
import UIKit

@testable import Klassik

@MainActor
struct PlaceTabsTests {
    @Test func onlySearchIsASearchTab() {
        for place in Place.allCases {
            let tab = place.tab(UIViewController())
            #expect((tab is UISearchTab) == (place == .search))
            // Only a search tab that activates search stands apart from the capsule of the other tabs.
            #expect((tab as? UISearchTab)?.automaticallyActivatesSearch ?? (place != .search))
        }
    }

    @Test func theOtherTabsKeepTheirTitleAndPlace() {
        for place in Place.allCases where place != .search {
            let tab = place.tab(UIViewController())
            #expect(tab.title == place.title)
            #expect(tab.identifier == place.rawValue)
        }
    }
}
