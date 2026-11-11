import XCTest

// Each area is one class, and each test starts from a reset app and keeps a few screenshots. So a UI change can
// walk only its own area, and one failed test does not stop the screenshots of the others. scripts/screens.sh
// takes the class names without "Screens" in KLASSIK_UI. scripts/screen_report.py reads the names of the
// screenshots from the snap calls in this file.

/// The four places, the stack of each place and the back arrow between them.
final class PlacesScreens: ScreensTestCase {
    @MainActor
    func testLibrary() throws {
        let app = try launchAndConnect(snapConnect: true, openComposers: false)
        XCTAssertTrue(app.buttons["library-favourites"].exists)
        snap(app, "02-library")
        app.buttons["library-composers"].tap()
        XCTAssertTrue(composer(app, "Felix Mendelssohn").waitForExistence(timeout: 30))
        snap(app, "02d-composers")
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
    func testFourPlaces() throws {
        let app = try launchAndConnect(openComposers: false)
        for name in ["Library", "Chronology", "Search", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[name].exists, "No tab \(name)")
        }
        // Library is the root of the app and has no back arrow.
        XCTAssertFalse(app.buttons["place-back"].exists)

        openPlace(app, "Chronology")
        expectBackArrow(app, to: "Library")
        snap(app, "02f-chronology")

        openPlace(app, "Search")
        expectBackArrow(app, to: "Chronology")
        snap(app, "02g-search")

        openPlace(app, "Settings")
        expectBackArrow(app, to: "Search")
        snap(app, "02h-settings")

        // Back returns to the place the listener came from, and that place still has its own back arrow.
        app.buttons["place-back"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 10))
        expectBackArrow(app, to: "Chronology")
    }

    @MainActor
    func testPlaceOpenedFromAPageGoesBackToThatPage() throws {
        let app = try launchAndConnect()
        composer(app, "Frédéric Chopin").tap()
        XCTAssertTrue(app.navigationBars["Frédéric Chopin"].waitForExistence(timeout: 10))
        openPlace(app, "Settings")
        expectBackArrow(app, to: "Chopin")
        snap(app, "02i-back-arrow-to-page")
        app.buttons["place-back"].tap()
        XCTAssertTrue(app.navigationBars["Frédéric Chopin"].waitForExistence(timeout: 10))
    }

    /// A swipe from the left edge of a root with an arrow does what the arrow does.
    @MainActor
    func testEdgeSwipeGoesBack() throws {
        let app = try launchAndConnect(openComposers: false)
        openPlace(app, "Chronology")
        expectBackArrow(app, to: "Library")
        swipeFromLeftEdge(app)
        XCTAssertTrue(app.buttons["place-back"].waitForNonExistence(timeout: 10), "The swipe did not go back")
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected)
        XCTAssertTrue(app.buttons["library-composers"].exists)
    }

    /// The previous place shows its page as the listener left it, after the arrow and after the swipe.
    @MainActor
    func testBackToThePageAsLeft() throws {
        let app = try launchAndConnect()
        composer(app, "Frédéric Chopin").tap()
        XCTAssertTrue(app.navigationBars["Frédéric Chopin"].waitForExistence(timeout: 10))
        openPlace(app, "Settings")
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

    @MainActor
    func testMusicBrainz() throws {
        let app = try launchAndConnect()
        openPlace(app, "Settings")
        XCTAssertTrue(app.buttons["musicbrainz"].waitForExistence(timeout: 30))
        app.buttons["musicbrainz"].tap()
        let toConfirm = app.buttons["to-confirm"]
        XCTAssertTrue(toConfirm.waitForExistence(timeout: 10))
        // The lookup may still run right after the connect.
        let counted = expectation(for: NSPredicate(format: "label CONTAINS '1'"), evaluatedWith: toConfirm)
        XCTAssertEqual(XCTWaiter.wait(for: [counted], timeout: 30), .completed, toConfirm.label)
        snap(app, "02c-musicbrainz")
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

        recording.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        app.buttons["play-recording"].tap()
        // The fixture movements last seconds, so the walk pauses before it looks at the page.
        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 30), "No Pause button")
        pause.tap()
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
    }

    /// Next has nowhere to go on the last movement of the last item. The fixture movements last about three
    /// seconds, so the walk does as little as it can between the second Next and the check.
    @MainActor
    func testNextEndsAtTheLastMovement() throws {
        let app = try launchAndConnect()
        openRecording(app)
        app.buttons["play-recording"].tap()
        let next = app.buttons["Next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 30), "No Next button")
        next.tap()
        next.tap()
        XCTAssertFalse(next.isEnabled, "Next stays on at the last movement")
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

        openPlace(app, "Settings")
        reveal(app.buttons["local-storage"], in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["download"].firstMatch.waitForExistence(timeout: 10))
        snap(app, "08a-local-storage")
    }

    @MainActor
    func testPerformers() throws {
        let app = try launchAndConnect()
        _ = pausedPlayerInLibrary(app)
        snap(app, "06-library-playing")

        openPlace(app, "Search")
        app.buttons["performers"].tap()
        let performer = app.buttons.matching(identifier: "performer").firstMatch
        XCTAssertTrue(performer.waitForExistence(timeout: 10))
        snap(app, "06a-performers")
        let performed = app.buttons.matching(identifier: "recording").firstMatch
        // A tap while the list still settles does not open the row, so the walk taps again.
        for _ in 0..<3 where !performed.exists {
            if performer.isHittable { performer.tap() }
            _ = performed.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(performed.exists)
        snap(app, "06b-performer")
        performed.tap()
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

        miniPlayer.tap()
        XCTAssertTrue(app.descendants(matching: .any)["playback-progress"].waitForExistence(timeout: 10))
        snap(app, "07-now-playing")
        let queued = app.buttons.matching(identifier: "up-next").firstMatch
        for _ in 0..<3 where !(queued.exists && queued.isHittable) { app.swipeUp() }
        XCTAssertTrue(queued.label.contains("Symphony No. 5"))
        snap(app, "08-up-next")
    }

    /// The server keeps the reference recording, so this test changes what the later ones see.
    @MainActor
    func testReference() throws {
        let app = try launchAndConnect()
        openRecording(app)
        app.buttons["reference"].tap()
        back(app)
        let reference = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Play Reference Recording'"))
            .firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        snap(app, "05b-work-reference")
    }
}

/// The settings pages and the diagnostic pages.
final class SettingsScreens: ScreensTestCase {
    @MainActor
    func testSettings() throws {
        let app = try launchAndConnect()
        // The mini player must leave the last rows free, so something must be playing.
        _ = pausedPlayerInLibrary(app)
        openPlace(app, "Settings")
        XCTAssertTrue(reveal(app.buttons["diagnostics"], in: app).isHittable)
        snap(app, "08c-settings")

        reveal(app.buttons["swipe-actions"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Swipe Actions"].waitForExistence(timeout: 10))
        snap(app, "08b-swipe-actions")
    }

    @MainActor
    func testFilter() throws {
        let app = try launchAndConnect()
        openPlace(app, "Settings")
        reveal(app.buttons["classical-filter"], in: app).tap()
        XCTAssertTrue(app.textFields.matching(identifier: "condition-text").firstMatch.waitForExistence(timeout: 10))
        snap(app, "09-filter")
    }

    @MainActor
    func testClassicalAlbums() throws {
        let app = try launchAndConnect()
        openPlace(app, "Settings")
        reveal(app.buttons["classical-albums"], in: app).tap()
        let concerto = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Mendelssohn: Violin Concerto'")).firstMatch
        XCTAssertTrue(concerto.waitForExistence(timeout: 10))
        let encores = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Romantic Encores'")).firstMatch
        XCTAssertTrue(encores.waitForExistence(timeout: 10))
        let performers = "Sine Wave Chamber Orchestra • Carl Fixture • Daniel Keys"
        XCTAssertTrue(encores.label.contains(performers), encores.label)
        snap(app, "10-classical-albums")
        // A tap opens the album. It does not start to play.
        concerto.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        back(app)
        XCTAssertTrue(encores.waitForExistence(timeout: 10))
        XCTAssertTrue(encores.label.contains(performers), encores.label)
    }

    @MainActor
    func testDiagnostics() throws {
        let app = try launchAndConnect()
        // Diagnostics checks that the mini player leaves the last row free, so something must be playing.
        let bar = pausedPlayerInLibrary(app)
        openPlace(app, "Settings")
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
        openPlace(app, "Settings")
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

    @MainActor
    func launchAndConnect(
        snapConnect: Bool = false, openComposers: Bool = true, arguments: [String] = []
    ) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["KLASSIK_SERVER_URL"] else { throw XCTSkip("No fixture server configured") }

        let app = XCUIApplication()
        app.launchArguments = ["-resetServer"] + arguments
        app.launchEnvironment = [
            "KLASSIK_SERVER_URL": server,
            "KLASSIK_USERNAME": env["KLASSIK_USERNAME"] ?? "",
            "KLASSIK_PASSWORD": env["KLASSIK_PASSWORD"] ?? "",
            "KLASSIK_MUSICBRAINZ_STUB": Self.musicBrainz,
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

    /// Taps a place in the tab bar.
    @MainActor
    func openPlace(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "No tab \(name)")
        tab.tap()
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
        app.buttons["play-recording"].tap()
        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 30))
        pause.tap()
        XCTAssertTrue(app.buttons["Resume"].firstMatch.waitForExistence(timeout: 10))
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

    /// Scrolls down until the element is on screen and clear of the mini player.
    /// Lists create rows only when they come near the screen.
    /// A short drag has no momentum, so it cannot move the element past the screen.
    @MainActor
    @discardableResult
    func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let bar = app.descendants(matching: .any)["mini-player"].firstMatch
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        for _ in 0..<14 {
            if element.exists {
                // A tap on a row below the mini player opens the player.
                let floor = bar.exists ? bar.frame.minY : app.frame.maxY
                if element.frame.maxY <= floor, element.isHittable { return element }
            }
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        return element
    }

    @MainActor
    func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
