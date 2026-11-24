import XCTest

// Each area is one class, and each test starts from a reset app and keeps a few screenshots. So a UI change can
// walk only its own area, and one failed test does not stop the screenshots of the others. scripts/screens.sh
// takes the class names without "Screens" in KLASSIK_UI. scripts/screen_report.py reads the names of the
// screenshots from the snap calls in this file.

/// The three places, the stack of each place and the back arrow between them.
final class PlacesScreens: ScreensTestCase {
    @MainActor
    func testLibrary() throws {
        let app = try launchAndConnect(snapConnect: true, openComposers: false)
        XCTAssertTrue(app.buttons["library-favourites"].exists)
        snap(app, "02-library")
        app.buttons["library-composers"].tap()
        XCTAssertTrue(composer(app, "Felix Mendelssohn").waitForExistence(timeout: 30))
        snap(app, "02d-composers")
        // The title must clear the system top blur, with the specimen gap below the bar.
        // The type style's line box reaches above the glyphs, so the check reads the drawn ink.
        let heading = app.staticTexts["page-heading"]
        XCTAssertTrue(heading.exists)
        let title = drawn(heading, in: app)
        XCTAssertGreaterThanOrEqual(
            title.minY, app.navigationBars.firstMatch.frame.maxY + Layout.headTop - 1, "Title ink \(title)")
        expectPageEdges(title, in: app, "Composers title")
        let rows = app.buttons.matching(identifier: "composer")
        XCTAssertGreaterThan(rows.count, 1, "The list has no two composers")
        expectHairline(between: rows.element(boundBy: 0), and: rows.element(boundBy: 1), in: app, "Composer hairline")
    }

    @MainActor
    func testLibraryEditMode() throws {
        let app = try launchAndConnect(openComposers: false)
        let composers = app.buttons["library-composers"]
        let favourites = app.buttons["library-favourites"]
        XCTAssertLessThan(composers.frame.minY, favourites.frame.minY)
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        snap(app, "02e-library-edit")
        // Move the last row above the first row, clear of the footer below the list.
        let reorder = { (name: String) in
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder \(name)")).firstMatch
        }
        XCTAssertTrue(reorder("Favourites").exists, "No reorder control on Favourites")
        // A drag that the list takes as a scroll leaves the order alone, so the walk drags again, up to three times.
        for _ in 0..<3 where !(favourites.frame.minY < composers.frame.minY) {
            reorder("Favourites").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(
                    forDuration: 0.1,
                    thenDragTo: reorder("Composers").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.5)
            _ = eventually(timeout: 3) { favourites.frame.minY < composers.frame.minY }
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        XCTAssertLessThan(favourites.frame.minY, composers.frame.minY, "The drag did not move Favourites up")
    }

    @MainActor
    func testThreePlaces() throws {
        let app = try launchAndConnect(openComposers: false)
        for name in ["Library", "Chronology", "Search"] {
            XCTAssertTrue(tab(app, name).exists, "No tab \(name)")
        }
        // At launch, Library has no place behind it and no back arrow.
        XCTAssertFalse(app.buttons["place-back"].exists)

        openPlace(app, "Chronology")
        expectBackArrow(app, to: "Library")
        snap(app, "02f-chronology")

        openPlace(app, "Search")
        expectBackArrow(app, to: "Chronology")
        snap(app, "02g-search")

        XCTAssertFalse(tab(app, "Settings").exists)
        app.buttons["place-back"].tap()
        XCTAssertTrue(app.navigationBars["Chronology"].waitForExistence(timeout: 10))
        expectBackArrow(app, to: "Library")

        // Library reached from another place shows the arrow too.
        openPlace(app, "Library")
        expectBackArrow(app, to: "Chronology")
        snap(app, "02l-library-back-arrow")
    }

    @MainActor
    func testPlaceOpenedFromAPageGoesBackToThatPage() throws {
        let app = try launchAndConnect()
        composer(app, "Frédéric Chopin").tap()
        XCTAssertTrue(app.navigationBars["Frédéric Chopin"].waitForExistence(timeout: 10))
        openPlace(app, "Search")
        expectBackArrow(app, to: "Chopin")
        snap(app, "02i-back-arrow-to-page")
        app.buttons["place-back"].tap()
        XCTAssertTrue(app.navigationBars["Frédéric Chopin"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testSecondTabTapReturnsToRoot() throws {
        let app = try launchAndConnect()
        composer(app, "Felix Mendelssohn").tap()
        XCTAssertTrue(app.navigationBars["Felix Mendelssohn"].waitForExistence(timeout: 10))
        openPlace(app, "Search")
        openPlace(app, "Library")
        XCTAssertTrue(app.navigationBars["Felix Mendelssohn"].waitForExistence(timeout: 10))
        tab(app, "Library").tap()
        XCTAssertTrue(app.buttons["library-composers"].waitForExistence(timeout: 10))
        snap(app, "02n-tab-root")
    }

    /// A swipe from the left edge of a root with an arrow does what the arrow does.
    @MainActor
    func testEdgeSwipeGoesBack() throws {
        let app = try launchAndConnect(openComposers: false)
        openPlace(app, "Chronology")
        expectBackArrow(app, to: "Library")
        swipeFromLeftEdge(app)
        XCTAssertTrue(app.buttons["place-back"].waitForNonExistence(timeout: 10), "The swipe did not go back")
        XCTAssertTrue(tab(app, "Library").isSelected)
        XCTAssertTrue(app.buttons["library-composers"].exists)
    }

    @MainActor
    func testRepeatedEdgeBackFromRows() throws {
        let app = try launchAndConnect()
        for _ in 0..<3 {
            let row = composer(app, "Felix Mendelssohn")
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            XCTAssertTrue(app.navigationBars["Felix Mendelssohn"].waitForExistence(timeout: 10))
            let work = app.buttons.matching(identifier: "work").firstMatch
            XCTAssertTrue(work.waitForExistence(timeout: 10))
            let y = work.frame.midY / app.frame.height
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.001, dy: y))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y))
            start.press(forDuration: 0.05, thenDragTo: end)
            XCTAssertTrue(app.staticTexts["page-heading"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["play-work"].exists, "The edge drag opened the work row")
            openPlace(app, "Search")
            swipeFromLeftEdge(app)
            XCTAssertTrue(composer(app, "Felix Mendelssohn").waitForExistence(timeout: 10))
        }
    }

    /// The previous place shows its page as the listener left it, after the arrow and after the swipe.
    @MainActor
    func testBackToThePageAsLeft() throws {
        let app = try launchAndConnect()
        composer(app, "Frédéric Chopin").tap()
        XCTAssertTrue(app.navigationBars["Frédéric Chopin"].waitForExistence(timeout: 10))
        openPlace(app, "Search")
        expectBackArrow(app, to: "Chopin")
        swipeFromLeftEdge(app)
        XCTAssertTrue(app.navigationBars["Frédéric Chopin"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["place-back"].exists)
    }

    /// The check of sz-rs30.1.87. It reads the accessibility label of the system back button only. The screenshots
    /// 02i and 02j show the arrow of a place next to the system back button.
    @MainActor
    func testSystemBackButtonAccessibilityLabel() throws {
        let app = try launchAndConnect()
        composer(app, "Felix Mendelssohn").tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        snap(app, "02j-back-names-page")
        XCTAssertTrue(back.label.contains("Mendelssohn"), "The back button reads \"\(back.label)\"")
    }

    @MainActor
    func testWorkComposerLinkKeepsEachPageInTheStack() throws {
        let app = try launchAndConnect()
        composer(app, "Felix Mendelssohn").tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        let title = app.navigationBars.firstMatch.identifier
        app.buttons["work-composer"].tap()
        XCTAssertTrue(app.navigationBars["Felix Mendelssohn"].waitForExistence(timeout: 10))
        app.buttons.matching(identifier: "work").firstMatch.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
        back(app)
        XCTAssertTrue(app.navigationBars["Felix Mendelssohn"].waitForExistence(timeout: 10))
        back(app)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
        snap(app, "02m-work-composer-back")
    }

    /// The tip comes once, on the second page of a stack: the first page has only the root behind it.
    @MainActor
    func testBackTip() throws {
        let app = try launchAndConnect(arguments: ["-showTips"])
        XCTAssertFalse(app.staticTexts["Hold Back to Go Further"].exists)
        composer(app, "Felix Mendelssohn").tap()
        XCTAssertTrue(app.staticTexts["Hold Back to Go Further"].waitForExistence(timeout: 10))
        snap(app, "02k-back-tip")
    }

    /// Without the test switch, the tip keeps its rule: it shows once, and a later page does not show it again.
    @MainActor
    func testBackTipShowsOnce() throws {
        let app = try launchAndConnect(arguments: ["-tipRules"])
        let tip = app.staticTexts["Hold Back to Go Further"]
        composer(app, "Felix Mendelssohn").tap()
        XCTAssertTrue(tip.waitForExistence(timeout: 10), "The tip does not show the first time")
        back(app)
        XCTAssertTrue(composer(app, "Frédéric Chopin").waitForExistence(timeout: 10))
        composer(app, "Frédéric Chopin").tap()
        XCTAssertTrue(app.navigationBars["Frédéric Chopin"].waitForExistence(timeout: 10))
        XCTAssertFalse(tip.waitForExistence(timeout: 3), "The tip shows a second time")
    }

    /// Every tab stays in the bar when the Search keyboard closes on the Search page before the listener leaves it:
    /// through a recent search and through Enter.
    @MainActor
    func testTabsStayAfterTheSearchKeyboard() throws {
        try expectTabsAfterTheSearchKeyboard(playing: false)
    }

    /// The mini player narrows the bar, so the Search circle has less room.
    @MainActor
    func testTabsStayAfterTheSearchKeyboardWhilePlaying() throws {
        try expectTabsAfterTheSearchKeyboard(playing: true)
    }

    /// A composer filter on the Search page, then two taps on Library: the Search circle must stay in the bar.
    @MainActor
    func testSearchTabStaysAfterAFilterAndTwoLibraryTaps() throws {
        let app = try launchAndConnect(openComposers: false)
        openPlace(app, "Library")
        app.buttons["library-composers"].tap()
        _ = pausedPlayerInLibrary(app)
        openPlace(app, "Library")
        let search = tab(app, "Search")
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        let searchFrame = search.frame
        openPlace(app, "Search")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("chopin\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["search-filters"].tap()
        let term = app.buttons.matching(identifier: "filter-term").firstMatch
        XCTAssertTrue(term.waitForExistence(timeout: 10))
        term.tap()
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForNonExistence(timeout: 5))
        tab(app, "Library").tap()
        tab(app, "Library").tap()
        XCTAssertTrue(app.buttons["library-composers"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            eventually(timeout: 5) { search.exists && search.isHittable && search.frame == searchFrame },
            "The Search circle is gone or moved: \(search.frame) instead of \(searchFrame)")
        snap(app, "02t-search-tab-after-filter-and-two-taps")
    }

    @MainActor
    private func expectTabsAfterTheSearchKeyboard(playing: Bool) throws {
        let app = try launchAndConnect(openComposers: false)
        if playing {
            openPlace(app, "Library")
            app.buttons["library-composers"].tap()
            _ = pausedPlayerInLibrary(app)
        }
        // A second tap on Library returns to its root, so the page behind the bar is the same at each check.
        func libraryRoot() {
            openPlace(app, "Library")
            if !app.buttons["library-composers"].waitForExistence(timeout: 3) { tab(app, "Library").tap() }
            XCTAssertTrue(app.buttons["library-composers"].waitForExistence(timeout: 10))
        }
        libraryRoot()
        let search = tab(app, "Search")
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        let searchFrame = search.frame
        let baseline = try XCTUnwrap(ScreenPixels(app))
        func expectTabs(_ step: String) {
            for name in ["Library", "Chronology", "Search"] {
                let item = tab(app, name)
                XCTAssertTrue(item.waitForExistence(timeout: 5), "\(step): no tab \(name)")
                XCTAssertTrue(item.isHittable, "\(step): tab \(name) is not hittable")
            }
            XCTAssertEqual(search.frame, searchFrame, "\(step): the Search tab moved")
            // A tab can keep its element while UIKit draws nothing, so the Search circle must look as it did before.
            var share = 1.0
            for _ in 0..<6 {
                if let now = ScreenPixels(app) { share = now.differingShare(in: searchFrame, from: baseline) }
                if share < 0.05 { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
            if share >= 0.05 { add(XCTAttachment(string: app.tabBars["tab-row"].debugDescription)) }
            XCTAssertLessThan(share, 0.05, "\(step): the Search circle changed")
        }
        let field = app.textFields["search-field"]
        let recent = app.buttons.matching(identifier: "search-recent")

        // Enter closes the keyboard on the Search page.
        openPlace(app, "Search")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("chopin\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        libraryRoot()
        expectTabs("Enter, then Library")
        if !playing { snap(app, "02o-tabs-after-enter") }

        // The tab opens Search with the keyboard up; a recent search closes it.
        openPlace(app, "Search")
        XCTAssertTrue(recent.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "The Search tab opens no keyboard")
        recent.firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        libraryRoot()
        expectTabs("Recent search, then Library")
        if playing { snap(app, "02q-tabs-after-recent-playing") } else { snap(app, "02p-tabs-after-recent") }
    }

    /// The bar draws no title, and the page still names the back button of the next page.
    @MainActor
    func testBarShowsNoTitle() throws {
        let app = try launchAndConnect()
        composer(app, "Felix Mendelssohn").tap()
        let bar = app.navigationBars["Felix Mendelssohn"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertFalse(bar.staticTexts["Felix Mendelssohn"].exists, "The bar shows the page title")
    }
}

/// The pages that the lookup fills.
final class BrowseScreens: ScreensTestCase {
    /// The field at the top finds works, people and albums in sections. Back from a result keeps the search; a tab
    /// opens Search empty.
    @MainActor
    func testSearch() throws {
        let app = try launchAndConnect(openComposers: false)
        openPlace(app, "Search")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["search-hint"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["page-heading"].exists, "Search shows a large title")
        let arrow = app.buttons["place-back"]
        XCTAssertTrue(arrow.exists)
        XCTAssertGreaterThanOrEqual(field.frame.minY, arrow.frame.maxY - 1, "The field is not under the back arrow")
        XCTAssertLessThan(field.frame.maxY, app.frame.midY, "The field is not at the top")
        XCTAssertLessThan(field.frame.maxY, app.staticTexts["search-hint"].frame.minY, "The hint is above the field")
        snap(app, "19a-search-empty")

        field.tap()
        field.typeText("chopin")
        let works = app.buttons.matching(identifier: "search-work")
        // The results arrive from a search off the main actor, so the rows of a shorter text can show first.
        let four = expectation(for: NSPredicate(format: "count == 4"), evaluatedWith: works)
        XCTAssertEqual(
            XCTWaiter.wait(for: [four], timeout: 10), .completed,
            "\(works.count) works, not the four Chopin nocturnes")
        XCTAssertTrue(app.buttons.matching(identifier: "search-person").firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "search-album").firstMatch.exists)
        field.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Search does not close the keyboard")
        let composerRow = app.buttons.matching(identifier: "search-person").firstMatch
        XCTAssertLessThan(composerRow.frame.minY, works.firstMatch.frame.minY, "Works precede composers")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Composers (")).firstMatch.exists)
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Composers and performers")).firstMatch
                .exists)
        snap(app, "19b-search-results")
        let fieldTop = field.frame.minY
        app.swipeUp()
        XCTAssertEqual(field.frame.minY, fieldTop, accuracy: 1, "The field scrolls with the results")
        app.swipeDown()

        reveal(works.firstMatch, in: app).tap()
        XCTAssertTrue(app.buttons.matching(identifier: "recording").firstMatch.waitForExistence(timeout: 10))
        back(app)
        XCTAssertTrue(works.firstMatch.waitForExistence(timeout: 10), "Back from a result lost the search")
        XCTAssertEqual(field.value as? String, "chopin")

        reveal(app.buttons.matching(identifier: "search-person").firstMatch, in: app).tap()
        XCTAssertTrue(app.navigationBars["Frédéric Chopin"].waitForExistence(timeout: 10))
        back(app)
        XCTAssertTrue(works.firstMatch.waitForExistence(timeout: 10))

        field.tap()
        field.typeText("zzz\n")
        XCTAssertTrue(app.staticTexts["search-no-match"].waitForExistence(timeout: 10))
        snap(app, "19c-search-no-match")

        app.buttons["search-clear"].tap()
        field.tap()
        field.typeText("s\n")
        let people = app.buttons.matching(identifier: "search-person")
        XCTAssertTrue(eventually(timeout: 10) { people.count == 2 })
        XCTAssertTrue(people.element(boundBy: 0).label.contains("Johann Sebastian Bach"))
        XCTAssertTrue(people.element(boundBy: 1).label.contains("Sine Wave Chamber Orchestra"))
        XCTAssertLessThan(people.element(boundBy: 0).frame.minY, people.element(boundBy: 1).frame.minY)
        XCTAssertLessThan(people.element(boundBy: 1).frame.minY, works.firstMatch.frame.minY)

        openPlace(app, "Library")
        openPlace(app, "Search")
        XCTAssertTrue(
            app.buttons.matching(identifier: "search-recent").firstMatch.waitForExistence(timeout: 10),
            "A tab kept the old search")
        XCTAssertFalse(app.buttons["search-clear"].exists)
    }

    /// Filters opens the conditions in a sheet at the medium detent and closes the keyboard. A pick clears the
    /// narrowing field. The badge counts the conditions; the x in the field clears the text only, the x pill clears
    /// the text and the conditions.
    @MainActor
    func testSearchFilters() throws {
        let app = try launchAndConnect(openComposers: false)
        openPlace(app, "Search")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("chopin")
        let works = app.buttons.matching(identifier: "search-work")
        XCTAssertTrue(works.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(works.count, 4)

        let filters = app.buttons["search-filters"]
        filters.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Filters keeps the keyboard up")
        let done = app.buttons["filter-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(done.frame.minY, app.frame.height / 3, "The sheet is not at the medium detent")
        XCTAssertEqual(app.staticTexts["filter-total"].label, "4\u{00A0}recordings")
        // The head and the body share one inset: Back leads the head, the title follows it, and the note and the
        // kinds start under Back; the kinds reach to Done.
        let back = app.buttons["filter-back"]
        let title = app.staticTexts["Filters"]
        XCTAssertGreaterThan(title.frame.minX, back.frame.maxX, "The title does not follow Back")
        let kinds = app.descendants(matching: .any)["filter-scopes"]
        for element in [app.staticTexts["filter-note"], kinds] {
            XCTAssertEqual(element.frame.minX, back.frame.minX, accuracy: 2, "\(element) does not start under Back")
        }
        XCTAssertEqual(kinds.frame.maxX, done.frame.maxX, accuracy: 2, "The kinds end before the sheet inset")
        snap(app, "19d-search-filter-sheet")

        // The text found only Chopin, so other composers leave nothing and do not show.
        let terms = app.buttons.matching(identifier: "filter-term")
        XCTAssertTrue(terms.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(terms.count, 1, "A composer that leaves nothing shows")
        app.buttons["Genres"].tap()
        let romantic = terms.matching(NSPredicate(format: "label CONTAINS %@", "Romantic")).firstMatch
        XCTAssertTrue(romantic.waitForExistence(timeout: 5))
        XCTAssertTrue(romantic.label.contains("2"), "Romantic does not count two recordings: \(romantic.label)")
        romantic.tap()
        let conditions = app.descendants(matching: .any).matching(identifier: "filter-condition")
        XCTAssertTrue(conditions.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["filter-total"].label, "2\u{00A0}recordings")
        let solo = terms.matching(NSPredicate(format: "label CONTAINS %@", "Solo")).firstMatch
        XCTAssertTrue(solo.waitForExistence(timeout: 5))
        XCTAssertTrue(solo.label.contains("and"), "Solo does not offer \"and\": \(solo.label)")

        // With "or" on, the next term joins the condition and its own term shows a check. The checked term sorts
        // first, so only the row under it is sure to be inside the medium detent; the lazy list loads no more.
        app.buttons["filter-or"].tap()
        XCTAssertFalse(terms.matching(NSPredicate(format: "label CONTAINS %@", "Baroque")).firstMatch.exists)
        XCTAssertTrue(romantic.waitForExistence(timeout: 5))
        XCTAssertTrue(romantic.isSelected, "The term of the open condition shows no check")
        let offered = terms.matching(NSPredicate(format: "NOT (label CONTAINS %@)", "Romantic")).firstMatch
        XCTAssertTrue(offered.waitForExistence(timeout: 5))
        XCTAssertNotNil(
            offered.label.range(of: #"\bor \d+$"#, options: .regularExpression),
            "A term does not offer \"or\": \(offered.label)")
        app.buttons["filter-or"].tap()

        // A pick clears the narrowing field.
        app.buttons["Performers"].tap()
        let narrow = app.textFields["filter-narrow"]
        narrow.tap()
        narrow.typeText("pia")
        let pia = terms.matching(NSPredicate(format: "label CONTAINS %@", "Pia Nissimo")).firstMatch
        XCTAssertTrue(pia.waitForExistence(timeout: 5))
        pia.tap()
        XCTAssertTrue(eventually(timeout: 5) { (narrow.value as? String) != "pia" }, "A pick kept the narrowing text")
        XCTAssertEqual(conditions.count, 2)
        snap(app, "19e-search-filter-conditions")

        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertEqual(filters.value as? String, "2\u{00A0}conditions", "The badge does not count the conditions")
        XCTAssertTrue(eventually(timeout: 5) { works.count == 2 }, "The conditions do not narrow the works")
        XCTAssertFalse(app.staticTexts["search-hidden"].exists, "Search shows a hidden-work count")
        snap(app, "19f-search-filtered")

        // The x in the field clears the text only; the conditions stay and still find works.
        app.buttons["search-clear"].tap()
        XCTAssertTrue(eventually(timeout: 5) { works.count == 2 }, "The x in the field cleared the conditions")
        XCTAssertEqual(filters.value as? String, "2\u{00A0}conditions")

        // The x pill clears the text and every condition, and keeps the search of conditions as a recent search.
        app.buttons["search-reset"].tap()
        let recent = app.buttons.matching(identifier: "search-recent")
        XCTAssertTrue(recent.firstMatch.waitForExistence(timeout: 5), "The empty page does not show")
        XCTAssertNotEqual(filters.value as? String, "2\u{00A0}conditions")
        XCTAssertFalse(app.buttons["search-reset"].isEnabled, "The x pill is on with nothing to clear")
    }

    /// A modal sheet dims its page and provides Back without exposing controls behind the sheet.
    @MainActor
    func testSearchSheetBackAndDimming() throws {
        let app = try launchAndConnect(openComposers: false)
        openPlace(app, "Search")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("chopin\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "search-work").firstMatch.waitForExistence(timeout: 10))
        let before = try XCTUnwrap(ScreenPixels(app))
        app.buttons["search-filters"].tap()
        XCTAssertTrue(app.buttons["filter-back"].waitForExistence(timeout: 10))
        let sample = CGRect(x: 8, y: field.frame.maxY + 10, width: 12, height: 60)
        XCTAssertTrue(
            eventually(timeout: 5) {
                guard let after = ScreenPixels(app) else { return false }
                return after.differingShare(in: sample, from: before) > 0.9
            }, "Filters does not dim the page")
        snap(app, "19i-search-modal")
        app.buttons["filter-back"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library-composers"].waitForExistence(timeout: 10), "Back did not leave Search")
        openPlace(app, "Search")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["filter-done"].exists, "The sheet survived Back")
        app.buttons["search-filters"].tap()
        app.buttons["filter-done"].tap()
        app.buttons["place-back"].tap()
        XCTAssertTrue(app.buttons["library-composers"].waitForExistence(timeout: 10))
    }

    /// Search shows its results in typed sections: Composers, Performers, Works, then Albums. Albums holds only
    /// albums, and a recording shows only inside its work. A track title finds its work and the row names that
    /// track.
    @MainActor
    func testSearchSections() throws {
        let app = try launchAndConnect(openComposers: false)
        openPlace(app, "Search")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("chopin\n")
        let works = app.buttons.matching(identifier: "search-work")
        let albums = app.buttons.matching(identifier: "search-album")
        let four = expectation(for: NSPredicate(format: "count == 4"), evaluatedWith: works)
        XCTAssertEqual(XCTWaiter.wait(for: [four], timeout: 10), .completed, "\(works.count) works, not four")
        XCTAssertTrue(albums.firstMatch.exists, "No album for Chopin")
        XCTAssertFalse(app.buttons["search-recording"].exists, "Search lists a recording apart from its work")
        let heading = { (title: String) in
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title) (")).firstMatch
        }
        XCTAssertEqual(heading("Albums").label, "Albums (\(albums.count))", "Albums counts more than its albums")
        XCTAssertLessThan(heading("Works").frame.minY, heading("Albums").frame.minY, "Albums precede works")
        XCTAssertLessThan(works.element(boundBy: 3).frame.minY, albums.firstMatch.frame.minY)
        snap(app, "19j-search-sections")

        // A movement title finds the work, not the album, and the row says which track matched.
        app.buttons["search-clear"].tap()
        field.tap()
        field.typeText("sarabande\n")
        XCTAssertTrue(works.firstMatch.waitForExistence(timeout: 10), "A track title finds no work")
        XCTAssertEqual(works.count, 1)
        XCTAssertTrue(works.firstMatch.label.contains("Cello Suite No. 1"), works.firstMatch.label)
        XCTAssertTrue(works.firstMatch.label.contains("Track: "), "The row does not name the track")
        XCTAssertTrue(works.firstMatch.label.contains("Sarabande"), works.firstMatch.label)
        XCTAssertFalse(albums.firstMatch.exists, "A tagged track title finds its album")
        snap(app, "19k-search-track-match")
    }

    /// A swipe down on the rows of a sheet with a grabber closes it, as on every system sheet.
    @MainActor
    func testSwipeDownClosesTheFilterSheet() throws {
        let app = try launchAndConnect(openComposers: false)
        openPlace(app, "Search")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("chopin\n")
        XCTAssertTrue(app.buttons.matching(identifier: "search-work").firstMatch.waitForExistence(timeout: 10))
        app.buttons["search-filters"].tap()
        let term = app.buttons.matching(identifier: "filter-term").firstMatch
        XCTAssertTrue(term.waitForExistence(timeout: 10))
        swipeSheetDown(from: term, in: app)
        XCTAssertTrue(app.buttons["filter-done"].waitForNonExistence(timeout: 5), "A swipe down left Filters open")
        XCTAssertTrue(field.isHittable)
    }

    @MainActor
    func testSwipeDownClosesTheChronologyWorks() throws {
        let app = try launchAndConnect()
        openPlace(app, "Chronology")
        let brahms = app.buttons.matching(identifier: "chronology-line")
            .matching(NSPredicate(format: "label == 'Johannes Brahms'")).firstMatch
        XCTAssertTrue(brahms.waitForExistence(timeout: 30), "The overview shows no line for Brahms")
        brahms.tap()
        let undated = app.buttons.matching(identifier: "chronology-works").firstMatch
        XCTAssertTrue(undated.waitForExistence(timeout: 30), "Brahms shows no counted row")
        undated.tap()
        let listed = app.buttons.matching(identifier: "chronology-listed-work").firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 10))
        swipeSheetDown(from: listed, in: app)
        XCTAssertTrue(listed.waitForNonExistence(timeout: 5), "A swipe down left the works sheet open")
        XCTAssertTrue(app.buttons["chronology-name"].isHittable)
    }

    /// The overview of the composers with life dates, then one composer among the contemporaries, the scrub, the
    /// name link and the way back to the overview. Bach has no Wikidata answer, so he stays
    /// off the chart.
    @MainActor
    func testChronology() throws {
        let app = try launchAndConnect()
        openPlace(app, "Chronology")
        let lines = app.buttons.matching(identifier: "chronology-line")
        let chopin = lines.matching(NSPredicate(format: "label == 'Frédéric Chopin'")).firstMatch
        XCTAssertTrue(chopin.waitForExistence(timeout: 30), "The overview shows no line for Chopin")
        XCTAssertTrue(app.staticTexts["All composers"].exists, "The Chronology does not open on the overview")
        let five = expectation(for: NSPredicate(format: "count == 5"), evaluatedWith: lines)
        XCTAssertEqual(
            XCTWaiter.wait(for: [five], timeout: 30), .completed,
            "The overview holds \(lines.count) lines, not the five composers with life dates")
        XCTAssertFalse(lines.matching(NSPredicate(format: "label CONTAINS 'Bach'")).firstMatch.exists)
        snap(app, "02b-chronology-overview")

        chopin.tap()
        let name = app.buttons["chronology-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "A tap on a line does not open the composer")
        XCTAssertEqual(name.label, "Frédéric Chopin")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1810–1849'")).firstMatch.exists,
            "The facts line does not give the life")
        // Mendelssohn, Beethoven and Brahms were active in Chopin's window: their lines stand beside his.
        for other in ["Felix Mendelssohn", "Ludwig van Beethoven", "Johannes Brahms"] {
            XCTAssertTrue(
                lines.matching(NSPredicate(format: "label == %@", other)).firstMatch.exists, "No lane for \(other)")
        }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chronology-work'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "Chopin shows no rows of works")
        snap(app, "02c-chronology-composer")
        // A row for several works lists them; a work in the list opens its work page.
        let several = app.buttons.matching(identifier: "chronology-works").firstMatch
        if several.exists {
            several.tap()
            let listed = app.buttons.matching(identifier: "chronology-listed-work").firstMatch
            XCTAssertTrue(listed.waitForExistence(timeout: 10), "A row of several works lists none")
            // The sheet head has a leading title and a plain Done on its trailing edge.
            let title = app.staticTexts["sheet-title"]
            let done = app.buttons["sheet-done"]
            XCTAssertTrue(title.exists, "The sheet has no head")
            XCTAssertLessThan(title.frame.minX, app.frame.width / 4, "The sheet title is not leading")
            XCTAssertGreaterThan(done.frame.minX, app.frame.width / 2, "Done is not on the trailing edge")
            snap(app, "02d-chronology-listed")
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
            XCTAssertTrue(listed.isHittable)
            XCTAssertLessThan(title.frame.minY, app.frame.minY + 100)
            snap(app, "02g-chronology-listed-full")
            listed.tap()
            XCTAssertTrue(app.buttons.matching(identifier: "recording").firstMatch.waitForExistence(timeout: 10))
            back(app)
            XCTAssertTrue(name.waitForExistence(timeout: 10))
        }

        // A sideways drag scrubs across the lanes in order; on release the chart moves to the last one, Brahms.
        let chart = app.descendants(matching: .any)["chronology-chart"]
        XCTAssertTrue(chart.exists)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(
                forDuration: 0.1, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
        let brahms = expectation(for: NSPredicate(format: "label == 'Johannes Brahms'"), evaluatedWith: name)
        XCTAssertEqual(XCTWaiter.wait(for: [brahms], timeout: 10), .completed, "The scrub did not move: \(name.label)")
        snap(app, "02e-chronology-scrubbed")

        let undated = app.buttons.matching(identifier: "chronology-works").firstMatch
        XCTAssertTrue(undated.exists, "The single undated work needs a counted list row")
        XCTAssertEqual(undated.label, "No date, 1 work")
        undated.tap()
        let undatedWork = app.buttons.matching(identifier: "chronology-listed-work").firstMatch
        XCTAssertTrue(undatedWork.waitForExistence(timeout: 10), "The single undated work did not open a list")
        snap(app, "02f-chronology-undated")
        expectWorkActions(on: undatedWork, in: app, "02j-chronology-listed-actions")
        app.buttons["Done"].tap()

        // The name opens the composer page.
        name.tap()
        XCTAssertTrue(app.navigationBars["Johannes Brahms"].waitForExistence(timeout: 10))
        let returnToChart = app.buttons["composer-chronology"]
        XCTAssertTrue(returnToChart.waitForExistence(timeout: 10))
        XCTAssertEqual(returnToChart.label, "Back to Chronology")
        snap(app, "02j-composer-back-to-chronology")
        returnToChart.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.label, "Johannes Brahms")

        // All goes back to the overview, which marks the composer last opened.
        app.buttons["chronology-level"].tap()
        XCTAssertTrue(app.staticTexts["All composers"].waitForExistence(timeout: 10))
        snap(app, "02h-chronology-last-opened")

        // Mendelssohn has one dated work, so this check cannot select a grouped row.
        lines.matching(NSPredicate(format: "label == 'Felix Mendelssohn'")).firstMatch.tap()
        XCTAssertTrue(eventually(timeout: 10) { name.label == "Felix Mendelssohn" })
        let single = app.buttons.matching(identifier: "chronology-work").firstMatch
        XCTAssertTrue(single.waitForExistence(timeout: 30), "Mendelssohn shows no single dated work")
        XCTAssertTrue(single.label.contains("Violin Concerto"), single.label)
        expectWorkActions(on: single, in: app, "02i-chronology-work-actions")
    }

    @MainActor
    private func expectWorkActions(on row: XCUIElement, in app: XCUIApplication, _ name: String) {
        let label = row.label
        row.press(forDuration: 1.2)
        let queue = app.buttons["Add to Queue"].firstMatch
        XCTAssertTrue(queue.waitForExistence(timeout: 5), "A long press on \(label) shows no actions")
        XCTAssertTrue(app.buttons["Play Next"].firstMatch.exists, "The actions of \(label) have no Play Next")
        snap(app, name)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(eventually(timeout: 5) { !queue.exists }, "The actions of \(label) stay open")
    }

    /// Mendelssohn has a picture in the fixture answers: it shows under the name, and a tap shows it whole with
    /// its credit. Chopin has none, so his page shows the name on the plain ground.
    @MainActor
    func testComposerPicture() throws {
        let app = try launchAndConnect()
        composer(app, "Felix Mendelssohn").tap()
        let picture = app.descendants(matching: .any)["composer-picture"]
        XCTAssertTrue(picture.waitForExistence(timeout: 30), "The composer page shows no picture")
        // The value gives the picture pixels for each screen pixel at the crop.
        let density = Double(picture.value as? String ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(density, 1, "The hero shows fewer picture pixels than screen pixels")
        snap(app, "03b-composer-picture")

        let mark = app.buttons["favourite-composer"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        let initial = mark.value as? String
        mark.tap()
        XCTAssertNotEqual(mark.value as? String, initial)
        snap(app, "03m-composer-picture-favourite")
        mark.tap()
        XCTAssertEqual(mark.value as? String, initial)

        picture.tap()
        let whole = app.descendants(matching: .any)["whole-picture"]
        XCTAssertTrue(whole.waitForExistence(timeout: 10))
        // The credit ends in the File page link, as in the specimen sheet.
        // Only those words are the link; the author and licence are plain text.
        let credit = app.staticTexts["whole-picture-credit"]
        XCTAssertTrue(credit.exists, "The whole picture shows no credit")
        XCTAssertTrue(credit.label.contains("Public domain"), credit.label)
        XCTAssertTrue(credit.label.hasSuffix("File page"), credit.label)
        XCTAssertTrue(app.links["File page"].exists, "The whole picture credit has no File page link")
        let close = app.buttons["whole-picture-close"]
        XCTAssertTrue(close.exists, "The whole picture shows no close button")
        XCTAssertLessThan(close.frame.maxY, app.frame.height / 4, "The close button is not at the top")
        snap(app, "03c-whole-picture")
        // A swipe down closes the picture, as any full-screen overlay.
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        middle.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(whole.waitForNonExistence(timeout: 10), "A swipe down does not close the whole picture")
        XCTAssertTrue(picture.waitForExistence(timeout: 10))
        picture.tap()
        XCTAssertTrue(whole.waitForExistence(timeout: 10))
        app.buttons["whole-picture-close"].tap()
        XCTAssertTrue(whole.waitForNonExistence(timeout: 10), "The close button does not close the whole picture")
        XCTAssertTrue(picture.waitForExistence(timeout: 10))
        let tabs = app.descendants(matching: .any)["composer-tabs"].firstMatch
        tabs.buttons["About"].tap()
        let article = app.descendants(matching: .any)["credit-text"].firstMatch
        XCTAssertTrue(reveal(article, in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(article.label.contains("Wikipedia, CC BY-SA 4.0"))
        XCTAssertTrue(article.label.contains("Article"))
        let commons = app.descendants(matching: .any)["credit-picture"].firstMatch
        XCTAssertTrue(reveal(commons, in: app).exists)
        XCTAssertTrue(commons.label.contains("Wikimedia Commons"), commons.label)
        snap(app, "03g-composer-article")
    }

    /// The picture runs under the status bar and the Dynamic Island, with the back button beside the island
    /// (sz-rs30.1.102). A light picture, in the light and the dark room.
    @MainActor
    func testLightPictureUnderTheStatusBar() throws {
        snap(try pictureTop(), "03h-picture-top-light-light-room")
        snap(try pictureTop(arguments: ["-darkRoom"]), "03i-picture-top-light-dark-room")
    }

    /// A dark picture under the status bar, in the light and the dark room.
    @MainActor
    func testDarkPictureUnderTheStatusBar() throws {
        snap(try pictureTop(arguments: ["-darkPicture"]), "03j-picture-top-dark-light-room")
        snap(try pictureTop(arguments: ["-darkPicture", "-darkRoom"]), "03k-picture-top-dark-dark-room")
    }

    @MainActor
    private func pictureTop(arguments: [String] = []) throws -> XCUIApplication {
        let app = try launchAndConnect(arguments: arguments)
        composer(app, "Felix Mendelssohn").tap()
        let picture = app.descendants(matching: .any)["composer-picture"]
        XCTAssertTrue(picture.waitForExistence(timeout: 30), "The composer page shows no picture")
        XCTAssertEqual(picture.frame.minY, 0, accuracy: 1, "The picture does not reach the top edge")
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists, "No back button over the picture")
        return app
    }

    @MainActor
    func testMusicBrainz() throws {
        let app = try launchAndConnect()
        openSettings(app, technical: true)
        // The row shows once the library has composers.
        let musicBrainz = app.buttons["musicbrainz"]
        XCTAssertTrue(eventually(timeout: 30) { reveal(musicBrainz, in: app).exists })
        musicBrainz.tap()
        let toConfirm = app.buttons["to-confirm"]
        XCTAssertTrue(toConfirm.waitForExistence(timeout: 10))
        // The lookup may still run right after the connect.
        let counted = expectation(for: NSPredicate(format: "label CONTAINS '1'"), evaluatedWith: toConfirm)
        XCTAssertEqual(XCTWaiter.wait(for: [counted], timeout: 30), .completed, toConfirm.label)
        snap(app, "02c-musicbrainz")
    }

    /// The Wikidata pass looks up the people of the fixture library and ends up to date (ADR 0042).
    @MainActor
    func testPeopleFromWikidata() throws {
        let app = try launchAndConnect()
        openSettings(app, technical: true)
        // The row shows once the library has composers.
        let musicBrainz = app.buttons["musicbrainz"]
        XCTAssertTrue(eventually(timeout: 30) { reveal(musicBrainz, in: app).exists })
        musicBrainz.tap()
        let status = app.descendants(matching: .any)["people-status"]
        XCTAssertTrue(reveal(status, in: app).waitForExistence(timeout: 10))
        let done = expectation(for: NSPredicate(format: "label CONTAINS 'Up to date'"), evaluatedWith: status)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 90), .completed, status.label)
        snap(app, "02e-people-up-to-date")
    }

    @MainActor
    func testSets() throws {
        let app = try launchAndConnect()
        composer(app, "Frédéric Chopin").tap()
        let set = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Nocturnes, Op. 9'")).firstMatch
        XCTAssertTrue(set.waitForExistence(timeout: 10))
        let before = set.frame.minY
        set.tap()
        let member = app.buttons.matching(
            NSPredicate(format: "identifier == 'work' AND label BEGINSWITH 'Nocturne No. 1 in B-flat minor'")
        ).firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: 10))
        // Opening a set keeps its title where it is and pushes the works in below (sz-rs30.1.123).
        XCTAssertEqual(set.frame.minY, before, accuracy: 1, "Opening a set scrolled the list")
        // A list row's frame spans the whole cell, so the inset shows on the title text.
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Nocturne No. 1'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The set member title is not exposed")
        XCTAssertEqual(
            title.frame.minX, app.frame.minX + Layout.setMemberLeading,
            accuracy: 1, "Set members lost their leading inset")
        snap(app, "02a-sets")
        set.tap()
        XCTAssertEqual(set.frame.minY, before, accuracy: 1, "Closing a set scrolled the list")
        XCTAssertEqual(set.value as? String, "Collapsed")
    }

    /// Chopin has no picture: his name sits under the back arrow. His works differ in genre, so chips show, and
    /// two chips join with "or".
    @MainActor
    func testComposerWithoutPicture() throws {
        let app = try launchAndConnect()
        composer(app, "Frédéric Chopin").tap()
        let chips = app.buttons.matching(identifier: "genre-chip")
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 10), "The composer page shows no genre chips")
        XCTAssertFalse(app.descendants(matching: .any)["composer-picture"].exists)
        snap(app, "03d-composer-no-picture")
        checkComposerPage(app)

        app.buttons.matching(NSPredicate(format: "identifier == 'genre-chip' AND label == 'Solo'")).firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "work").firstMatch.waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "identifier == 'genre-chip' AND label == 'Romantic'")).firstMatch
            .tap()
        snap(app, "03e-composer-chips")
        checkTabs(app, "composer-tabs", from: "Works", to: "About")
        snap(app, "03f-composer-about")
    }

    @MainActor
    func testOfflineComposerFavourite() throws {
        let app = try launchAndConnect(arguments: ["-offlineFavourites"])
        composer(app, "Frédéric Chopin").tap()
        let mark = app.buttons["favourite-composer"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.value as? String, "Not a favourite")
        mark.tap()
        XCTAssertEqual(mark.value as? String, "Favourite")
        snap(app, "03k-composer-favourite")
        back(app, times: 2)
        app.buttons["library-favourites"].tap()
        let row = app.buttons["favourite-composer-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        snap(app, "03l-favourite-composer-list")
        row.tap()
        XCTAssertEqual(mark.value as? String, "Favourite")
        mark.tap()
        XCTAssertEqual(mark.value as? String, "Not a favourite")
        openSettings(app, technical: true)
        reveal(app.buttons["diagnostics"], in: app).tap()
        let pending = app.descendants(matching: .any)["pending-favourite"].firstMatch
        XCTAssertTrue(reveal(pending, in: app).exists)
        XCTAssertTrue(pending.label.contains("Frédéric Chopin"), pending.label)
        snap(app, "11a-pending-favourites")

        // Two choices for one person wait as one: the newest. The offline send of a pull keeps it waiting.
        let rows = app.descendants(matching: .any).matching(identifier: "pending-favourite")
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(
            [pending.label, pending.value as? String ?? ""].joined().contains("Not a favourite"), pending.label)
        for _ in 0..<3 { app.swipeDown() }
        let checked = app.descendants(matching: .any)["opensubsonic"].firstMatch
        XCTAssertTrue(checked.waitForExistence(timeout: 20), "Diagnostics lost the server after the pull")
        XCTAssertTrue(reveal(pending, in: app).exists)
        XCTAssertEqual(rows.count, 1)
        snap(app, "11b-pending-after-pull")
    }

    /// The Fifth has two recordings in the fixture, so a hairline lies between their rows.
    @MainActor
    func testRecordingHairline() throws {
        let app = try launchAndConnect()
        composer(app, "Ludwig van Beethoven").tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        checkRecordingHairline(app)
    }

    /// Wikidata also finds Beethoven's relatives and friends, his grandfather with his full name. The tag gives
    /// the full name, so the page takes the composer without a pick list (sz-rs30.1.131.2). Choose Composer
    /// Again lists them all, and a tap on a row's title picks that person.
    @MainActor
    func testComposerAmongNamesakes() throws {
        let app = try launchAndConnect()
        composer(app, "Ludwig van Beethoven").tap()
        let tabs = app.descendants(matching: .any)["composer-tabs"].firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons["About"].tap()
        // The button shows once the lookup has settled the tag.
        let again = app.buttons["composer-choose-again"]
        XCTAssertTrue(reveal(again, in: app).waitForExistence(timeout: 30), "The lookup does not settle")
        let matches = app.buttons.matching(identifier: "composer-match")
        XCTAssertFalse(matches.firstMatch.exists, "The full name opens a pick list")
        again.tap()
        let first = matches.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "Choose Composer Again shows no pick list")
        // The list sits above the tabs, out of sight at the end of the page.
        for _ in 0..<6 where !first.isHittable { app.swipeDown() }
        XCTAssertEqual(matches.count, 7)
        XCTAssertTrue(first.label.hasPrefix("Ludwig van Beethoven"), first.label)
        snap(app, "03m-composer-pick-list")
        // The title line, at the leading top of the row.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.25)).tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 10), "A tap on the title does not pick the person")
    }

    /// The fixture holds only the third movement of Brahms's Fourth, so it shows under "Partial works". With the
    /// setting off, it is one of the works again.
    @MainActor
    func testPartialWorks() throws {
        let app = try launchAndConnect()
        reveal(composer(app, "Johannes Brahms"), in: app).tap()
        let partial = heading(app, "Partial works")
        XCTAssertTrue(partial.waitForExistence(timeout: 10), "The composer page shows no partial works")
        XCTAssertFalse(heading(app, "Works").exists)
        XCTAssertTrue(app.buttons.matching(identifier: "work").firstMatch.exists)
        snap(app, "03h-composer-partial-works")

        openSettings(app)
        let toggle = reveal(app.switches["partial-works"], in: app)
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "1", "Separate Partial Works is not on by default")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        snap(app, "08e-partial-works-setting")

        back(app)
        app.buttons["library-composers"].tap()
        reveal(composer(app, "Johannes Brahms"), in: app).tap()
        let works = heading(app, "Works")
        XCTAssertTrue(works.waitForExistence(timeout: 10), "With the setting off, the page shows no Works heading")
        XCTAssertFalse(partial.exists)
        snap(app, "03i-composer-partial-works-off")

        // A reset app keeps its user defaults, so the next test must find the default again.
        openSettings(app)
        let restore = reveal(app.switches["partial-works"], in: app)
        restore.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(restore.value as? String, "1")
    }

    @MainActor
    private func heading(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "section-heading")
            .matching(NSPredicate(format: "label BEGINSWITH %@", title + " (")).firstMatch
    }

    /// The work page offers no MusicBrainz confirmation, and the date is plain text.
    /// Ambiguous matches are picked from the sources page, which the status list opens.
    @MainActor
    func testWorkPageHasNoConfirmButton() throws {
        let app = try launchAndConnect()
        reveal(composer(app, "Wolfgang"), in: app).tap()
        let work = app.buttons.matching(identifier: "work").matching(NSPredicate(format: "label CONTAINS 'K. 467'"))
            .firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        let composed = app.staticTexts["composed"]
        XCTAssertTrue(composed.waitForExistence(timeout: 30), "The work page shows no composed date")
        XCTAssertTrue(composed.label.contains("composed"), composed.label)
        XCTAssertFalse(app.buttons["composed"].exists, "The composed date is a button")
        XCTAssertFalse(app.buttons["Confirm the MusicBrainz Work"].exists, "The work page has a Confirm button")
        snap(app, "04b-work-plain-date")
    }

    /// The empty Search page lists the recent searches, newest first. One search session is one entry; a tap
    /// restores the search, and Clear empties the list.
    @MainActor
    func testRecentSearches() throws {
        let app = try launchAndConnect(openComposers: false)
        openPlace(app, "Search")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let recent = app.buttons.matching(identifier: "search-recent")
        XCTAssertTrue(app.staticTexts["search-hint"].exists)
        XCTAssertFalse(recent.firstMatch.exists)

        // Two commits of one session: Enter, then opening a result.
        field.tap()
        field.typeText("chopin\n")
        let works = app.buttons.matching(identifier: "search-work")
        let four = expectation(for: NSPredicate(format: "count == 4"), evaluatedWith: works)
        XCTAssertEqual(XCTWaiter.wait(for: [four], timeout: 10), .completed)
        reveal(works.firstMatch, in: app).tap()
        XCTAssertTrue(app.buttons.matching(identifier: "recording").firstMatch.waitForExistence(timeout: 10))
        back(app)
        XCTAssertTrue(works.firstMatch.waitForExistence(timeout: 10))

        // Leaving the page commits too; a tab then opens a new session.
        openPlace(app, "Library")
        openPlace(app, "Search")
        XCTAssertTrue(recent.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(recent.count, 1, "One search session left more than one entry")
        XCTAssertEqual(recent.firstMatch.label, "chopin")
        XCTAssertFalse(app.staticTexts["search-hint"].exists, "The hint shows beside the recent searches")
        field.tap()
        field.typeText("brahms")
        openPlace(app, "Library")
        openPlace(app, "Search")
        XCTAssertTrue(recent.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(recent.allElementsBoundByIndex.map(\.label), ["brahms", "chopin"])
        snap(app, "19g-search-recent")

        // A tap restores the search and puts it on top.
        recent.element(boundBy: 1).tap()
        XCTAssertEqual(field.value as? String, "chopin")
        let again = expectation(for: NSPredicate(format: "count == 4"), evaluatedWith: works)
        XCTAssertEqual(XCTWaiter.wait(for: [again], timeout: 10), .completed, "A tap did not restore the search")
        app.buttons["search-clear"].tap()
        XCTAssertTrue(recent.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(recent.allElementsBoundByIndex.map(\.label), ["chopin", "brahms"])

        app.buttons["search-recent-clear"].tap()
        XCTAssertTrue(app.staticTexts["search-hint"].waitForExistence(timeout: 10), "Clear left the list")
        XCTAssertFalse(recent.firstMatch.exists)

        // Done on the filters commits. Closing the sheet with Filters does not, so the entry keeps the Romantic term.
        let filters = app.buttons["search-filters"]
        filters.tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 10))
        app.buttons["Genres"].tap()
        let narrow = app.textFields["filter-narrow"]
        narrow.tap()
        narrow.typeText("roman")
        let romantic = app.buttons.matching(identifier: "filter-term")
            .matching(NSPredicate(format: "label CONTAINS %@", "Romantic")).firstMatch
        XCTAssertTrue(romantic.waitForExistence(timeout: 5))
        romantic.tap()
        XCTAssertTrue(app.buttons["filter-chip"].waitForExistence(timeout: 5))
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForNonExistence(timeout: 5))
        // A search of conditions only shows results, not the recent list.
        XCTAssertTrue(works.firstMatch.waitForExistence(timeout: 10), "A search of conditions only shows no works")
        XCTAssertFalse(recent.firstMatch.exists, "A search of conditions only shows the recent list")
        filters.tap()
        XCTAssertTrue(app.buttons["filter-chip"].waitForExistence(timeout: 10))
        app.buttons["filter-chip"].tap()
        XCTAssertTrue(app.buttons["filter-chip"].waitForNonExistence(timeout: 5))
        filters.tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(recent.firstMatch.waitForExistence(timeout: 10), "Done did not commit the search")
        XCTAssertEqual(recent.count, 1)
        XCTAssertTrue(
            recent.firstMatch.label.hasPrefix("Genre Romantic"),
            "The entry does not show its condition: \(recent.firstMatch.label)")
        snap(app, "19h-search-recent-conditions")

        // A tap restores the conditions.
        recent.firstMatch.tap()
        XCTAssertTrue(
            eventually(timeout: 5) { (filters.value as? String) == "1\u{00A0}condition" },
            "A tap did not restore the conditions")
        XCTAssertTrue(works.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["search-clear"].exists, "A search of conditions only restored a text")

        // The x pill commits and ends the session, so the next search is a new entry.
        app.buttons["search-reset"].tap()
        XCTAssertTrue(recent.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(recent.count, 1)
        field.tap()
        field.typeText("brahms\n")
        app.buttons["search-reset"].tap()
        XCTAssertTrue(recent.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(recent.count, 2, "The search after the x pill replaced the entry before it")
        XCTAssertEqual(recent.firstMatch.label, "brahms")
    }
}

/// A recording, the player, the queue and the downloads.
final class PlaybackScreens: ScreensTestCase {
    /// Music that arrives far below its bitrate shows the slow-connection line in place of the times (ADR 0060).
    @MainActor
    func testSlowConnectionLine() throws {
        let app = try launchAndConnect(arguments: ["-slowMusic"])
        openRecording(app)
        startPlaying(app)
        openPlayer(app)
        let line = app.staticTexts["slow-connection"]
        XCTAssertTrue(line.waitForExistence(timeout: 20), "No slow-connection line while the music trickles in")
        snap(app, "07s-slow-connection")
    }

    /// The quiet spell returns to the playing row after the listener scrolls away.
    @MainActor
    func testPlayerFollowsAfterQuietSpell() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        openPlayer(app)
        let overlay = app.descendants(matching: .any)["player-overlay"].firstMatch
        let position = overlay.sliders["position"].firstMatch
        XCTAssertTrue(eventually(timeout: 12) { position.exists && position.isHittable })
        // The fixture page is short, so its end is the follow target. The top puts the hero above the playing row.
        let rowY = { position.exists ? position.frame.midY : CGFloat.infinity }
        // Short slow drags below the cover touch the page without the pull that closes the player, as a system
        // sheet closes. A drag that starts on the cover or the title moves the player instead.
        let facts = overlay.staticTexts["hero-facts"].firstMatch
        XCTAssertTrue(facts.waitForExistence(timeout: 10), "No facts line to start the drag on")
        let from = facts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = from.withOffset(CGVector(dx: 0, dy: 0.1 * app.frame.height))
        for _ in 0..<2 { from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2) }
        let still = Date()
        XCTAssertFalse(
            app.buttons["player-handle"].waitForNonExistence(timeout: 1), "A short drag at the top closed the player")
        let low = rowY()
        XCTAssertTrue(
            eventually(timeout: 15) { rowY() < low - 40 },
            "The player did not return after eight quiet seconds: row at \(rowY()), was \(low)")
        XCTAssertGreaterThan(
            Date().timeIntervalSince(still), 7, "The player followed before eight quiet seconds")
        snap(app, "05d-player-follow")
    }

    /// A drag up from the cover scrolls the page. It does not move the player.
    @MainActor
    func testUpwardDragOnTheCoverScrolls() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        openPlayer(app)
        let cover = app.descendants(matching: .any)["hero-cover"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        let handle = app.buttons["player-handle"]
        let top = cover.frame.minY
        let handleTop = handle.frame.minY
        let from = cover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(
            forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -0.25 * app.frame.height)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(
            eventually(timeout: 5) { cover.frame.minY < top - 40 },
            "An upward drag on the cover did not scroll the page: cover at \(cover.frame.minY), was \(top)")
        XCTAssertEqual(handle.frame.minY, handleTop, accuracy: 2, "An upward drag moved the player")
    }

    @MainActor
    func testOverlayOpensAndSlidesDown() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        let show = app.buttons["show-player"]
        XCTAssertTrue(show.waitForExistence(timeout: 10), "The playing page does not offer the player")
        let before = show.frame
        checkTabAndCoverFrames(app, side: .right)
        snap(app, "16-pill-right")
        let pill = app.descendants(matching: .any)["mini-player"].firstMatch
        let pillBefore = pillFrame(pill)
        openPlayer(app)
        XCTAssertEqual(pillFrame(pill), pillBefore, "Opening the overlay moved the pill")
        XCTAssertTrue(app.buttons["mini-player-cover"].isHittable)
        for name in ["Library", "Chronology", "Search"] { XCTAssertTrue(tab(app, name).isHittable) }
        checkTabAndCoverFrames(app, side: .right)
        snap(app, "16a-overlay-right")
        slidePlayerDown(app)
        XCTAssertTrue(show.waitForExistence(timeout: 10))
        XCTAssertEqual(show.frame.minY, before.minY, accuracy: 2, "The underlying page scrolled")
        snap(app, "16b-overlay-dismissed")
    }

    /// A swipe down on the content of the player closes it when its list is at the top, as a system sheet closes.
    @MainActor
    func testSwipeDownClosesThePlayer() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        openPlayer(app)
        let overlay = app.descendants(matching: .any)["player-overlay"].firstMatch
        XCTAssertTrue(overlay.exists)
        let start = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(
            forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)),
            withVelocity: .fast, thenHoldForDuration: 0)
        expectPlayerClosed(app)
        XCTAssertTrue(app.buttons["show-player"].waitForExistence(timeout: 10))
    }

    /// A drag that starts on a row at the top of the list and pulls past the top closes the player. The hero
    /// takes drags that start on the cover, so this path starts below it.
    @MainActor
    func testPullPastTopFromARowClosesThePlayer() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        openPlayer(app)
        let cover = app.descendants(matching: .any)["hero-cover"].firstMatch
        let row = app.descendants(matching: .any)["movement"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        XCTAssertTrue(eventually(timeout: 12) { row.exists && row.isHittable }, "No row to start the drag on")
        XCTAssertGreaterThan(row.frame.minY, cover.frame.maxY, "The row is not below the cover")
        // The player opens with the page scrolled to its playing row, and only a pull that starts at the top closes
        // it. Short slow drags down bring the page to the top. Each one pulls less than the 60 points that close the
        // player, so none of them closes it. The page is at the top when a drag no longer moves the cover.
        let handle = app.buttons["player-handle"]
        var atTop = false
        for _ in 0..<12 where !atTop {
            let before = cover.frame.minY
            let from = titleLine(of: row)
            from.press(
                forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 90)), withVelocity: .slow,
                thenHoldForDuration: 0.2)
            var last = CGFloat.infinity
            XCTAssertTrue(
                eventually(timeout: 8) {
                    defer { last = cover.frame.minY }
                    return abs(cover.frame.minY - last) < 1
                }, "The page did not settle")
            atTop = abs(cover.frame.minY - before) < 1
        }
        XCTAssertTrue(atTop, "The page did not reach its top")
        XCTAssertTrue(handle.exists, "A short drag closed the player")
        XCTAssertGreaterThan(row.frame.minY, cover.frame.maxY, "The row is not below the cover")
        snap(app, "05e-pull-from-row")
        titleLine(of: row).press(
            forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.95)),
            withVelocity: .default, thenHoldForDuration: 0.3)
        let closed = app.buttons["player-handle"].waitForNonExistence(timeout: 10)
        if !closed { snap(app, "05f-pull-from-row-open") }
        let logs = app.staticTexts.matching(identifier: "diag-log").allElementsBoundByIndex  // DIAG-TEMP
        let from0 = titleLine(of: row).screenPoint  // DIAG-TEMP
        // DIAG-TEMP
        let diag = logs.map(\.label).joined(separator: "|") + " row=\(row.frame) pt=\(from0)"
        XCTAssertTrue(closed, "A pull past the top from a row did not close the player DIAG[\(diag)]")  // DIAG-TEMP
        XCTAssertTrue(app.buttons["show-player"].waitForExistence(timeout: 10))
    }

    /// The empty right end of the playing row's title line. The playback bar and its slider lie below the line, so
    /// a drag from here starts on the row and on no control.
    @MainActor
    func titleLine(of row: XCUIElement) -> XCUICoordinate {
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0)).withOffset(CGVector(dx: 0, dy: 15))
    }

    /// A drag down from the cover of the player moves the whole player, and a fling closes it.
    @MainActor
    func testHeadingDragClosesThePlayer() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        openPlayer(app)
        let cover = app.descendants(matching: .any)["hero-cover"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        // A pull of more than 120 points closes the player, so the drag is long and does not rely on a fling
        // estimate. A drag that the recognizer misses at its start is lost, so a lost drag repeats; three lost
        // drags fail the check.
        for _ in 0..<3 where app.buttons["player-handle"].exists {
            cover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
                forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)),
                withVelocity: .default, thenHoldForDuration: 0)
            _ = app.buttons["player-handle"].waitForNonExistence(timeout: 4)
        }
        expectPlayerClosed(app)
        XCTAssertTrue(app.buttons["show-player"].waitForExistence(timeout: 10))
    }

    /// A short drag down from the cover only pulls the player. It springs back to its place.
    @MainActor
    func testShortHeadingDragSpringsBack() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        openPlayer(app)
        let handle = app.buttons["player-handle"]
        let before = handle.frame.minY
        let cover = app.descendants(matching: .any)["hero-cover"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        let from = cover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(
            forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 50)), withVelocity: .slow,
            thenHoldForDuration: 0.2)
        XCTAssertTrue(
            eventually(timeout: 5) { abs(handle.frame.minY - before) < 2 },
            "The player did not spring back: handle at \(handle.frame.minY), was \(before)")
        XCTAssertTrue(handle.exists, "A short drag closed the player")
    }

    @MainActor
    func testOverlayOnTheLeft() throws {
        let app = try launchAndConnect(arguments: ["-\(timelineSideKey)", "left"])
        openRecording(app)
        playPaused(app)
        checkTabAndCoverFrames(app, side: .left)
        snap(app, "16c-pill-left")
        let before = pillFrame(app.descendants(matching: .any)["mini-player"].firstMatch)
        openPlayer(app)
        XCTAssertEqual(pillFrame(app.descendants(matching: .any)["mini-player"].firstMatch), before)
        checkTabAndCoverFrames(app, side: .left)
        snap(app, "16d-overlay-left")
        slidePlayerDown(app)
    }

    /// Stop closes the player and leaves no end message. On the walk simulator a natural end of the queue
    /// does not arrive reliably, so the unit tests cover it through the same path.
    @MainActor
    func testStopClosesThePlayer() throws {
        let app = try launchAndConnect()
        openRecording(app)
        startPlaying(app)
        openPlayer(app)
        let player = app.descendants(matching: .any)["player-overlay"].firstMatch
        let stop = reveal(player.buttons["Stop"].firstMatch, in: app)
        XCTAssertTrue(stop.exists, "No Stop button in the player")
        stop.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["mini-player"].firstMatch.waitForNonExistence(timeout: 10),
            "Stop did not end the queue")
        expectPlayerClosed(app)
        XCTAssertFalse(app.staticTexts["player-ended"].exists, "An end message shows")
        snap(app, "16e-stop-closes-player")
    }

    @MainActor
    func testOverlayLinkUsesTheUnderlyingStack() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        openPlayer(app)
        // The page below the overlay builds the same header, so the query stays inside the overlay. The player opens
        // at its header, before the quiet spell brings the playing row up.
        let overlay = app.descendants(matching: .any)["player-overlay"].firstMatch
        let composer = overlay.links["Felix Mendelssohn"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "The composer in the player header is no link")
        composer.tap()
        expectPlayerClosed(app)
        XCTAssertTrue(app.navigationBars["Felix Mendelssohn"].waitForExistence(timeout: 10))
        back(app)
        XCTAssertTrue(app.buttons["show-player"].waitForExistence(timeout: 10))
        XCTAssertTrue(tab(app, "Library").isSelected)
    }

    @MainActor
    func testOverlayLeavesThroughLibrary() throws {
        try checkPlayerTab("Library")
    }

    @MainActor
    func testOverlayLeavesThroughChronology() throws {
        try checkPlayerTab("Chronology")
    }

    @MainActor
    func testOverlayLeavesThroughSearch() throws {
        try checkPlayerTab("Search")
    }

    /// Both the underlying tab and another tab must restore their pushed page.
    @MainActor
    private func checkPlayerTab(_ name: String) throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        back(app)
        openPlace(app, "Chronology")
        // The Chronology opens on the composer of what plays, with that work marked.
        XCTAssertTrue(app.buttons["chronology-name"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["chronology-name"].label, "Felix Mendelssohn")
        let work = app.buttons.matching(identifier: "chronology-work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 30))
        XCTAssertTrue(work.isSelected, "The row of the playing work is not marked")
        work.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "recording").firstMatch.waitForExistence(timeout: 10))
        openPerformer(app, "Carl Fixture")
        XCTAssertTrue(app.navigationBars["Carl Fixture"].waitForExistence(timeout: 10))
        if name != "Search" { openPlace(app, name) }
        let heading = app.navigationBars.firstMatch.identifier
        openPlayer(app)
        tab(app, name).tap()
        expectPlayerClosed(app)
        XCTAssertTrue(tab(app, name).isSelected)
        XCTAssertEqual(app.navigationBars.firstMatch.identifier, heading)
        let other = name == "Library" ? "Search" : "Library"
        openPlace(app, other)
        openPlayer(app)
        tab(app, name).tap()
        expectPlayerClosed(app)
        XCTAssertTrue(tab(app, name).isSelected)
        XCTAssertEqual(app.navigationBars.firstMatch.identifier, heading)
    }

    /// Search is the way to a performer page: the results list every performer whose name matches.
    @MainActor
    private func openPerformer(_ app: XCUIApplication, _ name: String) {
        openPlace(app, "Search")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name + "\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Search does not close the keyboard")
        let person = app.buttons.matching(identifier: "search-person").firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 10), "Search finds no \(name)")
        let page = app.navigationBars[name]
        // A tap while the results still settle does not open the row, so the walk taps again.
        for _ in 0..<3 where !page.exists {
            if person.isHittable { person.tap() }
            _ = page.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(page.exists, "The result did not open \(name)")
    }

    @MainActor
    private func slidePlayerDown(_ app: XCUIApplication) {
        let handle = app.buttons["player-handle"]
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
        expectPlayerClosed(app)
    }

    @MainActor
    func testRecording() throws {
        let app = try launchAndConnect()
        composer(app, "Felix Mendelssohn").tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        snap(app, "03-composer")

        work.tap()
        let recording = app.buttons.matching(identifier: "recording").firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 10))
        // The MusicBrainz pass may still run right after the connect.
        let composed = app.staticTexts.matching(
            NSPredicate(format: "identifier == 'composed' AND label CONTAINS '1844'"))
        XCTAssertTrue(composed.firstMatch.waitForExistence(timeout: 30), app.staticTexts["composed"].label)
        XCTAssertFalse(app.buttons["composed"].exists, "The composed date is a button")
        snap(app, "04-work")
        checkWorkPage(app)

        recording.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        playPaused(app)
        snap(app, "05-recording")
        openPlayer(app)

        // A paused player moves to the dragged position and stays paused.
        let position = app.sliders["position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        let beginning = position.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let end = position.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        beginning.tap()
        let start = position.value as? String ?? ""
        beginning.press(forDuration: 0.1, thenDragTo: end)
        // Read at once after the lift: a snap-back shows the start until the player arrives at the new place.
        let landed = position.value as? String ?? ""
        XCTAssertNotEqual(landed, start, "The position bar snapped back to the start")
        XCTAssertGreaterThan(Self.seconds(landed), Self.seconds(start))
        // The bar stays where the finger let go: it does not snap back while the movement starts again.
        XCTAssertFalse(eventually(timeout: 2) { position.value as? String != landed }, "The position bar snapped back")
        XCTAssertTrue(app.buttons["Resume"].firstMatch.exists)
        snap(app, "05c-seek")

        // The movements are below the player, and a list creates a row only near the screen.
        // The mark is an image in the row. Not every system puts its label into the label of the row.
        let playing = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Now playing'"))
            .firstMatch
        XCTAssertTrue(reveal(playing, in: app).exists, "No movement shows the playing mark")
        expectMovementPlayEdge(app)
    }

    /// The recording page matches the specimen: the header with linked names and a facts line, then the
    /// rows with no heading and no settings rows. While it plays, only the overlay is the player; the page offers it.
    @MainActor
    func testRecordingPageAndPlayer() throws {
        let app = try launchAndConnect()
        openRecording(app)
        let facts = app.staticTexts["hero-facts"]
        XCTAssertTrue(facts.waitForExistence(timeout: 10), "The header has no facts line")
        XCTAssertTrue(facts.label.contains("minute"), facts.label)
        let cover = app.descendants(matching: .any)["hero-cover"].firstMatch
        let play = app.buttons["play-recording"]
        XCTAssertGreaterThan(facts.frame.minY, cover.frame.maxY, "The facts are not under the cover")
        XCTAssertGreaterThan(play.frame.minY, facts.frame.maxY, "Play is not under the facts")
        XCTAssertTrue(app.links["Felix Mendelssohn"].firstMatch.exists, "The composer is no link")
        XCTAssertFalse(app.buttons["raw-tags"].exists, "The page shows a settings row")
        XCTAssertFalse(app.buttons["download"].exists, "The page shows a settings row")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "section-heading").firstMatch.exists,
            "The rows have a heading")
        XCTAssertTrue(app.buttons["page-menu"].exists, "The page bar has no menu")
        snap(app, "05h-recording-page")

        startPlaying(app)
        pause(app)
        let show = app.buttons["show-player"]
        XCTAssertTrue(show.waitForExistence(timeout: 10), "The playing page does not offer the player")
        XCTAssertFalse(play.exists, "The playing page still offers Play")
        XCTAssertFalse(app.sliders["position"].exists, "The page shows the playing row of the player")
        // The movement that plays keeps its tint and a round button that resumes it (paused here).
        // The row may lie below the header, and a list builds only the rows near the screen.
        let slot = reveal(app.buttons["movement-slot"], in: app)
        XCTAssertTrue(slot.exists, "The playing movement has no pause button")
        XCTAssertEqual(slot.label, "Resume", "The paused movement does not offer Resume")
        XCTAssertFalse(app.buttons["add-note"].exists, "The page takes a note")
        // Show the player takes its share of the content width, centred between the margins of the timeline.
        let content = app.frame.width - Layout.edge - Layout.timelineEdge
        XCTAssertEqual(show.frame.width, content * Layout.showPlayerShare, accuracy: 2, "Show the player width")
        XCTAssertEqual(
            show.frame.midX, app.frame.minX + Layout.edge + content / 2, accuracy: 2, "Show the player is off centre")
        snap(app, "05i-recording-playing")
        // Resume from the row: while audio plays the same button reads Pause, with the pause icon.
        slot.tap()
        let reads = NSPredicate(format: "label == 'Pause'")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reads, object: slot)], timeout: 10), .completed,
            "The playing movement offers \(slot.label), not Pause")

        show.tap()
        let handle = app.buttons["player-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10), "Show the player opened nothing")
        let overlay = app.descendants(matching: .any)["player-overlay"].firstMatch
        XCTAssertTrue(reveal(overlay.sliders["position"], in: app).exists, "The player has no playing row")
        XCTAssertFalse(overlay.buttons["show-player"].exists, "The player offers itself")
        snap(app, "05j-player-playing")
        // specimen menu.html, Player: Download and Tags and Grouping of what plays, no queue items.
        let menu = overlay.buttons["page-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "The player has no menu")
        menu.tap()
        let download = menuItem(app, "Download")
        _ = download.waitForExistence(timeout: 5)
        snap(app, "05o-player-menu")
        XCTAssertTrue(download.exists, "The player menu has no Download")
        XCTAssertTrue(menuItem(app, "Tags and Grouping").exists, "The player menu has no Tags and Grouping")
        XCTAssertFalse(menuItem(app, "Play Next").exists, "The player menu has Play Next")
        XCTAssertFalse(menuItem(app, "Add to Queue").exists, "The player menu has Add to Queue")
        expectOrder(app, ["Download", "Tags and Grouping"], "player menu")
        closeMenu(app)
    }

    /// A listening note is written in the playing row, never in a modal. It stays open while the bar scrubs, "End here"
    /// makes a span, and the saved note opens its row once another movement plays.
    @MainActor
    func testListeningNote() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        openPlayer(app)
        let add = reveal(app.buttons["add-note"], in: app)
        XCTAssertTrue(add.exists, "The playing row offers no note")
        let position = app.sliders["position"]
        XCTAssertTrue(position.exists)
        // The bottom of the bar, from the playing mark next to the row title: the room of the note lanes adds to it.
        let playing = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Now playing'"))
            .firstMatch
        let barDrop = { position.frame.maxY - playing.frame.minY }
        let bare = barDrop()
        add.tap()
        let field = app.textFields["note-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Add a note here opened no field")
        XCTAssertGreaterThan(field.frame.minY, position.frame.maxY, "The note field is not in the playing row")
        // The field takes focus by itself; the tap makes the walk independent of keyboard timing.
        field.tap()
        dismissKeyboardTip(app)
        field.typeText("Theme in the violins")
        snap(app, "41-note-writing")

        // The note stays open while the listener scrubs to find the end.
        let beginning = position.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let end = position.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        beginning.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(field.exists, "A scrub closed the note")
        reveal(app.buttons["end-note"], in: app).tap()
        let time = app.staticTexts["note-draft-time"]
        XCTAssertTrue(eventually(timeout: 5) { time.label.contains("–") }, "End here made no span: \(time.label)")
        let spanStart = Self.seconds(String(time.label.split(separator: "–")[0]))
        let spanEnd = Self.seconds(String(time.label.split(separator: "–")[1]))
        snap(app, "41a-note-span")
        reveal(app.buttons["save-note"], in: app).tap()
        let saved = app.buttons["note-text"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "The saved note does not show")
        XCTAssertTrue(saved.label.contains("Theme in the violins"), saved.label)
        XCTAssertFalse(field.exists, "Save left the note open")
        // The first lane sits in the gap above the bar, so the first note does not move the bar.
        XCTAssertEqual(barDrop(), bare, accuracy: 0.5, "The first note moved the bar")
        snap(app, "41b-note-saved")

        // Two moments at the end of the span stack in lanes above it. The bar keeps room for them below the names.
        for text in ["Horns", "Oboe"] {
            reveal(app.buttons["add-note"], in: app).tap()
            XCTAssertTrue(field.waitForExistence(timeout: 10), "Add a note here opened no field")
            field.tap()
            field.typeText(text)
            reveal(app.buttons["save-note"], in: app).tap()
            XCTAssertTrue(field.waitForNonExistence(timeout: 10), "Save left the note open")
        }
        XCTAssertEqual(app.buttons.matching(identifier: "note-text").count, 3)
        reveal(position, in: app)
        // Each lane above the first adds the pitch of one lane (Layout.noteDotTop).
        let pitch: CGFloat = 9
        XCTAssertEqual(barDrop(), bare + 2 * pitch, accuracy: 0.5, "The bar has no room for the third lane")
        snap(app, "41d-note-lanes")

        // A tap at the height of the third lane picks the note under it, the span, and moves to its start. A scrub
        // there would move to the middle of the movement. The frame of the slider reaches 19 pt below the bar, the
        // touch area (Layout.positionBarInset). The bar is 6 pt high, and a third-lane dot centres 2 lanes and 6 pt
        // above its top.
        let touchBelow: CGFloat = 19
        let thirdLane = -(touchBelow + 6 + 2 * pitch + 6)
        let lane = position.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
            .withOffset(CGVector(dx: 0, dy: thirdLane))
        lane.tap()
        XCTAssertTrue(
            eventually(timeout: 5) { abs(Self.seconds(position.value as? String ?? "") - spanStart) <= 1 },
            "A tap on the third lane did not move to the span: \(position.value ?? "")")

        // Both moments sit at the end of the span, where the scrub let go. There a tap on the third lane picks the top
        // moment, not the span that ends below it, and a tap on the span's own lane picks the span.
        let spanEndOnBar = position.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 1))
        spanEndOnBar.withOffset(CGVector(dx: 0, dy: thirdLane)).tap()
        XCTAssertTrue(
            eventually(timeout: 5) { abs(Self.seconds(position.value as? String ?? "") - spanEnd) <= 1 },
            "A tap on the third lane at the span's end did not move to the moment there: \(position.value ?? "")")
        spanEndOnBar.withOffset(CGVector(dx: 0, dy: -(touchBelow + 6 + 6))).tap()
        XCTAssertTrue(
            eventually(timeout: 5) { abs(Self.seconds(position.value as? String ?? "") - spanStart) <= 1 },
            "A tap on the span's end did not move to the span: \(position.value ?? "")")

        // Another movement plays; the row of the note now opens and shows it.
        reveal(app.buttons["Play from here"].firstMatch, in: app).tap()
        pause(app)
        XCTAssertFalse(app.buttons["note-text"].exists, "A closed row shows its note")
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Allegro molto appassionato'"))
            .firstMatch
        reveal(first, in: app).tap()
        let note = app.buttons["note-time"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "The row with a note does not open")
        XCTAssertTrue(app.buttons["Resume"].firstMatch.exists, "Opening the row started playback")
        snap(app, "41c-note-row")

        // A tap on its time jumps there and plays.
        reveal(note, in: app).tap()
        let pill = app.buttons["mini-player-pause"]
        XCTAssertTrue(eventually(timeout: 10) { pill.label == "Pause" }, "The note time did not play: \(pill.label)")
        pause(app)
    }

    /// Play on the work page plays the reference recording and the pill shows the playing state (item 25).
    @MainActor
    func testPlayOnTheWorkPage() throws {
        let app = try launchAndConnect()
        composer(app, "Felix Mendelssohn").tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        let play = app.buttons["play-work"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertEqual(play.label, "Play top recording")
        XCTAssertFalse(app.staticTexts["Plays first"].exists)
        let first = app.buttons.matching(identifier: "recording").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let before = first.frame
        let heading = app.buttons["favourite-work"]
        let headingBefore = heading.frame
        let playBefore = play.frame
        play.tap()
        // While a recording of the work plays, the pill pauses it (sz-swi9.4).
        XCTAssertTrue(eventually(timeout: 15) { play.label == "Pause" }, "The pill reads \(play.label) while it plays")
        for (element, original) in [(heading, headingBefore), (play, playBefore), (first, before)] {
            XCTAssertEqual(element.frame.minX - original.minX, -Measure.timeline / 2, accuracy: 1)
            XCTAssertEqual(element.frame.width, original.width, accuracy: 1)
            XCTAssertEqual(element.frame.height, original.height, accuracy: 1)
        }
        // The playing row holds one round button on its top edge, in place of the chevron (specimen `.row.top`).
        let slot = first.buttons["recording-slot"]
        XCTAssertTrue(slot.exists, "The playing row has no round button")
        XCTAssertEqual(slot.label, "Pause", "The playing row offers \(slot.label), not Pause")
        XCTAssertLessThan(slot.frame.midY, first.frame.midY, "The round button sits at the centre of the row")
        XCTAssertLessThanOrEqual(slot.frame.maxX, first.frame.maxX + 1, "The round button leaves the row")
        snap(app, "04c-work-playing")
        play.tap()
        XCTAssertTrue(eventually(timeout: 10) { play.label == "Resume" }, "The pill reads \(play.label) after a pause")
        XCTAssertEqual(app.buttons["mini-player-pause"].label, "Resume", "The pill did not pause the playback")
        // The playing row tints in place. The timeline moves the content sideways only; it keeps its size and height.
        XCTAssertEqual(first.frame.width, before.width, accuracy: 1, "The playing row changed its width")
        XCTAssertEqual(first.frame.height, before.height, accuracy: 1, "The playing row changed its height")
        XCTAssertEqual(first.frame.minY, before.minY, accuracy: 0.5, "The playing row moved up or down")
        snap(app, "04d-work-playing")
    }

    @MainActor
    func testWorkPlayUsesTheContentInsetsOnEitherSide() throws {
        for side in ["right", "left"] {
            let app = try launchAndConnect(arguments: ["-\(timelineSideKey)", side])
            composer(app, "Felix Mendelssohn").tap()
            let work = app.buttons.matching(identifier: "work").firstMatch
            XCTAssertTrue(work.waitForExistence(timeout: 10))
            work.tap()
            let play = app.buttons["play-work"]
            XCTAssertTrue(play.waitForExistence(timeout: 10))
            XCTAssertEqual(play.label, "Play top recording")
            let edge: PillEdge = side == "left" ? .left : .right
            // Without a timeline both margins are equal; a shown timeline adds its width on its side only.
            XCTAssertFalse(app.descendants(matching: .any)["timeline"].exists, "A timeline shows before playback")
            let still = drawn(play, in: app, side: edge)
            XCTAssertEqual(still.minX, app.frame.minX + Layout.centredEdge, accuracy: 1)
            XCTAssertEqual(still.maxX, app.frame.maxX - Layout.centredEdge, accuracy: 1)
            expectCapsuleLabelCentered(still, in: app)
            play.tap()
            XCTAssertTrue(app.descendants(matching: .any)["timeline"].waitForExistence(timeout: 10))
            XCTAssertTrue(eventually(timeout: 15) { play.label == "Pause" }, "Play reads \(play.label) while it plays")
            let frame = drawn(play, in: app, side: edge)
            let leading = side == "left" ? Layout.timelineEdge : Layout.edge
            let trailing = side == "left" ? Layout.edge : Layout.timelineEdge
            XCTAssertEqual(frame.minX, app.frame.minX + leading, accuracy: 1)
            XCTAssertEqual(frame.maxX, app.frame.maxX - trailing, accuracy: 1)
            XCTAssertEqual(frame.midX, app.frame.midX + (leading - trailing) / 2, accuracy: 1)
            XCTAssertEqual(frame.width, still.width, accuracy: 1, "The content width changed with the timeline")
            if side == "right" {
                snap(app, "04e-work-play-right")
            } else {
                snap(app, "04f-work-play-left")
            }
            app.terminate()
        }
    }

    /// Play Album on a recording page starts the album, not only the recording (build 48, item 11).
    /// The Brahms movement lives on a recital disc that holds a second work, so its page offers the whole disc.
    @MainActor
    func testPlayWholeAlbumOnTheRecordingPage() throws {
        let app = try launchAndConnect()
        composer(app, "Johannes Brahms").tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        let recording = app.buttons.matching(identifier: "recording").firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["work-cover"].exists)
        XCTAssertFalse(app.buttons["play-work-album"].exists)
        let workPlay = app.buttons["play-work"]
        let label = workPlay.staticTexts.firstMatch
        XCTAssertEqual(label.label, "Play top recording")
        // SwiftUI reports the label's whole allocation. Pixels give the inset of the visible icon and text.
        let capsule = drawn(workPlay, in: app)
        let labelBounds = try XCTUnwrap(ScreenPixels(app)?.lightLabelBounds(in: capsule))
        XCTAssertGreaterThanOrEqual(labelBounds.minX - capsule.minX, Layout.capsuleInset - 1)
        XCTAssertGreaterThanOrEqual(capsule.maxX - labelBounds.maxX, Layout.capsuleInset - 1)
        snap(app, "04e-work-album-buttons")
        recording.tap()
        let wholeAlbum = app.buttons["play-album"]
        XCTAssertTrue(wholeAlbum.waitForExistence(timeout: 10), "The recording page offers no Play Album")
        XCTAssertEqual(wholeAlbum.label, "Play Album")
        // The page shows the cover, and Play and Play Album stand side by side (sz-3hcq.2).
        let cover = app.descendants(matching: .any)["hero-cover"].firstMatch
        XCTAssertTrue(cover.exists, "The recording page shows no cover")
        let play = app.buttons["play-recording"]
        XCTAssertEqual(play.frame.midY, wholeAlbum.frame.midY, accuracy: 1, "Play and Play Album are not on one row")
        XCTAssertLessThan(play.frame.maxX, wholeAlbum.frame.minX, "Play does not lead Play Album")
        XCTAssertGreaterThan(play.frame.minY, cover.frame.maxY, "The buttons are not under the cover")
        snap(app, "05f-recording-buttons")
        wholeAlbum.tap()
        pause(app)
        snap(app, "05d-play-whole-album")
    }

    /// Play on an album page starts the album (build 48, item 21).
    @MainActor
    func testPlayOnTheAlbumPage() throws {
        let app = try launchAndConnect()
        openClassicalAlbums(app)
        let encores = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Romantic Encores'")).firstMatch
        XCTAssertTrue(reveal(encores, in: app).isHittable)
        encores.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        // The album page has the favourite mark after its title. Stars survive launches, so the
        // check sets the mark and takes it away again.
        let mark = app.buttons["favourite-album"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10), "The album page has no favourite mark")
        let before = mark.value as? String
        mark.tap()
        XCTAssertTrue(eventually(timeout: 2) { mark.value as? String != before }, "The album mark did not change")
        snap(app, "05e-album-favourite")
        mark.tap()
        XCTAssertTrue(eventually(timeout: 10) { mark.value as? String == before })
        startPlaying(app)
        pause(app)
        snap(app, "05e-play-album")
    }

    /// An opened row links the names that differ from the header, as the header does. On an album of two composers, each row names its composer.
    @MainActor
    func testMovementNamesAreLinks() throws {
        let app = try launchAndConnect()
        openClassicalAlbums(app)
        let encores = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Romantic Encores'")).firstMatch
        XCTAssertTrue(reveal(encores, in: app).isHittable)
        encores.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.links["Daniel Keys"].exists, "The soloist of one track shows in the header")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Andante'")).firstMatch
        XCTAssertTrue(reveal(row, in: app).exists, "The Mozart row does not open")
        row.tap()
        let composer = app.links["Wolfgang Amadeus Mozart"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "The composer in the row is no link")
        let soloist = app.links["Daniel Keys"].firstMatch
        XCTAssertTrue(soloist.exists, "The soloist in the row is no link")
        snap(app, "05k-movement-links")
        soloist.tap()
        XCTAssertTrue(app.navigationBars["Daniel Keys"].waitForExistence(timeout: 10), "The soloist link opens no page")
        back(app)
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        XCTAssertTrue(
            app.navigationBars["Wolfgang Amadeus Mozart"].waitForExistence(timeout: 10),
            "The composer link opens no page")
    }

    /// A name in the playing row of the overlay is a link too. It closes the player and opens the page in the place
    /// below, as a header link does.
    @MainActor
    func testPlayingRowNamesLinkFromTheOverlay() throws {
        let app = try launchAndConnect()
        openClassicalAlbums(app)
        let encores = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Romantic Encores'")).firstMatch
        XCTAssertTrue(reveal(encores, in: app).isHittable)
        encores.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        startPlaying(app)
        openPlayer(app)
        // The first track is Brahms; Next plays the Mozart Andante, whose soloist differs from the header.
        let next = app.buttons["Next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 30), "No Next button")
        next.tap()
        pause(app)
        let overlay = app.descendants(matching: .any)["player-overlay"].firstMatch
        let soloist = overlay.links["Daniel Keys"].firstMatch
        XCTAssertTrue(reveal(soloist, in: app).exists, "The soloist in the playing row is no link")
        snap(app, "05l-playing-row-links")
        soloist.tap()
        expectPlayerClosed(app)
        XCTAssertTrue(
            app.navigationBars["Daniel Keys"].waitForExistence(timeout: 10), "The playing row link opens no page")
    }

    @MainActor
    func testAlbumWorkHasOneDisclosureOnThePageAndOverlay() throws {
        let app = try launchAndConnect()
        openClassicalAlbums(app)
        let album = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Mendelssohn: Violin Concerto'")).firstMatch
        reveal(album, in: app).tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        let work = app.buttons.matching(identifier: "album-work").firstMatch
        XCTAssertTrue(reveal(work, in: app).isHittable)
        XCTAssertFalse(work.images["album-work-disclosure"].exists, "The system link has a second chevron")
        snap(app, "05f-album-work")
        startPlaying(app)
        pause(app)
        app.buttons["mini-player-cover"].tap()
        let overlayWork = app.descendants(matching: .any)["player-overlay"]
            .buttons.matching(identifier: "album-work").firstMatch
        XCTAssertTrue(reveal(overlayWork, in: app).isHittable)
        XCTAssertEqual(overlayWork.images.matching(identifier: "album-work-disclosure").count, 1)
        snap(app, "05g-album-work-overlay")
        overlayWork.tap()
        XCTAssertTrue(app.buttons["favourite-recording"].waitForExistence(timeout: 10))
    }

    /// Next has nowhere to go on the last movement of the last item. Next always plays, and a queue that ends
    /// removes the Next button. So the walk pauses as soon as Next turns off, while the last movement plays.
    @MainActor
    func testNextEndsAtTheLastMovement() throws {
        let app = try launchAndConnect()
        openRecording(app)
        startPlaying(app)
        openPlayer(app)
        let next = app.buttons["Next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 30), "No Next button")
        next.tap()
        next.tap()
        XCTAssertTrue(eventually(timeout: 10) { !next.isEnabled }, "Next stays on at the last movement")
        pause(app)
        XCTAssertFalse(next.isEnabled, "Next turned on again after the pause")
        snap(app, "05d-next-ends")
    }

    /// The ⋯ menu of the work, recording and album pages and the long-press menu of a recording row keep the order of
    /// The specimen menu: queue, download, tags. The row menu has Play on top.
    @MainActor
    func testPageMenus() throws {
        let app = try launchAndConnect()
        composer(app, "Felix Mendelssohn").tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        XCTAssertTrue(app.buttons["play-work"].waitForExistence(timeout: 10))
        let queue = pageMenuItem(app, "Add to Queue")
        XCTAssertTrue(queue.exists, "The work menu has no Add to Queue")
        XCTAssertTrue(menuItem(app, "Play Next").exists, "The work menu has no Play Next")
        XCTAssertFalse(menuItem(app, "Download").exists, "The work menu offers a download")
        XCTAssertFalse(menuItem(app, "Tags and Grouping").exists, "The work menu offers the tags")
        XCTAssertEqual(menuItem(app, "Play Next").label, "Play Next", "The work menu names the top recording")
        snap(app, "05k-work-menu")
        closeMenu(app)
        // A press while the work menu still fades out opens nothing, so the row waits for the menu to be gone.
        XCTAssertTrue(eventually(timeout: 5) { !queue.exists }, "The work menu stays open")

        let row = app.buttons.matching(identifier: "recording").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(eventually(timeout: 5) { row.isHittable }, "The recording row is not ready for a press")
        row.press(forDuration: 1.2)
        let rowTags = menuItem(app, "Tags and Grouping")
        XCTAssertTrue(rowTags.waitForExistence(timeout: 5), "The row menu has no Tags and Grouping")
        expectOrder(app, ["Play", "Play Next", "Add to Queue", "Download", "Tags and Grouping"], "row menu")
        snap(app, "05l-recording-row-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(eventually(timeout: 5) { !rowTags.exists }, "The row menu stays open")

        row.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        XCTAssertTrue(pageMenuItem(app, "Play Next").exists, "The recording menu has no Play Next")
        expectOrder(app, ["Play Next", "Add to Queue", "Download", "Tags and Grouping"], "recording menu")
        snap(app, "05m-recording-menu")
        closeMenu(app)
        back(app, times: 3)

        openClassicalAlbums(app)
        let album = app.buttons.matching(identifier: "album").firstMatch
        XCTAssertTrue(reveal(album, in: app).isHittable)
        album.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        XCTAssertTrue(pageMenuItem(app, "Tags and Grouping").exists, "The album menu has no Tags and Grouping")
        expectOrder(app, ["Play Next", "Add to Queue", "Download", "Tags and Grouping"], "album menu")
        snap(app, "05n-album-menu")
        closeMenu(app)
    }

    /// The favourite item of an open row menu, found by its identifier or its label. It is the last item, so on a low
    /// row it can sit under the tab bar: a test reads it and never drags the menu, because a lift selects an item.
    @MainActor
    func menuFavourite(_ app: XCUIApplication) -> XCUIElement {
        let favourite = app.buttons.matching(
            NSPredicate(format: "identifier == 'favourite-action' OR label IN {'Favourite', 'Unfavourite'}")
        ).firstMatch
        _ = favourite.waitForExistence(timeout: 5)
        return favourite
    }

    /// The items of the open menu run from top to bottom in this order.
    @MainActor
    private func expectOrder(_ app: XCUIApplication, _ titles: [String], _ name: String) {
        let tops = titles.map { menuItem(app, $0).frame.minY }
        for (index, pair) in zip(tops, tops.dropFirst()).enumerated() {
            XCTAssertLessThan(pair.0, pair.1, "In the \(name), \(titles[index + 1]) is above \(titles[index])")
        }
    }

    @MainActor
    func testDownload() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        // The download lives in the menu of the page bar, which closes after each choice.
        pageMenuItem(app, "Download").tap()
        let downloaded = eventually(timeout: 30) {
            let remove = pageMenuItem(app, "Remove Download")
            if remove.exists { return true }
            closeMenu(app)
            return false
        }
        XCTAssertTrue(downloaded, "The download did not finish")
        // The state is the line below the item, in the label or as its own text.
        let line = NSPredicate(format: "label CONTAINS 'Downloaded, '")
        XCTAssertTrue(
            app.staticTexts.matching(line).firstMatch.exists || app.buttons.matching(line).firstMatch.exists,
            "Remove Download has no line below it")
        snap(app, "05a-downloaded")
        closeMenu(app)
        back(app, times: 3)

        openSettings(app)
        reveal(app.buttons["local-storage"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Local Storage"].waitForExistence(timeout: 10))
        // The list builds rows lazily, and the Downloads section starts below the storage sections.
        XCTAssertTrue(reveal(app.descendants(matching: .any)["download"].firstMatch, in: app).exists, "No download row")
        snap(app, "08a-local-storage")
    }

    @MainActor
    func testPerformers() throws {
        let app = try launchAndConnect(openComposers: false, arguments: ["-offlineFavourites"])
        // The performer name must sit where a pushed page has its title. The ink of "Favourites" ends on the
        // baseline, as the name does: a descender would move the ink bottom.
        app.buttons["library-favourites"].tap()
        let heading = app.staticTexts["page-heading"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        let title = drawn(heading, in: app)
        openPerformer(app, "Carl Fixture")
        let cover = app.buttons.matching(identifier: "performer-album").firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        snap(app, "06b-performer")
        checkPerformerHead(app, titleBottom: title.maxY)
        let mark = app.buttons["favourite-performer"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        // The title words must not toggle the favourite.
        let before = mark.value as? String
        // The element extends under Back. Tap the last title line to avoid the navigation target.
        let line = Layout.pageTitle.size * Layout.pageTitle.lineHeight
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: mark.frame.minX + line / 2, dy: mark.frame.maxY - line / 2)).tap()
        XCTAssertEqual(mark.value as? String, before, "A tap on the name changed the favourite")
        mark.tap()
        let performerFavourite = expectation(for: NSPredicate(format: "value == 'Favourite'"), evaluatedWith: mark)
        XCTAssertEqual(
            XCTWaiter.wait(for: [performerFavourite], timeout: 5), .completed, "The performer is not a favourite")
        snap(app, "06d-performer-favourite")
        cover.tap()
        let albumMark = app.buttons["favourite-album"]
        XCTAssertTrue(albumMark.waitForExistence(timeout: 10))
        if albumMark.value as? String != "Favourite" { albumMark.tap() }
        let albumFavourite = expectation(for: NSPredicate(format: "value == 'Favourite'"), evaluatedWith: albumMark)
        XCTAssertEqual(XCTWaiter.wait(for: [albumFavourite], timeout: 5), .completed, "The album is not a favourite")
        pageMenuItem(app, "Tags and Grouping").tap()
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 10))
        snap(app, "06c-tags")
        // One tap on a cover pushes one album: two steps back reach the performer (sz-rs30.1.105.85).
        back(app, times: 2)
        XCTAssertTrue(
            app.descendants(matching: .any)["performer-tabs"].firstMatch.waitForExistence(timeout: 10),
            "Back from the album did not reach the performer")
        let marked = app.buttons.matching(identifier: "performer-album").firstMatch
        XCTAssertTrue(
            eventually(timeout: 5) { "\(marked.label) \(marked.value ?? "")".contains("Favourite") },
            "The favourite album reads \(marked.label)")
        snap(app, "06f-performer-album-favourite")
    }

    @MainActor
    func testQueue() throws {
        let app = try launchAndConnect()
        let miniPlayer = pausedPlayerInLibrary(app)
        composer(app, "Ludwig").tap()
        let fifth = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(fifth.waitForExistence(timeout: 10))
        fifth.swipeLeft()
        let add = app.buttons["Add to Queue"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        miniPlayer.buttons["mini-player-cover"].tap()
        // The player opens at its header, and the playing movement may lie below the fold.
        XCTAssertTrue(reveal(app.sliders["position"], in: app).exists, "No position slider in the player")
        snap(app, "07-now-playing")
        let queued = reveal(app.descendants(matching: .any).matching(identifier: "up-next").firstMatch, in: app)
        XCTAssertTrue(queued.label.contains("Symphony No. 5"), queued.label)
        snap(app, "08-up-next")
        queued.tap()
        let title = app.buttons.matching(identifier: "favourite-recording")
            .matching(NSPredicate(format: "label CONTAINS 'Symphony No. 5'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        // The player follows the playing row after its quiet spell, so the header shows only for that spell.
        expectWashFromTheTop(app)
        snap(app, "08d-next-player")
        pause(app)
        XCTAssertTrue(app.sliders["position"].waitForExistence(timeout: 10))
        XCTAssertTrue(miniPlayer.buttons["mini-player-cover"].exists)
        XCTAssertTrue(reveal(app.descendants(matching: .any)["up-next-end"].firstMatch, in: app).exists)
        snap(app, "08e-next-queue-end")
    }

    /// With no item after the one that plays, the player ends with a Next section that says where the queue ends
    ///. After the last item the player closes, as `testStopClosesThePlayer` checks for Stop.
    @MainActor
    func testQueueEndsHere() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        openPlayer(app)
        let endsHere = reveal(app.descendants(matching: .any)["up-next-end"].firstMatch, in: app)
        XCTAssertTrue(endsHere.exists, "The player does not say where the queue ends")
        XCTAssertFalse(app.descendants(matching: .any)["up-next"].firstMatch.exists, "A next row without a next item")
        snap(app, "08e-queue-ends-here")
    }

    /// Offline, a favourite changes at the tap and shows no notice. One quiet Library line says why changes wait
    ///.
    @MainActor
    func testOfflineFavouriteKeepsTheMarkAndShowsTheServerStatus() throws {
        let app = try launchAndConnect(arguments: ["-offlineFavourites"])
        composer(app, "Ludwig van Beethoven").tap()
        app.buttons.matching(identifier: "work").firstMatch.tap()
        app.buttons.matching(identifier: "recording").firstMatch.tap()
        let mark = app.buttons["favourite-recording"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        let initial = mark.value as? String
        let changed = initial == "Favourite" ? "Not a favourite" : "Favourite"
        mark.tap()
        XCTAssertEqual(mark.value as? String, changed)
        snap(app, "05f-offline-favourite-kept")
        mark.tap()
        XCTAssertEqual(mark.value as? String, initial)
        snap(app, "05g-offline-favourite-back")
        let notice = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: app.alerts.firstMatch)
        notice.isInverted = true
        wait(for: [notice], timeout: 2)
        openPlace(app, "Library")
        for _ in 0..<10 where !app.buttons["library-settings"].exists { back(app) }
        let status = app.staticTexts["server-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "No server status on Library")
        XCTAssertEqual(status.label, "Server not reachable. Changes wait on this iPhone.")
        snap(app, "05e-offline-server-status")
    }

    @MainActor
    func testOfflineAlbumAppearsInFavourites() throws {
        let app = try launchAndConnect(arguments: ["-offlineFavourites"])
        openClassicalAlbums(app)
        let album = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Romantic Encores'")).firstMatch
        reveal(album, in: app).tap()
        let mark = app.buttons["favourite-album"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        mark.tap()
        XCTAssertEqual(mark.value as? String, "Favourite")
        snap(app, "05j-offline-album")
        // Album, Classical Albums, Classical Rules and Settings lie between the album and Library.
        back(app, times: 4)
        app.buttons["library-favourites"].tap()
        let row = app.buttons["favourite-album-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Romantic Encores"))
        snap(app, "05k-favourite-albums")
        row.tap()
        XCTAssertEqual(mark.value as? String, "Favourite")
        mark.tap()
        XCTAssertEqual(mark.value as? String, "Not a favourite")
        back(app)
        XCTAssertFalse(row.exists)
    }

    /// A swipe favourite moves ahead of a newer recording before the listener plays the work.
    @MainActor
    func testFavouriteRecordingOrder() throws {
        let app = try launchAndConnect()
        composer(app, "Ludwig van Beethoven").tap()
        app.buttons.matching(identifier: "work").firstMatch.tap()
        let rows = app.buttons.matching(identifier: "recording")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let workMark = app.buttons["favourite-work"]
        workMark.tap()
        XCTAssertEqual(workMark.value as? String, "Favourite")
        snap(app, "05a-work-favourite")

        // Server stars survive UI test launches. Clear both before checking the default order.
        for name in ["Carl Fixture", "Anna Probe"] {
            rows.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.tap()
            let mark = app.buttons["favourite-recording"]
            XCTAssertTrue(mark.waitForExistence(timeout: 10))
            if mark.value as? String == "Favourite" {
                mark.tap()
                XCTAssertTrue(eventually(timeout: 10) { mark.value as? String == "Not a favourite" })
            }
            back(app)
        }
        XCTAssertTrue(rows.firstMatch.label.contains("Carl Fixture"))
        let older = rows.matching(NSPredicate(format: "label CONTAINS 'Anna Probe'")).firstMatch
        older.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: older.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        snap(app, "05a-recording-swipe")
        let favourite = app.buttons["favourite-action"].firstMatch
        XCTAssertTrue(favourite.waitForExistence(timeout: 5))
        XCTAssertEqual(favourite.label, "Favourite")
        favourite.tap()
        // The favourite moves up at once; it does not wait for the server.
        let moved = expectation(for: NSPredicate(format: "label CONTAINS 'Anna Probe'"), evaluatedWith: rows.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 2), .completed)
        snap(app, "05b-work-reference")
        // The menu of a favourite takes it away.
        rows.firstMatch.press(forDuration: 1.2)
        let unfavourite = menuFavourite(app)
        XCTAssertTrue(unfavourite.exists)
        XCTAssertEqual(unfavourite.label, "Unfavourite")
        snap(app, "05b-unfavourite-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(eventually(timeout: 5) { !unfavourite.exists }, "The menu did not close")

        rows.element(boundBy: 1).tap()
        app.buttons["favourite-recording"].tap()
        snap(app, "05c-recording-favourite")
        back(app)
        XCTAssertTrue(rows.firstMatch.label.contains("Anna Probe"))
        app.buttons["Edit"].tap()
        // A simulated drag on the reorder handle does not always lift the row, so the drag can repeat.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<3 where !rows.firstMatch.label.contains("Carl Fixture") {
            let source = origin.withOffset(
                CGVector(dx: app.frame.width - 30, dy: rows.element(boundBy: 1).frame.midY))
            let target = origin.withOffset(
                CGVector(dx: app.frame.width - 30, dy: rows.element(boundBy: 0).frame.minY))
            source.press(forDuration: 1.0, thenDragTo: target)
            _ = eventually(timeout: 3) { rows.firstMatch.label.contains("Carl Fixture") }
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(eventually(timeout: 10) { rows.firstMatch.label.contains("Carl Fixture") })
        snap(app, "05d-recordings-reordered")
        app.buttons["play-work"].tap()
        XCTAssertTrue(app.buttons["recording-slot"].waitForExistence(timeout: 10))
        XCTAssertTrue(rows.firstMatch.buttons["recording-slot"].exists)
        pause(app)
        back(app, times: 3)
        app.buttons["library-favourites"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "favourite").count, 2)
        XCTAssertTrue(app.buttons.matching(identifier: "work").firstMatch.exists)
        snap(app, "06d-favourites")
        // The composer page lists the favourite work with the set fermata after its title.
        back(app)
        app.buttons["library-composers"].tap()
        composer(app, "Ludwig van Beethoven").tap()
        XCTAssertTrue(app.buttons.matching(identifier: "work").firstMatch.waitForExistence(timeout: 10))
        snap(app, "06e-favourite-in-composer-works")
    }

    /// A long press lifts a favourite row and a drag drops it elsewhere with no Edit mode. A still long press on
    /// the same row keeps the context menu. The new order stays on the device across a relaunch (ADR 0013).
    @MainActor
    func testFavouriteRecordingLongPressDrag() throws {
        let app = try launchAndConnect()
        composer(app, "Ludwig van Beethoven").tap()
        app.buttons.matching(identifier: "work").firstMatch.tap()
        let rows = app.buttons.matching(identifier: "recording")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))

        // Server stars survive UI test launches, so each recording is set to a favourite, not toggled.
        for name in ["Carl Fixture", "Anna Probe"] {
            rows.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.tap()
            let mark = app.buttons["favourite-recording"]
            XCTAssertTrue(mark.waitForExistence(timeout: 10))
            if mark.value as? String != "Favourite" {
                mark.tap()
                XCTAssertTrue(eventually(timeout: 10) { mark.value as? String == "Favourite" })
            }
            back(app)
        }
        let first = rows.element(boundBy: 0).label
        let second = rows.element(boundBy: 1).label
        XCTAssertNotEqual(first, second)

        // A still press shows the menu, so a lift must need movement.
        rows.element(boundBy: 0).press(forDuration: 1.2)
        let unfavourite = menuFavourite(app)
        XCTAssertTrue(unfavourite.exists, "A still long press did not open the menu")
        XCTAssertEqual(unfavourite.label, "Unfavourite")
        snap(app, "05e-still-press-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(eventually(timeout: 5) { !unfavourite.exists }, "The menu did not close")
        XCTAssertEqual(rows.element(boundBy: 0).label, first, "A still press changed the order")

        // Press the second row for 0.6 s and drag it above the first. The drag call blocks the test until the
        // finger lifts and XCUIScreen is main-actor only, so no screenshot can show the row mid-drag.
        for _ in 0..<3 where !rows.element(boundBy: 0).label.contains(second) {
            let source = rows.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let target = rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            source.press(forDuration: 0.6, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
            _ = eventually(timeout: 3) { rows.element(boundBy: 0).label.contains(second) }
        }
        XCTAssertTrue(
            eventually(timeout: 10) {
                rows.element(boundBy: 0).label.contains(second) && rows.element(boundBy: 1).label.contains(first)
            }, "The long-press drag did not move the favourite")
        snap(app, "05g-recording-dropped")

        // The order lives in the device file. A launch without -resetServer keeps it and the login.
        app.terminate()
        app.launchArguments = []
        app.launch()
        let connect = app.buttons["connect"]
        if connect.waitForExistence(timeout: 5) { connect.tap() }
        let composers = app.buttons["library-composers"]
        XCTAssertTrue(composers.waitForExistence(timeout: 30))
        composers.tap()
        XCTAssertTrue(composer(app, "Ludwig van Beethoven").waitForExistence(timeout: 30))
        composer(app, "Ludwig van Beethoven").tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(
            eventually(timeout: 10) { rows.element(boundBy: 0).label.contains(second) },
            "The dragged order did not survive a relaunch")
        snap(app, "05h-recording-order-after-relaunch")
        app.terminate()
    }

}

/// The timeline on the screen edge and the mini player in the tab row.
final class TimelineScreens: ScreensTestCase {
    /// With nothing playing, pages show neither the timeline nor the mini player.
    @MainActor
    func testNothingPlaying() throws {
        let app = try launchAndConnect()
        XCTAssertTrue(tab(app, "Library").isSelected)
        XCTAssertFalse(timeline(app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["mini-player"].exists)
        snap(app, "15-nothing-playing")

        openRecording(app)
        playPaused(app)
        XCTAssertTrue(timeline(app).exists)
        openPlayer(app)
        reveal(app.buttons["Stop"].firstMatch, in: app).tap()
        XCTAssertTrue(timeline(app).waitForNonExistence(timeout: 10), "The timeline stays after Stop")
        XCTAssertFalse(app.descendants(matching: .any)["mini-player"].exists)
        snap(app, "15a-stopped")
    }

    /// The timeline runs down the right edge into the pill. The pill sits in the tab row beside the tabs.
    @MainActor
    func testTimelineAndPill() throws {
        let app = try launchAndConnect()
        let pill = pausedPlayerInLibrary(app)
        let bar = timeline(app)
        XCTAssertTrue(bar.exists)
        XCTAssertEqual(bar.frame.maxX, app.frame.maxX, accuracy: 1, "The timeline is not on the right edge")
        XCTAssertGreaterThan(bar.frame.minY, 40, "The timeline runs into the status bar")
        let frame = pillFrame(pill)
        XCTAssertEqual(frame.maxX, app.frame.maxX, accuracy: 1, "The pill is not flush with the edge")
        XCTAssertEqual(
            pill.buttons["mini-player-cover"].frame.maxX, app.frame.maxX, accuracy: 1,
            "A tap at the screen edge misses the cover")
        XCTAssertLessThan(frame.maxY, app.frame.maxY, "The playback controls have no bottom clearance")
        XCTAssertEqual(bar.frame.maxY, frame.minY, accuracy: 1, "The timeline does not run into the pill")
        XCTAssertEqual(frame.midY, tab(app, "Search").frame.midY, accuracy: 2, "The controls are not in the tab row")
        // Search stands apart in its own circle, so the capsule height comes from a tab inside the capsule.
        XCTAssertEqual(
            frame.height, tab(app, "Chronology").frame.height + 8, accuracy: 1,
            "The pill does not match the native capsule height")
        XCTAssertLessThanOrEqual(tab(app, "Search").frame.maxX, frame.minX, "The tabs run under the pill")
        XCTAssertTrue(pill.buttons["mini-player-cover"].exists)
        XCTAssertEqual(pill.buttons["mini-player-pause"].label, "Resume")
        checkTabAndCoverFrames(app, side: .right)
        snap(app, "15b-timeline-right")

        // The cover opens the overlay. The complete pill stays above it.
        pill.buttons["mini-player-cover"].tap()
        XCTAssertTrue(reveal(app.sliders["position"], in: app).exists, "No position slider in the player")
        XCTAssertTrue(pill.buttons["mini-player-cover"].isHittable)
        snap(app, "15c-player-pill")
        app.buttons["player-handle"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["player-overlay"].firstMatch.waitForNonExistence(timeout: 10))
        checkInteractiveBack(app)
        snap(app, "15h-interactive-back-right")
    }

    /// A vertical drag moves the paused music to the place under the finger. A tap plays the movement under it.
    @MainActor
    func testScrubAndTap() throws {
        let app = try launchAndConnect()
        let pill = pausedPlayerInLibrary(app)
        let bar = timeline(app)
        let start = bar.value as? String ?? ""
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            .press(forDuration: 0.1, thenDragTo: bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        let moved = expectation(for: NSPredicate(format: "value != %@", start), evaluatedWith: bar)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed, "The scrub did not move: \(start)")
        XCTAssertEqual(pill.buttons["mini-player-pause"].label, "Resume", "The scrub started the music")
        snap(app, "15d-scrubbed")

        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        let first = expectation(for: NSPredicate(format: "value BEGINSWITH 'Movement 1 of'"), evaluatedWith: bar)
        XCTAssertEqual(XCTWaiter.wait(for: [first], timeout: 5), .completed, bar.value as? String ?? "")
        let pause = pill.buttons["mini-player-pause"]
        if pause.label == "Pause" { pause.tap() }
    }

    /// The scrub label on each edge, beside a scrub pinned in the middle of the bar (specimen .scrub-label).
    @MainActor
    func testScrubLabelOnEitherEdge() throws {
        for side in ["right", "left"] {
            let app = try launchAndConnect(arguments: ["-\(timelineSideKey)", side, "-pinScrub", "0.5"])
            _ = pausedPlayerInLibrary(app)
            let bar = timeline(app)
            XCTAssertTrue(bar.exists)
            XCTAssertEqual(
                side == "right" ? bar.frame.maxX : bar.frame.minX, side == "right" ? app.frame.maxX : 0,
                accuracy: 1, "The timeline is not on the \(side) edge")
            snap(app, side == "right" ? "15j-scrub-label-right" : "15k-scrub-label-left")
            app.terminate()
        }
    }

    /// On the left edge, a swipe from the edge goes back a page or a place. It never scrubs.
    @MainActor
    func testTimelineOnTheLeft() throws {
        let app = try launchAndConnect(arguments: ["-\(timelineSideKey)", "left"])
        openRecording(app)
        playPaused(app)
        let bar = timeline(app)
        XCTAssertTrue(bar.exists)
        XCTAssertEqual(bar.frame.minX, 0, accuracy: 1, "The timeline is not on the left edge")
        let pill = app.descendants(matching: .any)["mini-player"].firstMatch
        XCTAssertEqual(pillFrame(pill).minX, 0, accuracy: 1, "The pill is not flush with the left edge")
        checkTabAndCoverFrames(app, side: .left)
        snap(app, "15e-timeline-left")
        expectMovementPlayEdge(app, side: .left)

        let place = bar.value as? String ?? ""
        swipeFromLeftEdge(app)
        XCTAssertTrue(
            app.buttons.matching(identifier: "recording").firstMatch.waitForExistence(timeout: 10),
            "The swipe did not go back to the work")
        XCTAssertEqual(bar.value as? String, place, "The swipe scrubbed")
        // The timeline side takes the wider inset, so the content keeps clear of the bar.
        let title = drawn(app.buttons["favourite-work"], in: app, side: .left)
        let play = drawn(app.buttons["play-work"], in: app, side: .left)
        expectPageEdges(title, in: app, side: .left, "Work title on the left")
        expectPageEdges(play, in: app, side: .left, trailing: true, "Play on the left")

        back(app, times: 2)
        openPlace(app, "Chronology")
        expectBackArrow(app, to: "Composers")
        swipeFromLeftEdge(app)
        XCTAssertTrue(tab(app, "Library").waitForSelection(timeout: 10), "The swipe did not go back to Library")
        XCTAssertEqual(bar.value as? String, place, "The swipe scrubbed")
        snap(app, "15f-left-back")
        checkInteractiveBack(app)
        snap(app, "15i-interactive-back-left")
    }

    /// The listener picks the edge in Settings.
    @MainActor
    func testTimelineSetting() throws {
        let app = try launchAndConnect(arguments: ["-\(timelineSideKey)", "right"])
        _ = pausedPlayerInLibrary(app)
        openSettings(app)
        XCTAssertTrue(reveal(app.descendants(matching: .any)["timeline-side"].firstMatch, in: app).exists)
        snap(app, "15g-timeline-setting")
    }
}

/// The settings pages and the diagnostic pages.
final class SettingsScreens: ScreensTestCase {
    @MainActor
    func testScrobbles() throws {
        let app = try launchAndConnect()
        openSettings(app)
        let scrobbles = reveal(app.switches["scrobbles"], in: app)
        XCTAssertTrue(scrobbles.isHittable)
        let value = scrobbles.value as? String
        scrobbles.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertNotEqual(scrobbles.value as? String, value)
        snap(app, "08d-scrobbles")
        scrobbles.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(scrobbles.value as? String, value)
    }

    @MainActor
    func testLocalStorage() throws {
        let app = try launchAndConnect()
        openSettings(app)
        reveal(app.buttons["local-storage"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Local Storage"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["storage-bar"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["storage-album-art"].firstMatch.exists)
        snap(app, "08f-local-storage")
    }

    @MainActor
    func testSettings() throws {
        let app = try launchAndConnect()
        // The mini player must leave the last rows free, so something must be playing.
        _ = pausedPlayerInLibrary(app)
        openSettings(app)
        // Technical Details starts off, so MusicBrainz and Diagnostics stay out of the way.
        let technical = reveal(app.switches["technical-details"], in: app)
        XCTAssertEqual(technical.value as? String, "0", "Technical Details is not off by default")
        XCTAssertFalse(app.buttons["diagnostics"].exists)
        XCTAssertFalse(app.buttons["musicbrainz"].exists)
        technical.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(reveal(app.buttons["diagnostics"], in: app).isHittable)
        for _ in 0..<6 where !row(app, "timeline-side").isHittable { app.swipeDown() }
        snap(app, "08c-settings-top")
        // Flo's groups: Playback, Library, Colour, Advanced settings. Each row follows the one before it.
        let order = [
            "timeline-side", "replaygain", "scrobbles", "classical-rules", "partial-works", "swipe-actions",
            "local-storage", "delete-listening-data", "accent", "player-tint-strength",
            "technical-details", "musicbrainz", "diagnostics", "licences",
        ]
        reveal(row(app, order[0]), in: app)
        for (above, below) in zip(order, order.dropFirst()) {
            let next = reveal(row(app, below), in: app)
            let previous = row(app, above)
            XCTAssertTrue(previous.exists, "\(above) is gone when \(below) shows")
            XCTAssertLessThan(previous.frame.minY, next.frame.minY, "\(below) is not below \(above)")
        }
        snap(app, "08c-settings")
        for _ in 0..<6 where !app.switches["scrobbles"].isHittable { app.swipeDown() }
        XCTAssertTrue(reveal(app.switches["scrobbles"], in: app).exists, "Scrobbles is not in Playback")

        // Swipe Actions in Library comes before the tint in Colour, because the walk only scrolls down.
        reveal(app.buttons["swipe-actions"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Swipe Actions"].waitForExistence(timeout: 10))
        // The list shows the buttons as the row does: Play Next left of Add to Queue.
        let playNext = app.staticTexts["Play Next"].firstMatch
        let addToQueue = app.staticTexts["Add to Queue"].firstMatch
        XCTAssertTrue(playNext.waitForExistence(timeout: 10) && addToQueue.exists, "No swipe left actions")
        XCTAssertLessThan(playNext.frame.minY, addToQueue.frame.minY, "Add to Queue is above Play Next")
        snap(app, "08b-swipe-actions")
        back(app)

        let tint = reveal(app.sliders["player-tint-strength"], in: app)
        XCTAssertTrue(tint.isHittable)
        XCTAssertEqual(tint.value as? String, "3×")
        tint.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(tint.value as? String, "0×")
        tint.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertEqual(tint.value as? String, "2.5×")
        tint.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(tint.value as? String, "5×")
        tint.adjust(toNormalizedSliderPosition: 0.6)
        XCTAssertEqual(tint.value as? String, "3×")
        snap(app, "08f-player-tint-setting")
    }

    /// The drawn ink of the page title, after the push has settled.
    @MainActor
    func titleInk(_ title: String, in app: XCUIApplication) -> CGRect {
        let heading = app.staticTexts.matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "page-heading", title)
        ).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "No title \(title)")
        _ = eventually(timeout: 3) { heading.isHittable && heading.frame.minX >= 0 }
        Thread.sleep(forTimeInterval: 0.5)
        return drawn(heading, in: app)
    }

    /// One row of a grouped list, whatever control it is.
    @MainActor
    func row(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The accent switch recolours the app at once.
    @MainActor
    func testAccent() throws {
        let app = try launchAndConnect()
        openSettings(app)
        // The Timeline picker sits at the top and the accent further down, so the check reads it from the top.
        let timelinePicker = app.buttons["timeline-side"]
        let claret = try XCTUnwrap(pickerInk(timelinePicker, in: app), "No accent ink in the Timeline picker")
        XCTAssertGreaterThan(claret.red, claret.green, "The Timeline picker is not claret: \(claret)")
        let accent = reveal(app.buttons["accent"], in: app)
        XCTAssertTrue(accent.label.contains("Claret"), accent.label)
        accent.tap()
        let green = app.buttons["Bottle Green"].firstMatch
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Plum"].firstMatch.exists)
        green.tap()
        XCTAssertTrue(eventually(timeout: 5) { accent.label.contains("Bottle Green") }, accent.label)
        // Another picker on the page takes the new family at once, not only the picker that changed.
        // The picker must be clear of the top bar, where the soft edge washes out its ink.
        let bar = app.navigationBars.firstMatch
        for _ in 0..<6 where !timelinePicker.isHittable || timelinePicker.frame.minY < bar.frame.maxY {
            app.swipeDown()
        }
        var picked = pickerInk(timelinePicker, in: app)
        XCTAssertTrue(
            eventually(timeout: 5) {
                picked = pickerInk(timelinePicker, in: app)
                return picked.map { $0.green > $0.red } ?? false
            }, "The Timeline picker keeps claret after Bottle Green: \(String(describing: picked))")
        reveal(accent, in: app).tap()
        let plum = app.buttons["Plum"].firstMatch
        XCTAssertTrue(plum.waitForExistence(timeout: 5))
        plum.tap()
        XCTAssertTrue(eventually(timeout: 5) { accent.label.contains("Plum") }, accent.label)
        snap(app, "08i-accent-plum")
        back(app)
        XCTAssertTrue(app.buttons["library-settings"].waitForExistence(timeout: 10))
        snap(app, "08j-library-plum")
    }

    /// The mean accent ink of a picker value: the trailing half of its row holds the value and its chevron.
    @MainActor
    func pickerInk(_ picker: XCUIElement, in app: XCUIApplication) -> (red: Int, green: Int, blue: Int)? {
        let frame = picker.frame.offsetBy(dx: -app.frame.minX, dy: -app.frame.minY)
        let value = CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
        return ScreenPixels(app)?.accentInk(in: value)
    }

    /// Delete Listening Data asks first, then removes the device data of this server and user.
    @MainActor
    func testDeleteListeningData() throws {
        let app = try launchAndConnect()
        openSettings(app)
        reveal(app.buttons["delete-listening-data"], in: app).tap()
        let confirm = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "Delete Listening Data", "delete-listening-data")
        ).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No confirmation")
        // The popover points at the button that opened it, so the whole dialog is on one side of the button.
        let source = app.buttons["delete-listening-data"]
        let title = app.staticTexts["Delete Listening Data?"].firstMatch
        XCTAssertTrue(title.exists, "The dialog has no title")
        let below = title.frame.minY >= source.frame.maxY - 1 && confirm.frame.minY >= source.frame.maxY - 1
        let above = title.frame.maxY <= source.frame.minY + 1 && confirm.frame.maxY <= source.frame.minY + 1
        XCTAssertTrue(
            below || above,
            "The dialog is not on the button: button \(source.frame), title \(title.frame), confirm \(confirm.frame)")
        snap(app, "08k-delete-listening-data")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists, "The device file refused the delete")
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    @MainActor
    func testFilter() throws {
        let app = try launchAndConnect()
        _ = pausedPlayerInLibrary(app)
        openSettings(app)
        reveal(app.buttons["classical-rules"], in: app).tap()
        let field = app.textFields.matching(identifier: "check-text").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let bar = app.tabBars["tab-row"]
        let barFrame = bar.frame
        let lineFrame = timeline(app).frame
        let pill = app.descendants(matching: .any)["mini-player"].firstMatch
        let controlsFrame = pillFrame(pill)
        let chronology = tab(app, "Chronology")
        let labelsBefore = ScreenPixels(app)
        snap(app, "09-filter")
        field.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertEqual(bar.frame.minY, barFrame.minY, accuracy: 2)
        XCTAssertEqual(timeline(app).frame.minY, lineFrame.minY, accuracy: 2)
        XCTAssertEqual(timeline(app).frame.maxY, lineFrame.maxY, accuracy: 2)
        XCTAssertEqual(pillFrame(pill).minY, controlsFrame.minY, accuracy: 2)
        XCTAssertLessThan(keyboard.frame.minY, barFrame.minY)
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY)
        snap(app, "09a-filter-keyboard")
        let original = field.value as? String
        field.typeText("\n")
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 10))
        XCTAssertTrue(field.isHittable)
        XCTAssertEqual(field.value as? String, original)
        XCTAssertEqual(timeline(app).frame.maxY, lineFrame.maxY, accuracy: 2)
        // The tab labels show in full again: the label row of the Chronology tab looks as before the keyboard.
        let labelRow = chronology.frame.divided(atDistance: chronology.frame.height * 0.35, from: .maxYEdge).slice
        var share = 1.0
        for _ in 0..<6 {
            if let before = labelsBefore, let after = ScreenPixels(app) {
                share = after.differingShare(in: labelRow, from: before)
            }
            if share < 0.02 { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertLessThan(share, 0.02, "The Chronology tab label changed after the keyboard closed")
        snap(app, "09b-keyboard-closed")
    }

    @MainActor
    func testClassicalAlbums() throws {
        let app = try launchAndConnect()
        // Every page title sits at the same gap under the bar: grouped Settings, the Classical Rules form and a
        // plain list.
        openSettings(app)
        let settingsTitle = titleInk("Settings", in: app)
        reveal(app.buttons["classical-rules"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Classical Rules"].waitForExistence(timeout: 10))
        let rulesTitle = titleInk("Classical Rules", in: app)
        // The result comes before the rules.
        let albums = app.buttons["classical-albums"]
        XCTAssertTrue(albums.waitForExistence(timeout: 10))
        // A row can merge its label and value into one element, so the check reads every element that shows one.
        let shares = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", " on server"))
        let shareRows = shares.allElementsBoundByIndex.map(\.frame)
        XCTAssertGreaterThanOrEqual(Set(shareRows.map { $0.minY.rounded() }).count, 2, "No albums and tracks result")
        let firstCheck = app.buttons["add-check"].firstMatch
        XCTAssertTrue(firstCheck.exists)
        let resultBottom = shareRows.map(\.maxY).max() ?? .infinity
        XCTAssertLessThan(resultBottom, firstCheck.frame.minY, "The result is not above the rules")
        snap(app, "09c-classical-rules")
        albums.tap()
        let albumsTitle = titleInk("Classical Albums", in: app)
        XCTAssertEqual(settingsTitle.minY, albumsTitle.minY, accuracy: 2, "Settings title gap")
        XCTAssertEqual(rulesTitle.minY, albumsTitle.minY, accuracy: 2, "Classical Rules title gap")
        let concerto = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Mendelssohn: Violin Concerto'")).firstMatch
        XCTAssertTrue(concerto.waitForExistence(timeout: 10))
        let encores = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Romantic Encores'")).firstMatch
        XCTAssertTrue(reveal(encores, in: app).isHittable)
        let performers = ["Carl Fixture", "Daniel Keys", "Sine Wave Chamber Orchestra"]
        for name in performers { XCTAssertTrue(encores.label.contains(name), encores.label) }
        snap(app, "10-classical-albums")
        // A tap opens the album. It does not start to play.
        encores.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        back(app)
        XCTAssertTrue(reveal(encores, in: app).isHittable)
        for name in performers { XCTAssertTrue(encores.label.contains(name), encores.label) }
    }

    @MainActor
    func testDiagnostics() throws {
        let app = try launchAndConnect()
        // Diagnostics checks that the mini player leaves the last row free, so something must be playing.
        let bar = pausedPlayerInLibrary(app)
        openSettings(app, technical: true)
        reveal(app.buttons["diagnostics"], in: app).tap()
        XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["opensubsonic"].waitForExistence(timeout: 10))
        snap(app, "11-diagnostics")
        let signOut = reveal(app.buttons["Sign Out"], in: app)
        XCTAssertTrue(signOut.isHittable)
        XCTAssertLessThanOrEqual(signOut.frame.maxY, bar.frame.minY, "The mini player covers the last row.")
        snap(app, "12-diagnostics-bottom")

        let showTaps = reveal(app.switches["show-taps"], in: app)
        showTaps.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let on = expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: showTaps)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 10), .completed, "\(showTaps.value ?? "nil")")
        snap(app, "12a-show-taps")
    }

    @MainActor
    func testGapless() throws {
        let app = try launchAndConnect()
        openSettings(app, technical: true)
        reveal(app.buttons["diagnostics"], in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["opensubsonic"].waitForExistence(timeout: 10))
        reveal(app.buttons["gapless-test"], in: app).tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Mendelssohn\n")
        let album = app.buttons.matching(identifier: "gapless-album").firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 15))
        snap(app, "13-gapless-search")

        album.tap()
        let track = app.buttons.matching(identifier: "gapless-track").firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 15))
        track.tap()
        let analysis = app.buttons.matching(NSPredicate(format: "label CONTAINS 'iOS decodes'")).firstMatch
        XCTAssertTrue(analysis.waitForExistence(timeout: 30))
        snap(app, "14-gapless-album")
    }
}

/// What every area needs: the fixture server, the MusicBrainz answers, and the steps that several tests share.
/// The screens workflow passes the server through TEST_RUNNER_KLASSIK_* variables.
class ScreensTestCase: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        // A failed launch must stop before later queries use an invalid app process.
        continueAfterFailure = false
    }

    /// MusicBrainz answers for the fixture works, shaped like real ones, by the keys of `Enrichment.stubKey`.
    /// Bach, Brahms and the nocturnes get no answer, as if MusicBrainz had no match.
    static let musicBrainz: String = {
        let beethoven = "1f9df192-a621-4f54-8850-2c5373b7eac9"
        let mendelssohn = "0e85eb79-1c05-44ba-827c-7b259a3d941a"
        let mozart = "b972f589-fb0e-474e-b64a-803b0364fa75"
        let fifth = "6efdb083-5bff-465e-b07d-41925e877788"
        let concerto = "c230858f-8b2b-3e77-aa3e-777743980263"
        let k467 = "f210c793-f668-413c-8821-3628b3c55483"
        let chopin = "09ff1fe8-d61c-4b98-bb82-18487c74d7b7"
        func listed(_ id: String, _ title: String, _ begin: String) -> String {
            #"{"id":"\#(id)","title":"\#(title)","relations":[{"type":"composer","direction":"backward","begin":"\#(begin)","artist":{"id":"\#(chopin)"}}]}"#
        }
        func work(_ id: String, _ title: String, _ begin: String, _ end: String, _ composer: String) -> String {
            """
            {"id":"\(id)","title":"\(title)","relations":[{"type":"composer","direction":"backward",\
            "begin":"\(begin)","end":"\(end)","artist":{"id":"\(composer)"}}]}
            """
        }
        func artist(_ id: String, _ name: String, _ born: String, _ died: String) -> String {
            #"{"id":"\#(id)","name":"\#(name)","score":100,"life-span":{"begin":"\#(born)","end":"\#(died)"}}"#
        }
        let bodies = [
            "work/\(fifth)": work(fifth, "Symphony no. 5 in C minor, op. 67", "1804", "1808", beethoven),
            "artist/\(beethoven)": artist(beethoven, "Ludwig van Beethoven", "1770-12-16", "1827-03-26"),
            "work?\"op. 64\" AND artist:\"Mendelssohn\"": """
            {"works":[{"id":"\(concerto)","score":95,"title":"Violinkonzert in e-Moll, op. 64"}]}
            """,
            "work/\(concerto)": work(concerto, "Violinkonzert in e-Moll, op. 64", "1844", "1844", mendelssohn),
            "artist/\(mendelssohn)": artist(mendelssohn, "Felix Mendelssohn", "1809-02-03", "1847-11-04"),
            "work?\"K. 467\" AND artist:\"Mozart\"": """
            {"works":[{"id":"\(k467)","score":100,"title":"Klavierkonzert Nr. 21 C-Dur, K. 467"},\
            {"id":"29d6128d-d64e-4db0-a099-4a8b79331d46","score":96,"title":"Klavierkonzert Nr. 21, K. 467 „Elvira Madigan“"}]}
            """,
            "work/\(k467)": work(k467, "Klavierkonzert Nr. 21 C-Dur, K. 467", "1785", "1785", mozart),
            "artist/\(mozart)": artist(mozart, "Wolfgang Amadeus Mozart", "1756-01-27", "1791-12-05"),
            // The nocturnes come from one list of Chopin's works, not from one search each.
            "work?artist=\(chopin)&offset=0": """
            {"work-count":4,"works":[\([
                listed("00000000-0000-4000-8000-000000000011", "Nocturne in B‐flat minor, op. 9 no. 1", "1830"),
                listed("00000000-0000-4000-8000-000000000012", "Nocturne in E‐flat major, op. 9 no. 2", "1831"),
                listed("00000000-0000-4000-8000-000000000013", "Nocturne in F major, op. 15 no. 1", "1832"),
                listed(
                    "00000000-0000-4000-8000-000000000014",
                    "Nocturne no. 20 in C‐sharp minor “Reminiscence”, op. posth. 1 no. 16, KKIVa/16", "1830"),
            ].joined(separator: ","))]}
            """,
            "artist?(artist:\"Frédéric Chopin\" OR alias:\"Frédéric Chopin\") AND type:person": """
            {"artists":[\(artist("09ff1fe8-d61c-4b98-bb82-18487c74d7b7", "Fryderyk Chopin", "1810-03-01", "1849-10-17"))]}
            """,
        ]
        return String(decoding: try! JSONEncoder().encode(bodies), as: UTF8.self)
    }()

    /// Wikidata, Commons and Wikipedia answers for Mendelssohn, shaped like the live ones, as pairs of the text
    /// that the URL holds and the body. The Commons answer names thumb.wikimedia.org, as the live one does.
    /// Every other person gets no answer, as if Wikidata had none.
    static let people: String = {
        let mendelssohn = "0e85eb79-1c05-44ba-827c-7b259a3d941a"
        let entity = """
            {"entities":{"Q46096":{"id":"Q46096","labels":{"en":{"value":"Felix Mendelssohn"}},\
            "descriptions":{"en":{"value":"German composer and conductor"}},\
            "claims":{"P569":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"time":"+1809-02-03T00:00:00Z","precision":11}}}}],\
            "P570":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"time":"+1847-11-04T00:00:00Z","precision":11}}}}],\
            "P18":[{"rank":"normal","mainsnak":{"datavalue":{"value":"Fixture portrait.png"}}}]},\
            "sitelinks":{"enwiki":{"title":"Felix Mendelssohn"}}}}}
            """
        // Four more composers with life dates and a work period start (P2031), so that the Chronology has
        // contemporaries. Each is found by name with the composer occupation.
        func composer(_ qid: String, _ name: String, _ born: String, _ died: String, _ active: String) -> [[String]] {
            func date(_ property: String, _ year: String) -> String {
                #""\#(property)":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"time":"+\#(year)-01-01T00:00:00Z","precision":9}}}}]"#
            }
            let entity = """
                {"entities":{"\(qid)":{"id":"\(qid)","labels":{"en":{"value":"\(name)"}},\
                "descriptions":{"en":{"value":"composer"}},\
                "claims":{\(date("P569", born)),\(date("P570", died)),\(date("P2031", active))}}}}
                """
            return [
                ["\"\(name)\" haswbstatement:P106", #"{"query":{"search":[{"title":"\#(qid)"}]}}"#],
                ["ids=\(qid)&props=labels|descriptions|claims", entity],
                ["ids=\(qid)&props=labels|descriptions", entity],
            ]
        }
        // Wikidata gives the composer occupation to Beethoven's relatives and friends, so his name search finds
        // them too, as the live search does. His grandfather has his full name.
        let beethovenHits = [
            ("Q255", "Ludwig van Beethoven", "German composer (1770-1827)"),
            ("Q12368917", "Ludwig van Beethoven", "grandfather of composer Ludwig van Beethoven"),
            ("Q2153541", "Johann van Beethoven", "father of Ludwig van Beethoven"),
            ("Q64862", "Anton Schindler", "Associate, secretary, and early biographer of Ludwig van Beethoven"),
            ("Q6374627", "Kaspar Anton Karl van Beethoven", "German composer, brother of Ludwig van Beethoven"),
            ("Q472851", "Count Ferdinand Ernst Gabriel von Waldstein", "British Army general (1762-1823)"),
            ("Q6216444", "Johanna van Beethoven", "Beethoven's sister-in-law"),
        ]
        let beethovenLabels = beethovenHits.map { qid, name, description in
            #""\#(qid)":{"id":"\#(qid)","labels":{"en":{"value":"\#(name)"}},"descriptions":{"en":{"value":"\#(description)"}}}"#
        }
        let beethoven: [[String]] = [
            [
                "\"Ludwig van Beethoven\" haswbstatement:P106",
                #"{"query":{"search":["# + beethovenHits.map { #"{"title":"\#($0.0)"}"# }.joined(separator: ",")
                    + "]}}",
            ],
            [
                "ids=" + beethovenHits.map(\.0).joined(separator: "|"),
                #"{"entities":{"# + beethovenLabels.joined(separator: ",") + "}}",
            ],
        ]
        let pairs: [[String]] =
            beethoven
            + composer("Q254", "Wolfgang Amadeus Mozart", "1756", "1791", "1761")
            + composer("Q255", "Ludwig van Beethoven", "1770", "1827", "1782")
            + composer("Q1268", "Frédéric Chopin", "1810", "1849", "1817")
            + composer("Q7294", "Johannes Brahms", "1833", "1897", "1851")
            + [
                ["haswbstatement:P434=\(mendelssohn)", #"{"query":{"search":[{"title":"Q46096"}]}}"#],
                ["\"Felix Mendelssohn\" haswbstatement:P106", #"{"query":{"search":[{"title":"Q46096"}]}}"#],
                // The first rule that matches answers: the longer text goes first. A search reads the same body.
                ["ids=Q46096&props=labels|descriptions|claims", entity],
                ["ids=Q46096&props=labels|descriptions", entity],
                ["page/summary/Felix_Mendelssohn", #"{"extract":"Felix Mendelssohn was a German composer."}"#],
                [
                    "commons.wikimedia.org/w/api.php",
                    """
                    {"query":{"pages":{"1":{"imageinfo":[{"thumburl":\
                    "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/Fixture_portrait.jpg/1280px-Fixture_portrait.jpg",\
                    "url":"https://upload.wikimedia.org/wikipedia/commons/f/f0/Fixture_portrait.jpg","width":3000,"height":4000,\
                    "descriptionurl":"https://commons.wikimedia.org/wiki/File:Fixture_portrait.png","extmetadata":{\
                    "Artist":{"value":"<a href=\\"//x\\">Fixture Studio</a>"},"LicenseShortName":{"value":"Public domain"}}}]}}}}
                    """,
                ],
                // Any other name finds nobody.
                ["list=search", #"{"query":{"search":[]}}"#],
            ]
        return String(decoding: try! JSONEncoder().encode(pairs), as: UTF8.self)
    }()

    @MainActor
    func launchAndConnect(
        snapConnect: Bool = false, openComposers: Bool = true, arguments: [String] = []
    ) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["KLASSIK_SERVER_URL"] else { throw XCTSkip("No fixture server configured") }

        let app = XCUIApplication()
        app.launchArguments = ["-resetServer"] + arguments
        // Xcode sets OS_ACTIVITY_DT_MODE, which copies each log message of the app to its stderr. XCTest logs
        // every attribute that a query reads, inside the app. On a busy runner the main thread then blocks on the
        // console pipe: queries time out, frames read as infinite, and the app does not terminate.
        app.launchEnvironment = [
            "OS_ACTIVITY_DT_MODE": "NO",
            "KLASSIK_SERVER_URL": server,
            "KLASSIK_USERNAME": env["KLASSIK_USERNAME"] ?? "",
            "KLASSIK_PASSWORD": env["KLASSIK_PASSWORD"] ?? "",
            "KLASSIK_MUSICBRAINZ_STUB": Self.musicBrainz,
            "KLASSIK_PERSON_STUB": Self.people,
        ]
        app.launch()

        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        if snapConnect { snap(app, "01-connect") }
        connect.tap()
        // The Library place lists its rows at once. The composers fill in while the first sync runs.
        let composers = app.buttons["library-composers"]
        XCTAssertTrue(composers.waitForExistence(timeout: 30))
        if openComposers {
            composers.tap()
            XCTAssertTrue(composer(app, "Felix Mendelssohn").waitForExistence(timeout: 30))
        }
        return app
    }

    /// A place opened from another one shows an arrow like the system back button: a chevron with no name on
    /// screen. Its label names the place or page behind it.
    @MainActor
    func expectBackArrow(_ app: XCUIApplication, to name: String) {
        let arrow = app.buttons["place-back"]
        XCTAssertTrue(arrow.waitForExistence(timeout: 10), "No back arrow")
        XCTAssertTrue(arrow.label.contains(name), "The back arrow reads \"\(arrow.label)\", not \"\(name)\"")
        // A chevron in a glass circle is about 44 points wide. A button that also draws a name is wider.
        XCTAssertLessThan(arrow.frame.width, 64, "The back arrow draws a name: \(arrow.frame.width) points wide")
    }

    /// A swipe from the left screen edge to the middle, as a thumb makes it.
    @MainActor
    func swipeFromLeftEdge(_ app: XCUIApplication) {
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        edge.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
    }

    /// Both completed and cancelled drags must preserve playback and each tab's stack.
    @MainActor
    func checkInteractiveBack(_ app: XCUIApplication) {
        let bar = timeline(app)
        let before = bar.value as? String
        composer(app, "Felix Mendelssohn").tap()
        XCTAssertTrue(app.navigationBars["Felix Mendelssohn"].waitForExistence(timeout: 10))
        openPlace(app, "Search")
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.001, dy: 0.4))
        let short = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.4))
        origin.press(forDuration: 0.05, thenDragTo: short, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(eventually(timeout: 5) { tab(app, "Search").isSelected })
        expectBackArrow(app, to: "Mendelssohn")
        swipeBack(app, to: "Felix Mendelssohn")
        swipeBack(app, to: "Composers")
        XCTAssertEqual(bar.value as? String, before, "Back changed the playback position")
    }

    /// Opens the menu in the bar of a work, recording or album page and returns its item with the title.
    @MainActor
    func pageMenuItem(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let menu = app.buttons["page-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "The page has no menu")
        menu.tap()
        let item = menuItem(app, title)
        _ = item.waitForExistence(timeout: 3)
        return item
    }

    /// An item of an open menu. The line below the title can join the title in the label, as "Download, 1 MB".
    @MainActor
    func menuItem(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ",")).firstMatch
    }

    /// A tap beside an open menu closes it and reaches nothing below.
    @MainActor
    func closeMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    /// Opens the player from the cover of the mini player.
    @MainActor
    func openPlayer(_ app: XCUIApplication) {
        app.buttons["mini-player-cover"].tap()
        let handle = app.buttons["player-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        // The overlay slides in below the tab row, so the handle becomes hittable only when the slide ends.
        XCTAssertTrue(eventually(timeout: 5) { handle.isHittable }, "The player is behind the selected place")
    }

    /// Drags down from a row of a sheet to near the bottom of the screen, the way a finger closes a sheet.
    @MainActor
    func swipeSheetDown(from element: XCUIElement, in app: XCUIApplication) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
            withVelocity: .fast, thenHoldForDuration: 0)
    }

    @MainActor
    func expectPlayerClosed(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["player-handle"].waitForNonExistence(timeout: 10))
    }

    /// Swipes from the left edge until the page with this title shows. A drag that starts while the last pop
    /// still settles is lost, so a lost drag swipes again; three lost drags fail the check.
    @MainActor
    func swipeBack(_ app: XCUIApplication, to title: String, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 {
            swipeFromLeftEdge(app)
            if app.navigationBars[title].waitForExistence(timeout: 4) { return }
        }
        XCTFail("Three edge swipes did not reach \(title)", file: file, line: line)
    }

    /// The key of the timeline edge in the user defaults. A launch argument sets it for one run.
    let timelineSideKey = "timeline.side"

    /// A place in the tab bar, which Klassik draws by hand beside the mini player.
    @MainActor
    func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let identified = app.buttons["tab-\(name.lowercased())"]
        // A UITab can leave its bar button without the identifier; the bar then names the tab by its title.
        return identified.exists ? identified : app.tabBars["tab-row"].buttons[name]
    }

    /// Settings belongs to the Library stack, behind its toolbar cog. `technical` turns on Technical Details, so
    /// that MusicBrainz and Diagnostics show. A reset launch turns the switch off again.
    @MainActor
    func openSettings(_ app: XCUIApplication, technical: Bool = false) {
        openPlace(app, "Library")
        for _ in 0..<10 where !app.buttons["library-settings"].exists { back(app) }
        let cog = app.buttons["library-settings"]
        XCTAssertTrue(cog.waitForExistence(timeout: 10))
        cog.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        guard technical else { return }
        let toggle = reveal(app.switches["technical-details"], in: app)
        // The switch reports its new value after its animation. A tap during the page's push can be lost; one
        // more tap follows then.
        for _ in 0..<2 where toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            _ = eventually(timeout: 3) { toggle.value as? String == "1" }
        }
        XCTAssertEqual(toggle.value as? String, "1", "Technical Details does not turn on")
    }

    /// The classical albums open from the Result rows of Classical Rules.
    @MainActor
    func openClassicalAlbums(_ app: XCUIApplication) {
        openSettings(app)
        reveal(app.buttons["classical-rules"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Classical Rules"].waitForExistence(timeout: 10))
        reveal(app.buttons["classical-albums"], in: app).tap()
    }

    /// Taps a place in the tab bar.
    @MainActor
    func openPlace(_ app: XCUIApplication, _ name: String) {
        let tab = tab(app, name)
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "No tab \(name)")
        // The Search tab focuses its field, and the keyboard covers the tab bar.
        if app.keyboards.firstMatch.exists, !tab.isHittable {
            app.swipeDown()
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
        }
        tab.tap()
    }

    @MainActor
    func timeline(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["timeline"].firstMatch
    }

    @MainActor
    func composer(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "composer").matching(NSPredicate(format: "label BEGINSWITH %@", name))
            .firstMatch
    }

    /// Goes back one page. UIKit gives the back button of a navigation bar the identifier "BackButton".
    @MainActor
    func back(_ app: XCUIApplication, times: Int = 1) {
        for _ in 0..<times {
            let named = app.navigationBars.buttons["BackButton"].firstMatch
            // A system that names the button differently still has it first in the bar.
            let button = named.waitForExistence(timeout: 5) ? named : app.navigationBars.buttons.firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "No back button")
            button.tap()
        }
    }

    /// Opens the first recording of the first Mendelssohn work.
    @MainActor
    func openRecording(_ app: XCUIApplication) {
        composer(app, "Felix Mendelssohn").tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        let recording = app.buttons.matching(identifier: "recording").firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 10))
        recording.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
    }

    /// Plays the open recording and pauses it. The fixture movements last seconds; paused, the player stays.
    @MainActor
    func playPaused(_ app: XCUIApplication) {
        startPlaying(app)
        pause(app)
    }

    /// Taps Play on the open recording and waits for the mini player, which exists from the first moment of a queue.
    /// A tap that starts nothing fails here with the screen and the element tree, not later at a missing button.
    @MainActor
    func startPlaying(_ app: XCUIApplication) {
        app.buttons["play-recording"].tap()
        let pill = app.descendants(matching: .any)["mini-player"].firstMatch
        if !pill.waitForExistence(timeout: 15) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "screen-after-play"
            shot.lifetime = .keepAlways
            add(shot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tree-after-play"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("Play did not start the queue")
        }
    }

    /// Pauses with the button of the mini player, which stays in the tab row whatever the page shows. The button
    /// must read "Pause" first: a queue that never started sound reads "Resume" and must fail here. The fixture
    /// movements last seconds, so the walk pauses at once.
    @MainActor
    func pause(_ app: XCUIApplication) {
        let button = app.buttons["mini-player-pause"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No pause button in the mini player")
        let playing = NSPredicate(format: "label == 'Pause'")
        let started = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: button)], timeout: 10)
        XCTAssertEqual(started, .completed, "Play did not start playback: the pill reads \(button.label)")
        button.tap()
        XCTAssertTrue(app.buttons["Resume"].firstMatch.waitForExistence(timeout: 10), "The player did not pause")
    }

    /// The frame of the mini player. Its buttons take its padding and fill it to its edges. XCUITest reports the
    /// container with only part of its content, so its own frame does not show the pill.
    @MainActor
    func pillFrame(_ pill: XCUIElement) -> CGRect {
        pill.buttons.allElementsBoundByIndex.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }

    enum PillEdge { case left, right }

    @MainActor
    func checkTabAndCoverFrames(_ app: XCUIApplication, side: PillEdge) {
        let buttons = ["Library", "Chronology", "Search"].map { tab(app, $0) }
        // UIKit expands button frames beyond their slots. Image frames exclude this extra area.
        let tabs = buttons.map { $0.images.firstMatch.frame }
        for frame in tabs { XCTAssertGreaterThan(frame.width, 0, "A tab has no image") }
        for (left, right) in zip(tabs, tabs.dropFirst()) {
            XCTAssertLessThanOrEqual(left.maxX, right.minX, "The visible tab frames overlap")
            XCTAssertGreaterThanOrEqual(right.midX - left.midX, 64, "The tab slots crowd their labels")
        }
        // Search stands apart in its own circle: the capsule edge and the gap make its step wider than a capsule step.
        // In one capsule all steps are equal. The mini player narrows the bar, so the margin stays small.
        XCTAssertGreaterThan(
            tabs[2].midX - tabs[1].midX, tabs[1].midX - tabs[0].midX + 8, "Search is not apart from the other tabs")
        let cover = app.buttons["mini-player-cover"].frame
        // The button includes the edge padding; its inward edge is the square cover's inward edge.
        let distance = side == .right ? app.frame.maxX - cover.minX : cover.maxX - app.frame.minX
        XCTAssertGreaterThan(cover.width, 0, "The cover has no width")
        XCTAssertLessThanOrEqual(distance, 96, "The cover is too far from the display edge")
        if side == .right {
            XCTAssertLessThanOrEqual(tabs.last!.maxX, cover.minX, "The tabs run under the cover")
        } else {
            XCTAssertGreaterThanOrEqual(tabs.first!.minX, cover.maxX, "The tabs run under the cover")
        }
    }

    /// What an element draws on the screen: the bounds of its ink, in screen points. SwiftUI merges a list row that
    /// holds one accessible element into its cell, and the element then reports the whole cell, row insets included.
    /// The ink shows where the view draws inside that frame, so a wrong row inset changes the measured gaps.
    /// An element without ink reports its frame.
    @MainActor
    func drawn(_ element: XCUIElement, in app: XCUIApplication, side: PillEdge = .right) -> CGRect {
        let frame = element.frame
        return ink(in: frame, of: app, side: side) ?? frame
    }

    /// The capsule's flat fill separates its visible label from the accessibility frame of the whole row.
    @MainActor
    func expectCapsuleLabelCentered(_ frame: CGRect, in app: XCUIApplication) {
        guard let screen = ScreenPixels(app) else { return XCTFail("No screenshot for the capsule label") }
        let local = frame.offsetBy(dx: -app.frame.minX, dy: -app.frame.minY)
        let columns = screen.pixels((local.minX + local.height / 2)...(local.maxX - local.height / 2))
            .clamped(to: 0..<screen.width)
        let rows = screen.pixels((local.minY + local.height / 4)...(local.maxY - local.height / 4))
            .clamped(to: 0..<screen.height)
        var (first, last) = (Int.max, Int.min)
        for y in rows {
            for x in columns where screen.differs(x, y, from: columns.lowerBound) {
                first = min(first, x)
                last = max(last, x)
            }
        }
        guard first <= last else { return XCTFail("No visible capsule label") }
        let center = app.frame.minX + CGFloat(first + last + 1) / (2 * screen.scale)
        XCTAssertEqual(center, frame.midX, accuracy: 1.5, "The icon and text do not center on the capsule")
    }

    /// The screen of the app as bytes, to compare pixels with the page ground.
    struct ScreenPixels {
        let width: Int
        let height: Int
        /// Pixels for each point.
        let scale: CGFloat
        private var bytes: [UInt8]

        @MainActor
        init?(_ app: XCUIApplication) {
            guard let image = app.screenshot().image.cgImage, app.frame.width > 0 else { return nil }
            width = image.width
            height = image.height
            scale = CGFloat(width) / app.frame.width
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            let (pixelWidth, pixelHeight) = (image.width, image.height)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                        bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                return true
            }
            guard drawn else { return nil }
        }

        /// True when the pixel differs from the pixel of the same row in the ground column.
        /// Each row has its own ground, so a soft edge that shades the screen from the top does not count as ink.
        func differs(_ x: Int, _ y: Int, from groundX: Int) -> Bool {
            let index = (y * width + x) * 4
            let ground = (y * width + groundX) * 4
            return (0..<3).reduce(0) { $0 + abs(Int(bytes[index + $1]) - Int(bytes[ground + $1])) } > 30
        }

        /// The default Claret capsule has white ink. Its inset path excludes the pale page around curved ends.
        func lightLabelBounds(in frame: CGRect) -> CGRect? {
            let inside = frame.insetBy(dx: 1, dy: 1)
            let path = CGPath(
                roundedRect: inside, cornerWidth: inside.height / 2, cornerHeight: inside.height / 2,
                transform: nil)
            let xs = pixels(frame.minX...frame.maxX).clamped(to: 0..<width)
            let ys = pixels(frame.minY...frame.maxY).clamped(to: 0..<height)
            var (first, last) = (Int.max, Int.min)
            for y in ys {
                for x in xs {
                    let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                    guard path.contains(point) else { continue }
                    let index = (y * width + x) * 4
                    if bytes[index..<(index + 3)].allSatisfy({ $0 > 200 }) {
                        first = min(first, x)
                        last = max(last, x)
                    }
                }
            }
            guard first <= last else { return nil }
            return CGRect(
                x: CGFloat(first) / scale, y: frame.minY, width: CGFloat(last + 1 - first) / scale, height: frame.height
            )
        }

        /// The mean colour of the coloured pixels in a rect, in points. Text, hairlines and the page ground are
        /// grey, so only the accent ink counts.
        func accentInk(in rect: CGRect) -> (red: Int, green: Int, blue: Int)? {
            let xs = pixels(rect.minX...rect.maxX).clamped(to: 0..<width)
            let ys = pixels(rect.minY...rect.maxY).clamped(to: 0..<height)
            var (sum, count) = ([0, 0, 0], 0)
            for y in ys {
                for x in xs {
                    let index = (y * width + x) * 4
                    let pixel = (0..<3).map { Int(bytes[index + $0]) }
                    guard let high = pixel.max(), let low = pixel.min(), high - low > 40 else { continue }
                    sum = zip(sum, pixel).map { $0 + $1 }
                    count += 1
                }
            }
            guard count > 0 else { return nil }
            return (sum[0] / count, sum[1] / count, sum[2] / count)
        }

        /// The share of pixels in a rect, in points, that differ from the same pixels of another screenshot.
        func differingShare(in rect: CGRect, from other: ScreenPixels) -> Double {
            let xs = max(0, Int(rect.minX * scale))..<min(width, other.width, Int(rect.maxX * scale))
            let ys = max(0, Int(rect.minY * scale))..<min(height, other.height, Int(rect.maxY * scale))
            guard !xs.isEmpty, !ys.isEmpty else { return 1 }
            var differing = 0
            for y in ys {
                for x in xs {
                    let index = (y * width + x) * 4
                    let otherIndex = (y * other.width + x) * 4
                    let distance = (0..<3).reduce(0) {
                        $0 + abs(Int(bytes[index + $1]) - Int(other.bytes[otherIndex + $1]))
                    }
                    if distance > 30 { differing += 1 }
                }
            }
            return Double(differing) / Double(xs.count * ys.count)
        }

        /// The pixel columns that content may use: the columns of the timeline bar are not content.
        func contentColumns(side: PillEdge) -> Range<Int> {
            let skip = Int(((Measure.timeline + Measure.timelineCap) * scale).rounded(.up))
            return side == .right ? 0..<(width - skip) : skip..<width
        }

        /// A column of page ground on the side away from the timeline, inside every page edge.
        func groundColumn(side: PillEdge) -> Int {
            side == .right ? Int(scale) : width - 1 - Int(scale)
        }

        /// True when two pixels differ in colour.
        func differs(_ a: (x: Int, y: Int), _ b: (x: Int, y: Int)) -> Bool {
            let (first, second) = ((a.y * width + a.x) * 4, (b.y * width + b.x) * 4)
            return (0..<3).reduce(0) { $0 + abs(Int(bytes[first + $1]) - Int(bytes[second + $1])) } > 30
        }

        func pixels(_ range: ClosedRange<CGFloat>) -> Range<Int> {
            Int((range.lowerBound * scale).rounded())..<Int((range.upperBound * scale).rounded())
        }
    }

    /// The player of a new item opens at its top, so its wash keeps the full colour below the details and fades into
    /// the page ground at `Layout.washHeight`, as the specimen does when the item changes.
    /// The wash comes after its cover loads, so the check waits for it, but for less than the quiet spell.
    @MainActor
    func expectWashFromTheTop(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let player = app.descendants(matching: .any)["player-overlay"].firstMatch
        XCTAssertTrue(player.exists, "No player", file: file, line: line)
        // The overlay lies under the status bar, so the wash starts at the top of the screen at the latest.
        let top = max(player.frame.minY - app.frame.minY, 0)
        let points = (
            top: top + 24, solid: top + Layout.washHeight * Layout.washSolid - 16, ground: top + Layout.washHeight + 16
        )
        guard points.ground < app.frame.height else {
            return XCTFail("The screen is shorter than the wash", file: file, line: line)
        }
        let deadline = Date().addingTimeInterval(4)
        var found = "no screenshot"
        repeat {
            if let screen = ScreenPixels(app) {
                let x = screen.groundColumn(side: .right)
                let pixel = { (y: CGFloat) in (x: x, y: min(Int((y * screen.scale).rounded()), screen.height - 1)) }
                let even = !screen.differs(pixel(points.top), pixel(points.solid))
                let washed = screen.differs(pixel(points.solid), pixel(points.ground))
                if even, washed { return }
                found = "full colour to the solid stop: \(even), wash above the ground: \(washed)"
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        snap(app, "08d-next-player")
        XCTFail("The wash of the next item does not start at the top: \(found)", file: file, line: line)
    }

    /// The bounds of the pixels inside `frame` that differ from the page ground, in screen points. A list cell spans
    /// the screen; its top and bottom point are skipped, so a row hairline does not count.
    @MainActor
    func ink(in frame: CGRect, of app: XCUIApplication, side: PillEdge) -> CGRect? {
        guard let screen = ScreenPixels(app), frame.width > 0, frame.height > 2 else { return nil }
        let local = frame.offsetBy(dx: -app.frame.minX, dy: -app.frame.minY)
        let allowed = screen.contentColumns(side: side)
        let columns = screen.pixels(local.minX...local.maxX).clamped(to: allowed)
        let hairline: CGFloat = frame.width >= app.frame.width - 1 ? 1 : 0
        let rows = screen.pixels((local.minY + hairline)...(local.maxY - hairline)).clamped(to: 0..<screen.height)
        let ground = screen.groundColumn(side: side)
        var (minX, maxX, minY, maxY) = (Int.max, Int.min, Int.max, Int.min)
        for y in rows {
            for x in columns where screen.differs(x, y, from: ground) {
                (minX, maxX, minY, maxY) = (min(minX, x), max(maxX, x), min(minY, y), max(maxY, y))
            }
        }
        guard minX <= maxX else { return nil }
        let scale = screen.scale
        return CGRect(
            x: app.frame.minX + CGFloat(minX) / scale, y: app.frame.minY + CGFloat(minY) / scale,
            width: CGFloat(maxX + 1 - minX) / scale, height: CGFloat(maxY + 1 - minY) / scale)
    }

    /// The hairline between two adjacent list rows, from its drawn pixels, against the page edges: the specimen
    /// hairline spans the row content from the leading to the trailing page edge.
    @MainActor
    func expectHairline(
        between upper: XCUIElement, and lower: XCUIElement, in app: XCUIApplication, side: PillEdge = .right,
        _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let screen = ScreenPixels(app) else { return XCTFail("\(name): no screenshot", file: file, line: line) }
        let border = lower.frame.minY - app.frame.minY
        XCTAssertEqual(upper.frame.maxY, lower.frame.minY, accuracy: 1, "\(name): the rows are not adjacent")
        let ground = screen.groundColumn(side: side)
        let columns = screen.contentColumns(side: side)
        // The hairline is the row near the border with the longest run of ink.
        let spans = screen.pixels((border - 1)...(border + 1)).compactMap { y -> Range<Int>? in
            let ink = columns.filter { screen.differs($0, y, from: ground) }
            guard let first = ink.first, let last = ink.last else { return nil }
            return first..<(last + 1)
        }
        guard let span = spans.max(by: { $0.count < $1.count }) else {
            return XCTFail("\(name): no hairline", file: file, line: line)
        }
        let frame = CGRect(
            x: app.frame.minX + CGFloat(span.lowerBound) / screen.scale, y: lower.frame.minY,
            width: CGFloat(span.count) / screen.scale, height: 1 / screen.scale)
        expectPageEdges(frame, in: app, side: side, trailing: true, name, file: file, line: line)
    }

    /// The left and right page insets of Layout.swift for the timeline that the app shows now, if any.
    @MainActor
    func pageInsets(_ app: XCUIApplication, side: PillEdge) -> (left: CGFloat, right: CGFloat) {
        let shown = app.descendants(matching: .any)["timeline"].exists
        return Layout.sideInsets(timelineOnLeft: shown ? side == .left : nil)
    }

    /// The distance of a drawn frame from the display edges against the page edges of Layout.swift. A shown
    /// timeline adds its width on its side; without one both sides are equal. A text checks only its leading edge: its frame can run to the trailing inset.
    /// The drawn edge of a letter sits up to a point inside its frame, so a text takes a wider tolerance.
    @MainActor
    func expectPageEdges(
        _ frame: CGRect, in app: XCUIApplication, side: PillEdge = .right, trailing: Bool = false,
        _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThan(frame.width, 0, "No \(name)", file: file, line: line)
        let (left, right) = pageInsets(app, side: side)
        XCTAssertEqual(
            frame.minX - app.frame.minX, left, accuracy: trailing ? 1 : 2, "\(name): left inset, frame \(frame)",
            file: file, line: line)
        if trailing {
            XCTAssertEqual(
                app.frame.maxX - frame.maxX, right, accuracy: 1, "\(name): right inset, frame \(frame)",
                file: file, line: line)
        }
    }

    /// The most room that a text line leaves between its line box and its ink on one side: half of the line
    /// box less the cap height. Ascenders and descenders only make the room smaller.
    func bearing(_ style: TypeStyle?) -> CGFloat {
        guard let style else { return 0 }
        return style.size * max(style.lineHeight - Self.capHeight, 0) / 2
    }

    /// The cap height of the faces, in em. It is a little lower than the faces measure, so the bearing is an upper
    /// limit.
    static let capHeight: CGFloat = 0.66

    /// The round play button of a movement row ends on the trailing page edge, as the specimen `.round` does.
    @MainActor
    func expectMovementPlayEdge(
        _ app: XCUIApplication, side: PillEdge = .right, file: StaticString = #filePath, line: UInt = #line
    ) {
        // The identifier of the movement row covers the identifiers inside it, so the label finds the button.
        let button = app.buttons["Play from here"].firstMatch
        XCTAssertTrue(reveal(button, in: app).exists, "No movement play button", file: file, line: line)
        guard let circle = ink(in: button.frame, of: app, side: side) else {
            return XCTFail("The movement play button draws nothing", file: file, line: line)
        }
        let right = pageInsets(app, side: side).right
        XCTAssertEqual(
            app.frame.maxX - circle.maxX, right, accuracy: 1, "Movement play: right inset, circle \(circle)",
            file: file, line: line)
        XCTAssertEqual(
            circle.width, Layout.roundButton, accuracy: 1, "Movement play: circle \(circle)", file: file, line: line)
    }

    /// The vertical gap from the foot of one drawn frame to the top of the next, against a gap of Layout.swift.
    /// The gap of the specimen runs between line boxes; ink sits inside them. So a text side of the gap may add its
    /// bearing, and a shape side adds nothing.
    @MainActor
    func expectGap(
        from upper: CGRect, to lower: CGRect, _ gap: CGFloat, _ name: String, upperText: TypeStyle? = nil,
        lowerText: TypeStyle? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(upper.isEmpty || lower.isEmpty, "\(name): an element is missing", file: file, line: line)
        let measured = lower.minY - upper.maxY
        let most = gap + bearing(upperText) + bearing(lowerText)
        XCTAssertGreaterThanOrEqual(
            measured, gap - 1.5, "\(name): gap \(measured) below \(gap), \(upper) to \(lower)", file: file, line: line)
        XCTAssertLessThanOrEqual(
            measured, most + 1.5, "\(name): gap \(measured) above \(most), \(upper) to \(lower)", file: file,
            line: line)
    }

    /// The height of a text in whole line pitches of its style, as the CSS line-height gives them.
    @MainActor
    func expectLinePitch(
        _ height: CGFloat, _ style: TypeStyle, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let pitch = style.size * style.lineHeight
        let lines = max((height / pitch).rounded(), 1)
        XCTAssertEqual(
            height, lines * pitch, accuracy: 1.5, "\(name): height \(height), not \(lines) lines of \(pitch)",
            file: file, line: line)
    }

    /// The work page against the specimen: title, meta line, Play, then the Recordings heading.
    @MainActor
    func checkWorkPage(_ app: XCUIApplication) {
        // The work title is the favourite button, which hides its text from static-text queries.
        let titleElement = app.buttons["favourite-work"]
        let composerElement = app.buttons["work-composer"]
        let playElement = app.buttons["play-work"]
        let headingElement = app.descendants(matching: .any)["section-heading"].firstMatch
        for element in [titleElement, composerElement, playElement, headingElement] {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "No \(element)")
        }
        let title = drawn(titleElement, in: app)
        let composer = drawn(composerElement, in: app)
        let play = drawn(playElement, in: app)
        let heading = drawn(headingElement, in: app)
        // The title cell holds the row insets of the page heading around the text.
        let titleCell = titleElement.frame
        let titleBox =
            titleCell.width >= app.frame.width - 1
            ? titleCell.height - Layout.headTop - Layout.metaTop : titleCell.height
        expectLinePitch(titleBox, Layout.pageTitle, "Work title")
        expectPageEdges(title, in: app, "Work title")
        expectPageEdges(composer, in: app, "Composer line")
        expectPageEdges(play, in: app, trailing: true, "Play")
        expectPageEdges(heading, in: app, "Recordings heading")
        expectGap(
            from: title, to: composer, Layout.metaTop, "Title to meta", upperText: Layout.pageTitle,
            lowerText: Layout.metaLine)
        // The composer and the date share the meta line; the lower of the two ends it.
        let date = app.buttons["composed"].firstMatch
        let meta = date.exists && date.frame.maxY > composer.maxY ? drawn(date, in: app) : composer
        expectGap(
            from: meta, to: play, Layout.headBottom + Layout.buttonRowTop, "Meta to Play", upperText: Layout.metaLine)
        expectGap(from: play, to: heading, Layout.sectionTop, "Play to Recordings", lowerText: Layout.sectionHeading)
    }

    /// The hairline between two recording rows. It fails when the page has no pair, so the check cannot pass unrun.
    @MainActor
    func checkRecordingHairline(_ app: XCUIApplication) {
        let recordings = app.buttons.matching(identifier: "recording")
        XCTAssertTrue(recordings.element(boundBy: 1).waitForExistence(timeout: 10), "The work has no two recordings")
        expectHairline(
            between: recordings.element(boundBy: 0), and: recordings.element(boundBy: 1), in: app,
            "Recording hairline")
    }

    /// The composer page without a picture against the specimen: Chronology, the tabs, the chips, the Works heading.
    @MainActor
    func checkComposerPage(_ app: XCUIApplication) {
        let chronologyElement = app.buttons["composer-chronology"]
        let tabsElement = app.descendants(matching: .any)["composer-tabs"].firstMatch
        let chipElement = app.buttons.matching(identifier: "genre-chip").firstMatch
        let headingElement = app.descendants(matching: .any)["section-heading"].firstMatch
        for element in [chronologyElement, tabsElement, chipElement, headingElement] {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "No \(element)")
        }
        let chronology = drawn(chronologyElement, in: app)
        let tabs = drawn(tabsElement, in: app)
        let chip = drawn(chipElement, in: app)
        let heading = drawn(headingElement, in: app)
        expectPageEdges(chronology, in: app, trailing: true, "Chronology")
        expectPageEdges(tabs, in: app, trailing: true, "Works and About")
        expectPageEdges(chip, in: app, "First chip")
        expectPageEdges(heading, in: app, "Works heading")
        expectGap(from: chronology, to: tabs, Layout.segmentedTop, "Chronology to tabs")
        expectGap(from: tabs, to: chip, Layout.chipsTop, "Tabs to chips")
        expectGap(from: chip, to: heading, Layout.sectionTop, "Chips to Works", lowerText: Layout.sectionHeading)
    }

    /// A performer without a picture: the name sits where a page title sits, and the tabs follow at the specimen
    /// gap, with no room for a Chronology button (sz-rs30.1.105.77).
    @MainActor
    func checkPerformerHead(_ app: XCUIApplication, titleBottom: CGFloat) {
        let nameElement = app.descendants(matching: .any)["performer-name"].firstMatch
        let tabsElement = app.descendants(matching: .any)["performer-tabs"].firstMatch
        for element in [nameElement, tabsElement] {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "No \(element)")
        }
        XCTAssertFalse(app.descendants(matching: .any)["performer-picture"].exists)
        // The name element reaches up under the back button, so the ink is read on the title line only.
        let element = nameElement.frame
        let line = Layout.pageTitle.size * Layout.pageTitle.lineHeight
        let band = CGRect(x: element.minX, y: element.maxY - line, width: element.width, height: line)
        let name = ink(in: band, of: app, side: .right) ?? element
        let tabs = drawn(tabsElement, in: app)
        // The name sits where the title of every other page sits (sz-3hcq.13). The name element reaches up under
        // the bar, so only the bottoms of the two lines compare.
        XCTAssertEqual(name.maxY, titleBottom, accuracy: 2, "Performer name is not at the page title: \(name)")
        expectPageEdges(name, in: app, "Performer name")
        expectPageEdges(tabs, in: app, trailing: true, "Albums and About")
        expectGap(
            from: name, to: tabs, Layout.personHeadBottom + Layout.segmentedTop, "Name to tabs",
            upperText: Layout.pageTitle)
        // The album grid is a .section on the plain page list, so the section gap follows the tabs.
        // The placeholder fill is close to the page ground, so the element frame stands in for the ink.
        // Different title heights must not move the covers from the top of their grid row.
        let covers = app.buttons.matching(identifier: "performer-album").allElementsBoundByIndex.map(\.frame)
            .sorted { $0.minY < $1.minY }.prefix(2).sorted { $0.minX < $1.minX }
        guard covers.count == 2 else { return XCTFail("The performer needs two album covers") }
        let left = covers[0]
        let right = covers[1]
        XCTAssertGreaterThan(abs(left.height - right.height), 2, "The album titles need different line counts")
        XCTAssertEqual(left.minY, right.minY, accuracy: 2, "The album covers are not top-aligned")
        expectPageEdges(left, in: app, "First album")
        expectGap(from: tabs, to: left, Layout.sectionTop, "Tabs to albums")
        checkTabs(app, "performer-tabs", from: "Albums", to: "About")
        tabsElement.buttons["Albums"].tap()
    }

    /// The flat tabs of a person page: a tap selects the other tab and shows its content at once (sz-rs30.1.105.74).
    @MainActor
    func checkTabs(_ app: XCUIApplication, _ identifier: String, from first: String, to second: String) {
        let tabs = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(reveal(tabs, in: app).waitForExistence(timeout: 10), "No \(identifier)")
        XCTAssertTrue(tabs.buttons[first].isSelected, "\(first) is not selected")
        tabs.buttons[second].tap()
        let tags = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Name in your tags'"))
        XCTAssertTrue(reveal(tags.firstMatch, in: app).waitForExistence(timeout: 5), "\(second) shows no tags")
        // The About tab of both person pages is one shared plain list: its rows keep the page edges.
        expectPageEdges(drawn(tags.firstMatch, in: app), in: app, "\(identifier) tags row")
        XCTAssertTrue(tabs.buttons[second].isSelected, "\(second) is not selected")
        XCTAssertFalse(tabs.buttons[first].isSelected, "\(first) stays selected")
    }

    /// Opens a recording, leaves it paused in the player and goes back to the list of composers.
    @MainActor
    func pausedPlayerInLibrary(_ app: XCUIApplication) -> XCUIElement {
        openRecording(app)
        playPaused(app)
        back(app, times: 3)
        let miniPlayer = app.descendants(matching: .any)["mini-player"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 10))
        return miniPlayer
    }

    /// Scrolls down until the element is on screen and clear of the tab row and the mini player.
    /// Lists create rows only when they come near the screen.
    /// A short drag has no momentum, so it cannot move the element past the screen.
    @MainActor
    @discardableResult
    func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let row = app.descendants(matching: .any)["tab-row"].firstMatch
        let bar = app.sliders["position"].firstMatch
        for _ in 0..<14 {
            if element.exists {
                // A tap on a row under the tab row would open a place or the player.
                let floor = row.exists ? row.frame.minY : app.frame.maxY
                if element.frame.maxY <= floor, element.isHittable { return element }
            }
            // A drag that starts on the playback bar scrubs and does not scroll, so it starts below the bar.
            let start = CGPoint(x: app.frame.midX, y: app.frame.minY + app.frame.height * 0.6)
            let onBar = bar.exists && bar.frame.insetBy(dx: 0, dy: -Measure.hitTarget).contains(start)
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: onBar ? 0.78 : 0.6))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: onBar ? 0.53 : 0.35))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        return element
    }

    /// The first keyboard of a new simulator shows the system tip on sliding to type over the lower half of the
    /// screen. A screenshot taken while it shows hides the controls below the field.
    @MainActor
    func dismissKeyboardTip(_ app: XCUIApplication) {
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 3) { tip.tap() }
    }

    /// The seconds of a shown time such as 1:48 or 1:02:03.
    static func seconds(_ time: String) -> Double {
        time.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    /// Reads the condition until it holds or the time is over. The time ends only between two complete reads.
    /// An XCTWaiter that times out interrupts the read in progress, and an interrupted frame read fails the test
    /// with an invalid activation point instead of a false value.
    @MainActor
    func eventually(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    @MainActor
    func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIElement {
    /// Waits until the element carries the selected trait.
    func waitForSelection(timeout: TimeInterval) -> Bool {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: self)
        return XCTWaiter.wait(for: [selected], timeout: timeout) == .completed
    }
}
