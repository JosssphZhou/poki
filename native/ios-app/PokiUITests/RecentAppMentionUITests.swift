import XCTest

final class RecentAppMentionUITests: XCTestCase {
    func testTypingMentionWithDuplicateRecentsShowsOneNotesSuggestion() {
        let app = XCUIApplication()
        app.launchArguments += ["-pokiScreen", "chat", "-pokiUITestDuplicateRecentApps",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
    }
}
