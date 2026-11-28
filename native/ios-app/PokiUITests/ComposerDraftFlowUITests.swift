import XCTest

final class ComposerDraftFlowUITests: XCTestCase {
    func testSameDraftSurvivesFullAppConversationChange() {
        let app = XCUIApplication()
        app.launchArguments = ["-pokiScreen", "chat", "-pokiUITestComposerDraft",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let wifiOnly = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["仅限无线局域网"]
        if wifiOnly.waitForExistence(timeout: 3) { wifiOnly.tap() }
        let field = app.textViews["capsule.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("Open Settings")
        app.buttons["composer.main"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic reply finished."].waitForExistence(timeout: 15),
                      "The real send path must consume the local response before switching conversations")
        let fresh = app.buttons["home.newChat"]
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: fresh)
        waitForExpectations(timeout: 20)
        fresh.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Open Settings")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue((field.value as? String)?.contains("Open") == true)
        XCTAssertTrue((field.value as? String)?.contains("Settings") == true)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Full app new conversation keeps identical draft"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
