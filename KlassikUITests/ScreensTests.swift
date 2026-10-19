import XCTest

/// Walks the main screens against the fixture server and keeps a screenshot of each.
/// The screens workflow passes the server through TEST_RUNNER_KLASSIK_* variables.
final class ScreensTests: XCTestCase {
    @MainActor
    func testWalkMainScreens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["KLASSIK_SERVER_URL"] else { throw XCTSkip("No fixture server configured") }

        let app = XCUIApplication()
        app.launchArguments = ["-resetServer"]
        app.launchEnvironment = [
            "KLASSIK_SERVER_URL": server,
            "KLASSIK_USERNAME": env["KLASSIK_USERNAME"] ?? "",
            "KLASSIK_PASSWORD": env["KLASSIK_PASSWORD"] ?? "",
            "KLASSIK_MUSICBRAINZ_STUB": Self.musicBrainz,
        ]
        app.launch()

        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        snap(app, "01-connect")
        connect.tap()

        let mendelssohn = app.buttons.matching(identifier: "composer")
            .matching(NSPredicate(format: "label BEGINSWITH 'Felix Mendelssohn'")).firstMatch
        XCTAssertTrue(mendelssohn.waitForExistence(timeout: 30))
        snap(app, "02-home")

        app.buttons["timeline"].tap()
        let dated = app.buttons.matching(identifier: "timeline-work")
            .matching(NSPredicate(format: "label CONTAINS 'Symphony No. 5'")).firstMatch
        XCTAssertTrue(dated.waitForExistence(timeout: 30))
        XCTAssertTrue(dated.label.contains("1804"))
        snap(app, "02b-timeline")
        back(app)

        app.buttons["musicbrainz"].tap()
        let toConfirm = app.buttons["to-confirm"]
        XCTAssertTrue(toConfirm.waitForExistence(timeout: 10))
        XCTAssertTrue(toConfirm.label.contains("1"), toConfirm.label)
        snap(app, "02c-musicbrainz")
        back(app)

        let chopin = app.buttons.matching(identifier: "composer")
            .matching(NSPredicate(format: "label BEGINSWITH 'Frédéric Chopin'")).firstMatch
        chopin.tap()
        let set = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Nocturnes, Op. 9'")).firstMatch
        XCTAssertTrue(set.waitForExistence(timeout: 10))
        set.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "work").firstMatch.waitForExistence(timeout: 10))
        snap(app, "02a-sets")
        back(app)

        // Two good matches in another language: the listener picks one once.
        reveal(
            app.buttons.matching(identifier: "composer").matching(NSPredicate(format: "label BEGINSWITH 'Wolfgang'"))
                .firstMatch, in: app
        ).tap()
        app.buttons.matching(identifier: "work").matching(NSPredicate(format: "label CONTAINS 'K. 467'")).firstMatch
            .tap()
        let confirm = app.buttons["composed"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(confirm.label.contains("Confirm"), confirm.label)
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
        for _ in 0..<3 { back(app) }

        mendelssohn.tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        snap(app, "03-composer")

        work.tap()
        let recording = app.buttons.matching(identifier: "recording").firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["composed"].label.contains("1844"), app.buttons["composed"].label)
        snap(app, "04-work")

        recording.tap()
        app.buttons["play-recording"].tap()
        let playing = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Now playing'")).firstMatch
        XCTAssertTrue(playing.waitForExistence(timeout: 30))
        snap(app, "05-recording")
        // The fixture movements last seconds; paused, the player stays for the next screens.
        app.buttons["Pause"].firstMatch.tap()

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

        reveal(app.buttons["download"], in: app).tap()
        XCTAssertTrue(app.buttons["remove-download"].waitForExistence(timeout: 30))
        snap(app, "05a-downloaded")
        app.buttons["reference"].tap()
        back(app)
        let reference = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Play Reference Recording'"))
            .firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        snap(app, "05b-work-reference")
        for _ in 0..<2 { back(app) }

        let miniPlayer = app.descendants(matching: .any)["mini-player"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 10))
        snap(app, "06-home-playing")

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
        for _ in 0..<4 { back(app) }

        app.buttons.matching(identifier: "composer")
            .matching(NSPredicate(format: "label BEGINSWITH 'Ludwig'")).firstMatch.tap()
        let fifth = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(fifth.waitForExistence(timeout: 10))
        fifth.swipeLeft()
        app.buttons["Add to Queue"].tap()
        back(app)

        miniPlayer.tap()
        XCTAssertTrue(app.descendants(matching: .any)["playback-progress"].waitForExistence(timeout: 10))
        snap(app, "07-now-playing")
        let queued = app.buttons.matching(identifier: "up-next").firstMatch
        for _ in 0..<3 where !(queued.exists && queued.isHittable) { app.swipeUp() }
        XCTAssertTrue(queued.label.contains("Symphony No. 5"))
        snap(app, "08-up-next")
        app.buttons["Done"].tap()

        reveal(app.buttons["local-storage"], in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["download"].firstMatch.waitForExistence(timeout: 10))
        snap(app, "08a-local-storage")
        back(app)

        reveal(app.buttons["swipe-actions"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Swipe Actions"].waitForExistence(timeout: 10))
        snap(app, "08b-swipe-actions")
        back(app)

        reveal(app.buttons["classical-filter"], in: app).tap()
        XCTAssertTrue(app.textFields.matching(identifier: "condition-text").firstMatch.waitForExistence(timeout: 10))
        snap(app, "09-filter")
        back(app)

        reveal(app.buttons["classical-albums"], in: app).tap()
        let concerto = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Mendelssohn: Violin Concerto'")).firstMatch
        XCTAssertTrue(concerto.waitForExistence(timeout: 10))
        snap(app, "10-classical-albums")
        // A tap opens the album. It does not start to play.
        concerto.tap()
        XCTAssertTrue(app.buttons["play-recording"].waitForExistence(timeout: 10))
        back(app)
        back(app)

        reveal(app.buttons["diagnostics"], in: app).tap()
        XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["opensubsonic"].waitForExistence(timeout: 10))
        snap(app, "11-diagnostics")
        app.swipeUp()
        app.swipeUp()
        let signOut = app.buttons["Sign Out"]
        let bar = app.descendants(matching: .any)["mini-player"].firstMatch
        XCTAssertTrue(signOut.isHittable)
        XCTAssertLessThanOrEqual(signOut.frame.maxY, bar.frame.minY, "The mini player covers the last row.")
        snap(app, "12-diagnostics-bottom")

        let showTaps = reveal(app.switches["show-taps"], in: app)
        showTaps.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(showTaps.value as? String, "1")
        snap(app, "12a-show-taps")

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
    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Scrolls down until the element is on screen. Lists create rows only when they come near the screen.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<4 where !(element.exists && element.isHittable) { app.swipeUp() }
        return element
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
