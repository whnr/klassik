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
        // ADR 0030: the title sits right under the back arrow, as on the specimen.
        let heading = app.staticTexts["page-heading"]
        XCTAssertTrue(heading.exists)
        XCTAssertLessThan(heading.frame.minY, 130)
        expectPageEdges(drawn(heading, in: app), in: app, "Composers title")
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

        // Library reached from another place shows the arrow too (ADR 0038).
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
}

/// The pages that the lookup fills.
final class BrowseScreens: ScreensTestCase {
    @MainActor
    func testTimeline() throws {
        let app = try launchAndConnect()
        openPlace(app, "Chronology")
        let dated = app.buttons.matching(identifier: "timeline-work")
            .matching(NSPredicate(format: "label CONTAINS 'Symphony No. 5'")).firstMatch
        XCTAssertTrue(dated.waitForExistence(timeout: 30))
        XCTAssertTrue(dated.label.contains("1804"))
        snap(app, "02b-timeline")
    }

    /// Mendelssohn has a picture in the fixture answers: it shows under the name, and a tap shows it whole with
    /// its credit (ADR 0017). Chopin has none, so his page shows the name on the plain ground.
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

        picture.tap()
        let whole = app.descendants(matching: .any)["whole-picture"]
        XCTAssertTrue(whole.waitForExistence(timeout: 10))
        let credit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Public domain'")).firstMatch
        XCTAssertTrue(credit.exists, "The whole picture shows no credit")
        snap(app, "03c-whole-picture")
        app.buttons["Close"].tap()
        XCTAssertTrue(picture.waitForExistence(timeout: 10))
    }

    @MainActor
    func testMusicBrainz() throws {
        let app = try launchAndConnect()
        openSettings(app)
        XCTAssertTrue(app.buttons["musicbrainz"].waitForExistence(timeout: 30))
        app.buttons["musicbrainz"].tap()
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
        openSettings(app)
        XCTAssertTrue(app.buttons["musicbrainz"].waitForExistence(timeout: 30))
        app.buttons["musicbrainz"].tap()
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
        set.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "work").firstMatch.waitForExistence(timeout: 10))
        snap(app, "02a-sets")
    }

    /// Chopin has no picture: his name sits under the back arrow. His works differ in genre, so chips show, and
    /// two chips join with "or" (ADR 0017).
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

    /// Two good matches in another language: the listener picks one once.
    @MainActor
    func testConfirmMatch() throws {
        let app = try launchAndConnect()
        reveal(composer(app, "Wolfgang"), in: app).tap()
        let work = app.buttons.matching(identifier: "work").matching(NSPredicate(format: "label CONTAINS 'K. 467'"))
            .firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "identifier == 'composed' AND label CONTAINS 'Confirm'"))
            .firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), app.buttons["composed"].label)
        confirm.tap()
        let candidate = app.buttons.matching(identifier: "candidate").firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        snap(app, "04b-confirm-match")
        candidate.tap()
        let linked = app.descendants(matching: .any)["musicbrainz-work"]
        XCTAssertTrue(linked.waitForExistence(timeout: 10))
        let year = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1785'")).firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 10))
        snap(app, "04c-sources")
    }
}

/// A recording, the player, the queue and the downloads.
final class PlaybackScreens: ScreensTestCase {
    @MainActor
    func testOverlayOpensAndSlidesDown() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        let tags = reveal(app.buttons["raw-tags"], in: app)
        let before = tags.frame
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
        XCTAssertTrue(tags.waitForExistence(timeout: 10))
        XCTAssertEqual(tags.frame.minY, before.minY, accuracy: 2, "The underlying page scrolled")
        snap(app, "16b-overlay-dismissed")
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

    /// Stop closes the player and leaves no end message (ADR 0043). On the walk simulator a natural end of the queue
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
        // The page below the overlay builds the same row, so the query stays inside the overlay.
        let overlay = app.descendants(matching: .any)["player-overlay"].firstMatch
        reveal(overlay.buttons["raw-tags"], in: app).tap()
        expectPlayerClosed(app)
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 10))
        back(app)
        // The page returns at its top; a list builds the row below the fold only once it scrolls near.
        XCTAssertTrue(reveal(app.buttons["raw-tags"], in: app).exists)
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
        let work = app.buttons.matching(identifier: "timeline-work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 30))
        work.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "recording").firstMatch.waitForExistence(timeout: 10))
        openPlace(app, "Search")
        app.buttons["performers"].tap()
        XCTAssertTrue(app.navigationBars["Performers"].waitForExistence(timeout: 10))
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

    @MainActor
    private func openPlayer(_ app: XCUIApplication) {
        app.buttons["mini-player-cover"].tap()
        let handle = app.buttons["player-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        // The overlay slides in below the tab row, so the handle becomes hittable only when the slide ends.
        XCTAssertTrue(eventually(timeout: 5) { handle.isHittable }, "The player is behind the selected place")
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
    private func expectPlayerClosed(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["player-handle"].waitForNonExistence(timeout: 10))
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
        let composed = app.buttons.matching(NSPredicate(format: "identifier == 'composed' AND label CONTAINS '1844'"))
        XCTAssertTrue(composed.firstMatch.waitForExistence(timeout: 30), app.buttons["composed"].label)
        snap(app, "04-work")
        checkWorkPage(app)

        recording.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        playPaused(app)
        snap(app, "05-recording")

        // A paused player moves to the dragged position and stays paused.
        let position = app.sliders["position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        position.adjust(toNormalizedSliderPosition: 0)
        let start = position.value as? String ?? ""
        position.adjust(toNormalizedSliderPosition: 0.9)
        let moved = expectation(for: NSPredicate(format: "value != %@", start), evaluatedWith: position)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed, start)
        XCTAssertTrue(app.buttons["Resume"].firstMatch.exists)
        snap(app, "05c-seek")

        // The movements are below the player, and a list creates a row only near the screen.
        // The mark is an image in the row. Not every system puts its label into the label of the row.
        let playing = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Now playing'"))
            .firstMatch
        XCTAssertTrue(reveal(playing, in: app).exists, "No movement shows the playing mark")
        expectMovementPlayEdge(app)
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
        let first = app.buttons.matching(identifier: "recording").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let before = first.frame
        play.tap()
        // While a recording of the work plays, the pill pauses it (sz-swi9.4).
        XCTAssertTrue(eventually(timeout: 15) { play.label == "Pause" }, "The pill reads \(play.label) while it plays")
        snap(app, "04c-work-playing")
        play.tap()
        XCTAssertTrue(eventually(timeout: 10) { play.label == "Resume" }, "The pill reads \(play.label) after a pause")
        XCTAssertEqual(app.buttons["mini-player-pause"].label, "Resume", "The pill did not pause the playback")
        // The playing row tints in place: the row keeps its frame.
        XCTAssertEqual(first.frame, before, "The playing row moved or changed its size")
        snap(app, "04d-work-playing")
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
        let workCover = app.descendants(matching: .any)["work-cover"].firstMatch
        XCTAssertTrue(workCover.exists, "The work page shows no reference cover")
        let workAlbum = app.buttons["play-work-album"]
        XCTAssertTrue(workAlbum.exists, "The work page offers no Play Album")
        let workPlay = app.buttons["play-work"]
        XCTAssertEqual(workPlay.frame.midY, workAlbum.frame.midY, accuracy: 1)
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
        openSettings(app)
        reveal(app.buttons["classical-albums"], in: app).tap()
        let encores = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Romantic Encores'")).firstMatch
        XCTAssertTrue(reveal(encores, in: app).isHittable)
        encores.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        startPlaying(app)
        pause(app)
        snap(app, "05e-play-album")
    }

    /// Next has nowhere to go on the last movement of the last item. Next always plays, and a queue that ends
    /// removes the Next button. So the walk pauses as soon as Next turns off, while the last movement plays.
    @MainActor
    func testNextEndsAtTheLastMovement() throws {
        let app = try launchAndConnect()
        openRecording(app)
        startPlaying(app)
        let next = app.buttons["Next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 30), "No Next button")
        next.tap()
        next.tap()
        XCTAssertTrue(eventually(timeout: 10) { !next.isEnabled }, "Next stays on at the last movement")
        pause(app)
        XCTAssertFalse(next.isEnabled, "Next turned on again after the pause")
        snap(app, "05d-next-ends")
    }

    @MainActor
    func testDownload() throws {
        let app = try launchAndConnect()
        openRecording(app)
        playPaused(app)
        reveal(app.buttons["download"], in: app).tap()
        XCTAssertTrue(app.buttons["remove-download"].waitForExistence(timeout: 30), "The download did not finish")
        snap(app, "05a-downloaded")
        back(app, times: 3)

        openSettings(app)
        reveal(app.buttons["local-storage"], in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["download"].firstMatch.waitForExistence(timeout: 10))
        snap(app, "08a-local-storage")
    }

    @MainActor
    func testPerformers() throws {
        let app = try launchAndConnect()
        openPlace(app, "Search")
        app.buttons["performers"].tap()
        let performer = app.buttons.matching(identifier: "performer").firstMatch
        XCTAssertTrue(performer.waitForExistence(timeout: 10))
        snap(app, "06a-performers")
        let cover = app.buttons.matching(identifier: "performer-album").firstMatch
        // A tap while the list still settles does not open the row, so the walk taps again.
        for _ in 0..<3 where !cover.exists {
            if performer.isHittable { performer.tap() }
            _ = cover.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(cover.exists)
        snap(app, "06b-performer")
        checkPerformerHead(app)
        cover.tap()
        reveal(app.buttons["raw-tags"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 10))
        snap(app, "06c-tags")
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
        let queued = app.buttons.matching(identifier: "up-next").firstMatch
        for _ in 0..<3 where !(queued.exists && queued.isHittable) { app.swipeUp() }
        XCTAssertTrue(queued.label.contains("Symphony No. 5"))
        snap(app, "08-up-next")
        reveal(app.buttons["Next Work"].firstMatch, in: app).tap()
        let title = app.buttons.matching(identifier: "favourite-recording")
            .matching(NSPredicate(format: "label CONTAINS 'Symphony No. 5'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        pause(app)
        XCTAssertTrue(app.sliders["position"].waitForExistence(timeout: 10))
        XCTAssertTrue(miniPlayer.buttons["mini-player-cover"].exists)
        snap(app, "08d-next-player")
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
        favourite.tap()
        let moved = expectation(for: NSPredicate(format: "label CONTAINS 'Anna Probe'"), evaluatedWith: rows.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed)
        snap(app, "05b-work-reference")

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
    }

}

/// The timeline on the screen edge and the mini player in the tab row (ADR 0014, 0028, 0035).
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
        XCTAssertEqual(
            frame.height, tab(app, "Search").frame.height + 8, accuracy: 1,
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
        slidePlayerDown(app)
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
    func testSettings() throws {
        let app = try launchAndConnect()
        // The mini player must leave the last rows free, so something must be playing.
        _ = pausedPlayerInLibrary(app)
        openSettings(app)
        XCTAssertTrue(reveal(app.buttons["diagnostics"], in: app).isHittable)
        snap(app, "08c-settings")

        reveal(app.buttons["swipe-actions"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Swipe Actions"].waitForExistence(timeout: 10))
        snap(app, "08b-swipe-actions")
    }

    @MainActor
    func testFilter() throws {
        let app = try launchAndConnect()
        _ = pausedPlayerInLibrary(app)
        openSettings(app)
        reveal(app.buttons["classical-filter"], in: app).tap()
        let field = app.textFields.matching(identifier: "condition-text").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let bar = app.tabBars["tab-row"]
        let barFrame = bar.frame
        let lineFrame = timeline(app).frame
        let pill = app.descendants(matching: .any)["mini-player"].firstMatch
        let controlsFrame = pillFrame(pill)
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
        snap(app, "09b-keyboard-closed")
    }

    @MainActor
    func testClassicalAlbums() throws {
        let app = try launchAndConnect()
        openSettings(app)
        reveal(app.buttons["classical-albums"], in: app).tap()
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
        openSettings(app)
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
        XCTAssertEqual(showTaps.value as? String, "1")
        snap(app, "12a-show-taps")
    }

    @MainActor
    func testGapless() throws {
        let app = try launchAndConnect()
        openSettings(app)
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
        let pairs: [[String]] = [
            ["haswbstatement:P434=\(mendelssohn)", #"{"query":{"search":[{"title":"Q46096"}]}}"#],
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
        swipeFromLeftEdge(app)
        XCTAssertTrue(app.navigationBars["Felix Mendelssohn"].waitForExistence(timeout: 10))
        swipeFromLeftEdge(app)
        XCTAssertTrue(app.navigationBars["Composers"].waitForExistence(timeout: 10))
        XCTAssertEqual(bar.value as? String, before, "Back changed the playback position")
    }

    /// The key of the timeline edge in the user defaults. A launch argument sets it for one run.
    let timelineSideKey = "timeline.side"

    /// A place in the tab bar, which Klassik draws by hand beside the mini player.
    @MainActor
    func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons["tab-\(name.lowercased())"]
    }

    /// Settings belongs to the Library stack, behind its toolbar cog.
    @MainActor
    func openSettings(_ app: XCUIApplication) {
        openPlace(app, "Library")
        for _ in 0..<10 where !app.buttons["library-settings"].exists { back(app) }
        let cog = app.buttons["library-settings"]
        XCTAssertTrue(cog.waitForExistence(timeout: 10))
        cog.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }

    /// Taps a place in the tab bar.
    @MainActor
    func openPlace(_ app: XCUIApplication, _ name: String) {
        let tab = tab(app, name)
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "No tab \(name)")
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

        /// The pixel columns that content may use: the columns of the timeline bar are not content.
        func contentColumns(side: PillEdge) -> Range<Int> {
            let skip = Int(((Measure.timeline + Measure.timelineCap) * scale).rounded(.up))
            return side == .right ? 0..<(width - skip) : skip..<width
        }

        /// A column of page ground on the side away from the timeline, inside every page edge.
        func groundColumn(side: PillEdge) -> Int {
            side == .right ? Int(scale) : width - 1 - Int(scale)
        }

        func pixels(_ range: ClosedRange<CGFloat>) -> Range<Int> {
            Int((range.lowerBound * scale).rounded())..<Int((range.upperBound * scale).rounded())
        }
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

    /// The distance of a drawn frame from the display edges against the page edges of Layout.swift. The timeline
    /// side takes the wider inset. A text checks only its leading edge: its frame can run to the trailing inset.
    /// The drawn edge of a letter sits up to a point inside its frame, so a text takes a wider tolerance.
    @MainActor
    func expectPageEdges(
        _ frame: CGRect, in app: XCUIApplication, side: PillEdge = .right, trailing: Bool = false,
        _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThan(frame.width, 0, "No \(name)", file: file, line: line)
        let left = side == .left ? Layout.timelineEdge : Layout.edge
        let right = side == .left ? Layout.edge : Layout.timelineEdge
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
        let right = side == .left ? Layout.edge : Layout.timelineEdge
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

    /// The work page against work.html: title, meta line, Play, then the Recordings heading.
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
        let recordings = app.buttons.matching(identifier: "recording")
        if recordings.count > 1 {
            expectHairline(
                between: recordings.element(boundBy: 0), and: recordings.element(boundBy: 1), in: app,
                "Recording hairline")
        }
    }

    /// The composer page without a picture against person.html: Chronology, the tabs, the chips, the Works heading.
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
    func checkPerformerHead(_ app: XCUIApplication) {
        let nameElement = app.descendants(matching: .any)["performer-name"].firstMatch
        let tabsElement = app.descendants(matching: .any)["performer-tabs"].firstMatch
        for element in [nameElement, tabsElement] {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "No \(element)")
        }
        XCTAssertFalse(app.descendants(matching: .any)["performer-picture"].exists)
        let name = drawn(nameElement, in: app)
        let tabs = drawn(tabsElement, in: app)
        // As the Composers title in testLibrary: right under the back arrow.
        XCTAssertLessThan(name.minY, 130, "Performer name sits too low: \(name)")
        expectPageEdges(name, in: app, "Performer name")
        expectPageEdges(tabs, in: app, trailing: true, "Albums and About")
        expectGap(
            from: name, to: tabs, Layout.personHeadBottom + Layout.segmentedTop, "Name to tabs",
            upperText: Layout.pageTitle)
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
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        for _ in 0..<14 {
            if element.exists {
                // A tap on a row under the tab row would open a place or the player.
                let floor = row.exists ? row.frame.minY : app.frame.maxY
                if element.frame.maxY <= floor, element.isHittable { return element }
            }
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        return element
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
