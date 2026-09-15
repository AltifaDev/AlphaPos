import XCTest

final class AlphaPosLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndPresentsInteractiveContent() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(th)", "-AppleLocale", "th_TH"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(
            app.buttons.firstMatch.waitForExistence(timeout: 15) ||
            app.staticTexts.firstMatch.waitForExistence(timeout: 15),
            "AlphaPos must render interactive or readable launch content"
        )
    }
}
