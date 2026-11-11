import Testing

@testable import Klassik

@MainActor
struct NavigatorTests {
    typealias Origin = Navigator<String>.Origin

    @Test func startsInLibraryWithoutPages() {
        let navigator = Navigator<String>()
        #expect(navigator.selection == .library)
        for place in Place.allCases { #expect(navigator.pages(in: place).isEmpty) }
    }

    @Test func eachPlaceKeepsItsOwnStack() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.open("page", in: .settings)
        #expect(navigator.pages(in: .library) == ["composer"])
        #expect(navigator.pages(in: .settings) == ["page"])
        #expect(navigator.pages(in: .chronology).isEmpty)
    }

    @Test func aPlaceKeepsItsStackWhileAnotherShows() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.select(.settings)
        navigator.select(.library)
        #expect(navigator.pages(in: .library) == ["composer"])
    }

    @Test func libraryHasNoBackArrow() {
        let navigator = Navigator<String>()
        navigator.select(.settings)
        navigator.select(.library)
        #expect(navigator.backTarget(for: .library) == nil)
    }

    @Test func aPlaceOpenedFromAPageGoesBackToThatPage() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.open("work", in: .library)
        navigator.select(.chronology)
        #expect(navigator.backTarget(for: .chronology) == Origin(place: .library, page: "work"))
        navigator.goBack(from: .chronology)
        #expect(navigator.selection == .library)
        #expect(navigator.pages(in: .library) == ["composer", "work"])
    }

    @Test func aPlaceOpenedFromARootGoesBackToThatRoot() {
        let navigator = Navigator<String>()
        navigator.select(.settings)
        navigator.select(.search)
        #expect(navigator.backTarget(for: .search) == Origin(place: .settings, page: nil))
        navigator.goBack(from: .search)
        #expect(navigator.selection == .settings)
    }

    @Test func aPlaceOpenedFromNowhereGoesBackToLibrary() {
        let navigator = Navigator<String>()
        #expect(navigator.backTarget(for: .settings) == Origin(place: .library, page: nil))
        navigator.goBack(from: .settings)
        #expect(navigator.selection == .library)
    }

    @Test func eachOpeningSetsTheBackTargetAgain() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.select(.settings)
        navigator.select(.library)
        navigator.open("work", in: .library)
        navigator.select(.settings)
        #expect(navigator.backTarget(for: .settings) == Origin(place: .library, page: "work"))
    }

    @Test func aSecondTapOnThePlaceKeepsTheBackTarget() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.select(.settings)
        navigator.select(.settings)
        #expect(navigator.backTarget(for: .settings) == Origin(place: .library, page: "composer"))
    }

    @Test func backFromAPlaceThatShowsLibraryDoesNothing() {
        let navigator = Navigator<String>()
        navigator.goBack(from: .library)
        #expect(navigator.selection == .library)
    }

    @Test func linkToAPageInTheStackPushesItAgain() {
        let navigator = Navigator<String>()
        for page in ["composer", "work", "recording", "composer"] { navigator.open(page, in: .library) }
        #expect(navigator.pages(in: .library) == ["composer", "work", "recording", "composer"])
    }

    @Test func linkToThePageOnTopPushesItAgain() {
        let navigator = Navigator<String>()
        navigator.open("work", in: .library)
        navigator.open("work", in: .library)
        #expect(navigator.pages(in: .library) == ["work", "work"])
    }

    @Test func pathFromTheSystemKeepsRepeatedPages() {
        let navigator = Navigator<String>()
        navigator.setPages(["composer", "work", "composer"], in: .library)
        #expect(navigator.pages(in: .library) == ["composer", "work", "composer"])
        navigator.setPages(["composer"], in: .library)
        #expect(navigator.pages(in: .library) == ["composer"])
        navigator.setPages([], in: .library)
        #expect(navigator.pages(in: .library).isEmpty)
    }

    @Test func aTabTapKeepsTheStackOfThePlaceItLeaves() {
        let navigator = Navigator<String>()
        navigator.setPages(["composer", "work", "composer"], in: .library)
        navigator.select(.chronology)
        navigator.goBack(from: .chronology)
        #expect(navigator.selection == .library)
        #expect(navigator.pages(in: .library) == ["composer", "work", "composer"])
    }

    @Test func aTripAcrossPlacesBacksOutOneArrowAtATime() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.select(.chronology)
        navigator.open("work", in: .chronology)
        navigator.select(.settings)
        #expect(navigator.backTarget(for: .settings) == Origin(place: .chronology, page: "work"))
        navigator.goBack(from: .settings)
        #expect(navigator.selection == .chronology)
        #expect(navigator.backTarget(for: .chronology) == Origin(place: .library, page: "composer"))
        navigator.goBack(from: .chronology)
        #expect(navigator.selection == .library)
        #expect(navigator.pages(in: .chronology) == ["work"])
    }
}
