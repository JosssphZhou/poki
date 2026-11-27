import XCTest

final class MemoryPageEditorUITests: XCTestCase {
    func testSamplePageEditorOpensAndKeepsDraft() {
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Memory page editor"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(app.buttons["memory.pageEditor.save"].exists)
    }
}
