import Testing
import UIKit

@testable import Klassik

@MainActor
struct PlaceTabsTests {
    /// A search tab stands apart from the capsule, so every place is a plain tab.
    @Test func everyPlaceIsAPlainTab() {
        for place in Place.allCases {
            #expect(!(place.tab(UIViewController()) is UISearchTab))
        }
    }

    @Test func everyTabKeepsItsTitleAndPlace() {
        for place in Place.allCases {
            let tab = place.tab(UIViewController())
            #expect(tab.title == place.title)
            #expect(tab.identifier == place.rawValue)
        }
    }

    /// Chronology shows the specimen lifelines as a template, so the tab bar tints it like the system symbols.
    @Test func chronologyDrawsTheLifelines() throws {
        #expect(Place.chronology.tab(UIViewController()).image != nil)
        let image = try #require(UIImage(named: "Chronology"))
        #expect(image.renderingMode == .alwaysTemplate)
    }
}
