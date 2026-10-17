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

        let diagnostics = app.buttons["diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15))
        snap(app, "02-home")

        diagnostics.tap()
        XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["opensubsonic"].waitForExistence(timeout: 10))
        snap(app, "03-diagnostics")
        app.swipeUp()
        snap(app, "04-diagnostics-bottom")
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
