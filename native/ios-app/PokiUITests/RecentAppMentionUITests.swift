import XCTest

final class RecentAppMentionUITests: XCTestCase {
    func testTypingMentionWithDuplicateRecentsShowsOneNotesSuggestion() {
        let app = XCUIApplication()
        let suite = UUID().uuidString
        let base = ["-pokiScreen", "chat", "-pokiUITestRecentsFingerprint",
                    "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments = base
        app.launch()
        // Establish nonempty real history through an ordinary composer selection, not fixture writes.
        let ordinary = app.textViews["capsule.field"]
        XCTAssertTrue(ordinary.waitForExistence(timeout: 20))
        ordinary.tap()
        ordinary.typeText("@Note")
        let ordinaryNotes = app.buttons["mention.com.apple.mobilenotes"]
        XCTAssertTrue(ordinaryNotes.waitForExistence(timeout: 5))
        ordinaryNotes.tap()
        XCTAssertTrue((ordinary.value as? String)?.contains("Notes") == true)
        ordinary.tap()
        ordinary.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32))
        app.terminate()
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
