import XCTest

final class SensesHomeClearUITests: XCTestCase {
    func testFreshHomeSuggestionSurvivesLateOldResult() {
        let app = XCUIApplication()
        app.launchArguments = ["-pokiScreen", "chat", "-pokiUITestSensesHome",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let wifiOnly = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["仅限无线局域网"]
        if wifiOnly.waitForExistence(timeout: 3) { wifiOnly.tap() }
        let clear = app.buttons["fixture.history.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 20))
        clear.tap()
        let confirm = app.buttons["fixture.history.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let matches = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Fresh suggestion"))
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10))
        func visible() -> Bool {
            // Marquee repeats pills; its first accessibility match may be the offscreen copy.
            matches.allElementsBoundByIndex.contains { item in
                let seen = item.frame.intersection(app.frame.insetBy(dx: 16, dy: 100))
                return seen.width > 120 && seen.height > 30
            }
        }
        XCTAssertTrue(visible(), "The fresh suggestion must actually be visible on Home")
        app.buttons["fixture.history.release"].tap()
        XCTAssertTrue(app.buttons["Old result released"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(visible(), "The late old result must leave the fresh suggestion visible")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Old suggestion")).firstMatch.exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Fresh Home suggestion survives the old result"
        image.lifetime = .keepAlways
        add(image)
    }
}
