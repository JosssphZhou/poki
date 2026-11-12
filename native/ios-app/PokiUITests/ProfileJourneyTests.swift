import XCTest

final class ProfileJourneyTests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchEnvironment["POKI_UI_TEST_PROXY"] = ProcessInfo.processInfo.environment["POKI_UI_TEST_PROXY"] ?? "http://127.0.0.1:19383"
        app.launchArguments = ["-pokiScreen", "model", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }
    func testTwoAPIProfilesSelectSendAndRestoreFromChat() throws {
        let work = "Work \(UUID().uuidString.prefix(4))"
        let personal = "Personal \(UUID().uuidString.prefix(4))"
        addProfile(work, key: "fixture-work")
        addProfile(personal, key: "fixture-personal")
        app.terminate()
        app.launchArguments = ["-pokiScreen", "chat", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        choose(work)
        send("private-work-context")
        choose(personal)
        send("personal-new-task")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["composer.more"].waitForExistence(timeout: 10))
        // Open the saved conversation through the actual drawer.
        let saved = app.buttons.containing(.staticText, identifier: "Synthetic reply").firstMatch
        if !saved.isHittable {
            app.buttons["chat.threads"].tap()
        }
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        app.buttons["composer.more"].tap()
        XCTAssertTrue(app.buttons["composer.model"].label.contains(personal))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Selected Personal profile and restored conversation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testCustomConnectionsReplacementDeletionAndMissingCredentials() throws {
        let first = "Custom A \(UUID().uuidString.prefix(4))"
        let second = "Custom B \(UUID().uuidString.prefix(4))"
        addProfile(first, key: "fixture-custom-a", providerID: "custom", endpoint: "http://127.0.0.1:19383/a/v1", model: "fixture-a")
        addProfile(second, key: "", providerID: "custom", endpoint: "http://127.0.0.1:19383/b/v1", model: "fixture-b")
        restartChat()
        choose(first, provider: "Custom Endpoint", model: "fixture-a")
        send("custom-endpoint-a-task")
        choose(second, provider: "Custom Endpoint", model: "fixture-b")
        send("custom-endpoint-b-task")
        app.buttons["composer.more"].tap()
        app.buttons["Accounts and Models"].tap()
        let row = app.buttons["Custom Endpoint, \(second)"]
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        row.tap()
        app.buttons["Edit Profile"].tap()
        app.secureTextFields["profile.key"].tap()
        app.secureTextFields["profile.key"].typeText("fixture-custom-replaced")
        screenshot("Profile editor")
        app.buttons["Save"].tap()
        restartChat()
        choose(second, provider: "Custom Endpoint", model: "fixture-b")
        send("custom-replacement-task")
        app.buttons["composer.more"].tap()
        app.buttons["Accounts and Models"].tap()
        let removal = app.buttons["Custom Endpoint, \(second)"]
        for _ in 0..<5 where !removal.isHittable { app.swipeUp() }
        removal.tap()
        let delete = app.buttons["Delete Profile"]
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        restartChat()
        let field = app.descendants(matching: .any).matching(identifier: "capsule.field").firstMatch
        field.tap(); field.typeText("deleted-profile-must-not-send")
        app.buttons["composer.main"].tap()
        XCTAssertTrue(app.staticTexts["Choose an available chat model or open Accounts to finish setting one up."].waitForExistence(timeout: 5))
    }
    func testActiveTaskDisablesSwitchingAndStopEndsIt() {
        let label = "Stop fixture \(UUID().uuidString.prefix(4))"
        addProfile(label, key: "fixture-stop")
        restartChat()
        choose(label)
        let field = app.descendants(matching: .any).matching(identifier: "capsule.field").firstMatch
        field.tap(); field.typeText("hold-for-stop")
        app.buttons["composer.main"].tap()
        XCTAssertTrue(app.buttons["composer.main"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["composer.main"].label, "Stop")
        app.buttons["composer.more"].tap()
        XCTAssertTrue(app.buttons["composer.model.busy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["composer.model"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        let closed = Date().addingTimeInterval(5)
        while app.buttons["composer.model.busy"].exists && Date() < closed { usleep(300_000) }
        app.buttons["composer.main"].tap()
        XCTAssertTrue(app.staticTexts["Stopped."].firstMatch.waitForExistence(timeout: 10))
    }
    func testUpstreamModelsInUseAndChangeChatModelUseTheChosenProfile() {
        let label = "Settings fixture \(UUID().uuidString.prefix(4))"
        addProfile(label, key: "fixture-settings")
        screenshot("Multiple account profiles")
        let detail = app.buttons["DeepSeek, \(label)"]
        detail.tap()
        screenshot("Profile management")
        app.navigationBars.buttons["Models"].tap()
        for _ in 0..<8 where !app.buttons["model.inUse.action"].isHittable { app.swipeDown() }
        let action = app.buttons["model.inUse.action"]
        XCTAssertTrue(action.isHittable)
        screenshot("Upstream Models and In Use")
        action.tap()
        let profile = app.buttons[label]
        for _ in 0..<6 where !profile.isHittable { app.swipeUp() }
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        let model = app.buttons["DeepSeek V4.1 Flash"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.tap()
        screenshot("Settings selected profile model")
        restartChat()
        app.buttons["composer.more"].tap()
        XCTAssertTrue(app.buttons["composer.model"].label.contains(label))
        screenshot("Native More selected settings profile")
    }

    private func screenshot(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    private func restartChat() {
        app.terminate()
        app.launchArguments = ["-pokiScreen", "chat", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }
    private func addProfile(_ label: String, key: String, providerID: String = "deepseek", endpoint: String? = nil, model: String? = nil) {
        var add = app.buttons["profile.add.\(providerID)"]
        if !add.exists {
            var create = app.buttons["model.addAccount"]
            let empty = app.buttons["model.inUse.action"]
            if empty.exists && empty.label == "Add Account" { create = empty }
            for _ in 0..<8 where !create.isHittable { app.swipeUp() }
            create.tap()
            add = app.buttons["model.addProvider.\(providerID)"]
        }
        for _ in 0..<5 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(label)
        let secret = app.secureTextFields["profile.key"]
        if !key.isEmpty { secret.tap(); secret.typeText(key) }
        if let endpoint {
            app.textFields["profile.address"].tap(); app.textFields["profile.address"].typeText(endpoint)
        }
        if let model { app.textFields["profile.model"].tap(); app.textFields["profile.model"].typeText(model) }
        app.buttons["Save"].tap()
        let row = app.buttons["\(providerID == "custom" ? "Custom Endpoint" : "DeepSeek"), \(label)"]
        for _ in 0..<16 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }
    private func choose(_ label: String, provider: String = "DeepSeek", model: String = "DeepSeek V4.1 Flash") {
        app.buttons["composer.more"].tap()
        let picker = app.buttons["composer.model"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        app.buttons[provider].tap()
        app.buttons[label].tap()
        app.buttons[model].tap()
        app.buttons["composer.more"].tap()
        XCTAssertTrue(app.buttons["composer.model"].label.contains(label))
        app.buttons["composer.more"].tap()
    }
    private func send(_ text: String) {
        let input = app.descendants(matching: .any).matching(identifier: "capsule.field").firstMatch
        input.tap(); input.typeText(text)
        app.buttons["composer.main"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic reply"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "composer.main", "Talk to Poki")).firstMatch.waitForExistence(timeout: 15))
    }
}
