import XCTest

@MainActor
final class SetupNoticeUITests: XCTestCase {
    func testDecliningLocationLeavesInlineInstructionsInsteadOfAnotherAlert() {
        let app = XCUIApplication()
        app.launchArguments = ["-pokiScreen", "setup", "-pokiSetupStep", "5", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.resetAuthorizationStatus(for: .location)
        app.launch()

        let location = app.buttons["background.location"]
        XCTAssertTrue(location.waitForExistence(timeout: 15))
        location.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let decline = springboard.buttons.matching(NSPredicate(format: "label MATCHES %@", "Don.t Allow")).firstMatch
        XCTAssertTrue(decline.waitForExistence(timeout: 10))
        decline.tap()

        let help = app.staticTexts["Set Location to Always in Settings to finish this step. Poki never records your location."]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Choose Always"].exists)
    }
}
