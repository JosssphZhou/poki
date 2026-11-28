import XCTest

final class RecentAppMentionUITests: XCTestCase {
    func testTypingMentionWithDuplicateRecentsShowsOneNotesSuggestion() {
        let app = XCUIApplication()
        let suite = UUID().uuidString
        let base = ["-pokiScreen", "chat", "-pokiUITestRecentsFingerprint",
                    "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments = base
        app.launch()
        let fingerprint = app.staticTexts["fixture.recents.fingerprint"]
        XCTAssertTrue(fingerprint.waitForExistence(timeout: 20))
        let original = fingerprint.label
        app.terminate()
        app.launchArguments = base + ["-pokiUITestDuplicateRecentApps", "-pokiUITestRecentsSuite", suite]
        app.launch()
        let field = app.textViews["capsule.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("@")
        let notes = app.buttons.matching(identifier: "mention.com.apple.mobilenotes")
        XCTAssertTrue(notes.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes.firstMatch.label.contains("Notes"))
        field.typeText("Note")
        XCTAssertTrue(notes.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(notes.count, 1)
        notes.firstMatch.tap()
        XCTAssertTrue((field.value as? String)?.contains("Notes") == true)
        XCTAssertEqual(fingerprint.label, original)
        app.terminate()
        app.launchArguments = base + ["-pokiUITestCleanupRecents", "-pokiUITestRecentsSuite", suite]
        app.launch()
        XCTAssertTrue(fingerprint.waitForExistence(timeout: 20))
        XCTAssertEqual(fingerprint.label, original, "A fresh non-fixture launch must retain both original recent-app histories")
    }
}
