import XCTest

/// TestFlight ships an optimized build, and the UI walk tests a debug build. The optimizer can change what a
/// cast does, so this test opens the places in a release build. It runs only from `scripts/release-launch.sh`.
final class ReleaseLaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A listener who updates the app opens it with a stored login and the files of the last build.
    @MainActor
    func testOpensThePlacesAfterLoginAndAfterRelaunch() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["KLASSIK_RELEASE_LAUNCH"] == "1", let server = env["KLASSIK_SERVER_URL"] else {
            throw XCTSkip("Runs only from scripts/release-launch.sh")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-resetServer"]
        app.launchEnvironment = [
            "OS_ACTIVITY_DT_MODE": "NO",
            "KLASSIK_SERVER_URL": server,
            "KLASSIK_USERNAME": env["KLASSIK_USERNAME"] ?? "",
            "KLASSIK_PASSWORD": env["KLASSIK_PASSWORD"] ?? "",
        ]
        app.launch()
        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 30), "No connect button")
        connect.tap()
        expectPlaces(app, "after the login")

        // The composers show when the first sync has written the library cache and the device file.
        let composers = app.buttons["library-composers"]
        XCTAssertTrue(composers.waitForExistence(timeout: 30), "No composers row")
        composers.tap()
        let composer = app.buttons.matching(identifier: "composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 60), "No composer after the first sync")
        app.terminate()

        app.launchArguments = []
        app.launchEnvironment = ["OS_ACTIVITY_DT_MODE": "NO"]
        app.launch()
        expectPlaces(app, "after a launch with the stored data")
    }

    @MainActor
    private func expectPlaces(_ app: XCUIApplication, _ moment: String) {
        XCTAssertTrue(app.tabBars["tab-row"].waitForExistence(timeout: 30), "No tab bar \(moment)")
        XCTAssertEqual(app.state, .runningForeground, "The app does not run \(moment)")
    }
}
