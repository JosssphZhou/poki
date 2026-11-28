import XCTest

final class MemoryPageEditorUITests: XCTestCase {
    func testConflictingSaveKeepsEditorDraft() {
        let app = XCUIApplication()
        app.launchArguments += ["-pokiScreen", "memory", "-pokiMemorySample", "NO",
                                "-pokiUITestMemoryPageConflict", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["memory.about.all"].waitForExistence(timeout: 20))
        app.buttons["memory.about.all"].tap()
        app.buttons["memory.editPage"].tap()
        let field = app.textFields["memory.pageEditor"]
        let view = app.textViews["memory.pageEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5) || view.waitForExistence(timeout: 5))
        let editor = field.exists ? field : view
        editor.tap()
        editor.typeText(" Owner draft")
        app.buttons["memory.fixture.write"].tap()
        let saved = app.staticTexts["memory.fixture.saved"]
        let landed = NSPredicate(format: "label == %@", "Updated synthetic memory")
        expectation(for: landed, evaluatedWith: saved)
        waitForExpectations(timeout: 5)
        app.buttons["memory.pageEditor.save"].tap()
        let alert = app.alerts["Memory Page Changed"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Memory page conflict preserves draft"
        attachment.lifetime = .keepAlways
        add(attachment)
        alert.buttons["OK"].tap()
        XCTAssertTrue(editor.exists)
        XCTAssertTrue((editor.value as? String)?.contains("Owner draft") == true)
        XCTAssertEqual(saved.label, "Updated synthetic memory")
        XCTAssertTrue(app.buttons["memory.pageEditor.save"].exists)
    }

    func testSamplePageEditorOpensWithCurrentText() {
        let app = XCUIApplication()
        app.launchArguments += ["-pokiScreen", "memory", "-pokiMemorySample", "YES",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let all = app.buttons["memory.about.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 20))
        all.tap()
        let edit = app.buttons["memory.editPage"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let field = app.textFields["memory.pageEditor"]
        let view = app.textViews["memory.pageEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5) || view.waitForExistence(timeout: 5))
        let editor = field.exists ? field : view
        XCTAssertTrue((editor.value as? String)?.contains("不吃香菜") == true)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Memory page editor"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(app.buttons["memory.pageEditor.save"].exists)
    }
}
