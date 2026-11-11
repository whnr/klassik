import Testing

@testable import Klassik

struct PageStackTests {
    @Test func openPushesNewPages() {
        var stack = PageStack<String>()
        stack.open("composer")
        stack.open("work")
        #expect(stack.pages == ["composer", "work"])
    }

    @Test func linkToAPageInTheStackGoesBackToIt() {
        var stack = PageStack<String>()
        for page in ["composer", "work", "recording"] { stack.open(page) }
        stack.open("composer")
        #expect(stack.pages == ["composer"])
    }

    @Test func linkToThePageOnTopChangesNothing() {
        var stack = PageStack<String>()
        stack.open("work")
        stack.open("work")
        #expect(stack.pages == ["work"])
    }

    @Test func pathFromTheSystemKeepsThePageOnce() {
        var stack = PageStack<String>()
        stack.replace(with: ["composer", "work", "composer"])
        #expect(stack.pages == ["composer"])
        stack.replace(with: ["composer", "work"])
        #expect(stack.pages == ["composer", "work"])
        stack.replace(with: [])
        #expect(stack.pages.isEmpty)
    }

    @Test func popToRootEmptiesTheStack() {
        var stack = PageStack<String>()
        stack.open("composer")
        stack.popToRoot()
        #expect(stack.pages.isEmpty)
    }
}

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

    @Test func linkInAPlaceGoesBackToAPageInItsStack() {
        let navigator = Navigator<String>()
        for page in ["composer", "work", "recording"] { navigator.open(page, in: .library) }
        navigator.setPages(["composer", "work", "recording", "composer"], in: .library)
        #expect(navigator.pages(in: .library) == ["composer"])
    }
}
