import Testing

@testable import Klassik

@MainActor
struct NavigatorTests {
    typealias Origin = Navigator<String>.Origin

    @Test func cancelledBackPreviewRestoresTheOriginAndAllStacks() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.select(.search)
        navigator.open("performer", in: .search)
        navigator.select(.chronology)
        let origin = navigator.backTarget(for: .chronology)
        let cancel = navigator.previewBack(from: .chronology)
        #expect(navigator.selection == .search)
        #expect(navigator.pages(in: .search) == ["performer"])
        cancel()
        #expect(navigator.selection == .chronology)
        #expect(navigator.backTarget(for: .chronology) == origin)
        #expect(navigator.pages(in: .library) == ["composer"])
        #expect(navigator.pages(in: .search) == ["performer"])
    }

    @Test func completedBackPreviewConsumesTheOrigin() {
        let navigator = Navigator<String>()
        navigator.select(.search)
        navigator.select(.library)
        _ = navigator.previewBack(from: .library)
        #expect(navigator.selection == .search)
        #expect(navigator.backTarget(for: .library) == nil)
    }

    /// A tab or a link opens Search empty; back from a result keeps the search.
    @Test func aTabOrALinkStartsSearchAfresh() {
        let navigator = Navigator<String>()
        navigator.selectTab(.search)
        #expect(navigator.searchStarts == 1)
        navigator.open("work", in: .search)
        navigator.back()
        #expect(navigator.searchStarts == 1)
        navigator.select(.library)
        navigator.select(.search)
        #expect(navigator.searchStarts == 2)
        navigator.selectTab(.search)
        #expect(navigator.searchStarts == 3)
    }

    /// The tab restores a result page, so back from it must still find the search behind it.
    @Test func aTabThatRestoresAResultKeepsTheSearch() {
        let navigator = Navigator<String>()
        navigator.select(.search)
        navigator.open("work", in: .search)
        navigator.selectTab(.library)
        navigator.selectTab(.search)
        #expect(navigator.pages(in: .search) == ["work"])
        #expect(navigator.searchStarts == 1)
        navigator.goBack(from: .search)
        navigator.select(.search)
        #expect(navigator.searchStarts == 1)
    }

    @Test func composerLinkReturnsToTheChronologyRoot() {
        let navigator = Navigator<String>()
        navigator.open("library composer", in: .library)
        navigator.select(.chronology)
        navigator.open("work", in: .chronology)
        navigator.open("composer", in: .chronology)
        navigator.showChronology()
        #expect(navigator.selection == .chronology)
        #expect(navigator.pages(in: .chronology).isEmpty)
        #expect(navigator.pages(in: .library) == ["library composer"])
        navigator.back()
        #expect(navigator.selection == .library)
    }

    @Test func composerLinkOpensTheChartFromAnotherPlace() {
        let navigator = Navigator<String>()
        navigator.open("old composer", in: .chronology)
        navigator.open("composer", in: .library)
        navigator.showChronology()
        #expect(navigator.selection == .chronology)
        #expect(navigator.pages(in: .chronology).isEmpty)
        navigator.back()
        #expect(navigator.selection == .library)
        #expect(navigator.pages(in: .library) == ["composer"])
    }

    @Test func startsInLibraryWithoutPages() {
        let navigator = Navigator<String>()
        #expect(navigator.selection == .library)
        for place in Place.allCases { #expect(navigator.pages(in: place).isEmpty) }
    }

    @Test func eachPlaceKeepsItsOwnStack() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.open("page", in: .chronology)
        #expect(navigator.pages(in: .library) == ["composer"])
        #expect(navigator.pages(in: .chronology) == ["page"])
        #expect(navigator.pages(in: .search).isEmpty)
    }

    @Test func aPlaceKeepsItsStackWhileAnotherShows() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.select(.chronology)
        navigator.select(.library)
        #expect(navigator.pages(in: .library) == ["composer"])
    }

    @Test func libraryAtLaunchHasNoBackArrow() {
        let navigator = Navigator<String>()
        #expect(navigator.backTarget(for: .library) == nil)
    }

    @Test func libraryReachedFromAnotherPlaceGoesBackToIt() {
        let navigator = Navigator<String>()
        navigator.select(.chronology)
        navigator.open("page", in: .chronology)
        navigator.select(.library)
        #expect(navigator.backTarget(for: .library) == Origin(place: .chronology, page: "page"))
        navigator.goBack(from: .library)
        #expect(navigator.selection == .chronology)
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
        navigator.select(.chronology)
        navigator.select(.search)
        #expect(navigator.backTarget(for: .search) == Origin(place: .chronology, page: nil))
        navigator.goBack(from: .search)
        #expect(navigator.selection == .chronology)
    }

    @Test func aPlaceOpenedFromNowhereGoesBackToLibrary() {
        let navigator = Navigator<String>()
        #expect(navigator.backTarget(for: .chronology) == Origin(place: .library, page: nil))
        navigator.goBack(from: .chronology)
        #expect(navigator.selection == .library)
    }

    @Test func eachOpeningSetsTheBackTargetAgain() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.select(.chronology)
        navigator.select(.library)
        navigator.open("work", in: .library)
        navigator.select(.chronology)
        #expect(navigator.backTarget(for: .chronology) == Origin(place: .library, page: "work"))
    }

    @Test func aSecondTabTapReturnsToTheRoot() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.selectTab(.chronology)
        navigator.open("work", in: .chronology)
        navigator.selectTab(.library)
        #expect(navigator.pages(in: .library) == ["composer"])
        navigator.selectTab(.library)
        #expect(navigator.pages(in: .library).isEmpty)
        #expect(navigator.pages(in: .chronology) == ["work"])
        #expect(navigator.backTarget(for: .library) == Origin(place: .chronology, page: "work"))
    }

    @Test func aSecondTapOnThePlaceKeepsTheBackTarget() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.select(.chronology)
        navigator.select(.chronology)
        #expect(navigator.backTarget(for: .chronology) == Origin(place: .library, page: "composer"))
    }

    @Test func backFromAPlaceThatShowsLibraryDoesNothing() {
        let navigator = Navigator<String>()
        navigator.goBack(from: .library)
        #expect(navigator.selection == .library)
    }

    @Test func backLeavesThePageOnTopOfTheShownPlace() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.open("work", in: .library)
        navigator.back()
        #expect(navigator.selection == .library)
        #expect(navigator.pages(in: .library) == ["composer"])
    }

    @Test func backOnARootReturnsToThePlaceItWasReachedFrom() {
        let navigator = Navigator<String>()
        navigator.open("composer", in: .library)
        navigator.select(.chronology)
        navigator.back()
        #expect(navigator.selection == .library)
        #expect(navigator.pages(in: .library) == ["composer"])
    }

    @Test func backOnLibraryAtLaunchDoesNothing() {
        let navigator = Navigator<String>()
        navigator.back()
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
        navigator.select(.search)
        #expect(navigator.backTarget(for: .search) == Origin(place: .chronology, page: "work"))
        navigator.goBack(from: .search)
        #expect(navigator.selection == .chronology)
        #expect(navigator.backTarget(for: .chronology) == Origin(place: .library, page: "composer"))
        navigator.goBack(from: .chronology)
        #expect(navigator.selection == .library)
        #expect(navigator.pages(in: .chronology) == ["work"])
    }

    @Test func slidingDownKeepsThePageUnderThePlayer() {
        let navigator = Navigator<String>()
        navigator.setPages(["composer", "work", "recording"], in: .library)
        navigator.openPlayer()
        #expect(navigator.isPlayerOpen)
        navigator.closePlayer()
        #expect(!navigator.isPlayerOpen)
        #expect(navigator.selection == .library)
        #expect(navigator.pages(in: .library) == ["composer", "work", "recording"])
    }

    @Test func theEndOfPlaybackClosesThePlayerAndKeepsThePage() {
        let navigator = Navigator<String>()
        navigator.setPages(["composer", "work"], in: .library)
        navigator.openPlayer()
        navigator.playbackChanged(hasItem: true)
        #expect(navigator.isPlayerOpen)
        navigator.playbackChanged(hasItem: false)
        #expect(!navigator.isPlayerOpen)
        #expect(navigator.pages(in: .library) == ["composer", "work"])
    }

    @Test(arguments: Place.allCases, Place.allCases)
    func everyTabLeavesThePlayerOnItsLastPage(underlying: Place, tapped: Place) {
        let navigator = Navigator<String>()
        for place in Place.allCases {
            navigator.setPages(["root-child", place.rawValue], in: place)
        }
        navigator.select(underlying)
        navigator.openPlayer()
        navigator.selectTab(tapped)
        #expect(!navigator.isPlayerOpen)
        #expect(navigator.selection == tapped)
        for place in Place.allCases {
            #expect(navigator.pages(in: place) == ["root-child", place.rawValue])
        }
        navigator.selectTab(tapped)
        #expect(navigator.pages(in: tapped).isEmpty)
    }
}
