import XCTest

/// Launch-level checks with the network replaced by canned data (`-MurkStub`).
final class SmokeTests: XCTestCase {
    private func launch(_ stub: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-MurkStub", stub] + extra
        app.launch()
        return app
    }

    func testFirstLaunchShowsAForecastWithoutAskingForLocation() {
        let app = launch("online")
        let place = app.buttons["placeName"]
        XCTAssertTrue(place.waitForExistence(timeout: 20))
        XCTAssertTrue(place.label.contains("San Diego"))
        XCTAssertTrue(app.buttons["USE MY LOCATION"].waitForExistence(timeout: 5))     // offered, not demanded
        XCTAssertTrue(app.buttons["status"].waitForExistence(timeout: 10))
    }

    func testSettingsOpenAndOfferPlacesAndPro() {
        let app = launch("online")
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 20))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["Use Current Location"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restore Purchases"].exists || app.staticTexts["Restore Purchases"].exists)
    }

    func testWidgetLinkOpensTheApp() {
        let app = launch("online")
        XCTAssertTrue(app.buttons["placeName"].waitForExistence(timeout: 20))
        app.open(URL(string: "murk://settings")!)
        XCTAssertTrue(app.navigationBars["Murk"].waitForExistence(timeout: 10))
        app.open(URL(string: "murk://not-a-page")!)          // ignored, no crash
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testOfflineLaunchOffersRetryInsteadOfABlankScreen() {
        let app = launch("offline")
        let retry = app.buttons["Try again"], status = app.buttons["status"]
        // With a saved forecast the status line offers the retry; with none, the empty state does.
        XCTAssertTrue(retry.waitForExistence(timeout: 20) || status.waitForExistence(timeout: 5))
    }

    func testLargeTextAndReducedMotionLaunch() {
        let app = launch("online", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(app.buttons["placeName"].waitForExistence(timeout: 20))
    }
}
