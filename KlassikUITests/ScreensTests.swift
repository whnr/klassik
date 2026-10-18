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

        mendelssohn.tap()
        let work = app.buttons.matching(identifier: "work").firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        snap(app, "03-composer")

        work.tap()
        let recording = app.buttons.matching(identifier: "recording").firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 10))
        snap(app, "04-work")

        recording.tap()
        app.buttons["download-menu"].tap()
        app.buttons["Download"].tap()
        let downloaded = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Downloaded'")).firstMatch
        XCTAssertTrue(downloaded.waitForExistence(timeout: 60))
        app.buttons["play-recording"].tap()
        let playing = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Now playing'")).firstMatch
        XCTAssertTrue(playing.waitForExistence(timeout: 30))
        snap(app, "05-recording")
        // The fixture movements last seconds; paused, the player stays for the next screens.
        app.buttons["Pause"].firstMatch.tap()

        for _ in 0..<3 { back(app) }
        let miniPlayer = app.descendants(matching: .any)["mini-player"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 10))
        snap(app, "06-home-playing")

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

        reveal(app.buttons["classical-filter"], in: app).tap()
        XCTAssertTrue(app.textFields.matching(identifier: "condition-text").firstMatch.waitForExistence(timeout: 10))
        snap(app, "09-filter")
        back(app)

        reveal(app.buttons["classical-albums"], in: app).tap()
        let concerto = app.buttons.matching(identifier: "album")
            .matching(NSPredicate(format: "label CONTAINS 'Mendelssohn: Violin Concerto'")).firstMatch
        XCTAssertTrue(concerto.waitForExistence(timeout: 10))
        snap(app, "10-classical-albums")
        back(app)

        reveal(app.buttons["local-storage"], in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["cache-size"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["download-row"].firstMatch.waitForExistence(timeout: 10))
        snap(app, "15-local-storage")
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
