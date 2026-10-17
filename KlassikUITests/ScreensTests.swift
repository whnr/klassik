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

        XCTAssertTrue(app.descendants(matching: .any)["library-synced"].waitForExistence(timeout: 30))
        snap(app, "02-home")

        app.buttons["classical-filter"].tap()
        XCTAssertTrue(app.textFields["filter-genre"].waitForExistence(timeout: 10))
        snap(app, "03-filter")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["classical-albums"].tap()
        XCTAssertTrue(app.staticTexts["Mendelssohn: Violin Concerto"].waitForExistence(timeout: 10))
        snap(app, "04-classical-albums")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let diagnostics = app.buttons["diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10))
        diagnostics.tap()
        XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["opensubsonic"].waitForExistence(timeout: 10))
        snap(app, "05-diagnostics")
        app.swipeUp()
        snap(app, "06-diagnostics-bottom")

        let gaplessTest = app.buttons["gapless-test"]
        for _ in 0..<3 where !(gaplessTest.exists && gaplessTest.isHittable) { app.swipeUp() }
        gaplessTest.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Mendelssohn\n")
        let album = app.buttons.matching(identifier: "gapless-album").firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 15))
        snap(app, "07-gapless-search")

        album.tap()
        let track = app.buttons.matching(identifier: "gapless-track").firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 15))
        track.tap()
        let analysis = app.buttons.matching(NSPredicate(format: "label CONTAINS 'iOS decodes'")).firstMatch
        XCTAssertTrue(analysis.waitForExistence(timeout: 30))
        snap(app, "08-gapless-album")
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
