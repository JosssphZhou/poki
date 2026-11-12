import XCTest

final class ProfileJourneyTests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchEnvironment["POKI_UI_TEST_PROXY"] = ProcessInfo.processInfo.environment["POKI_UI_TEST_PROXY"] ?? "http://127.0.0.1:19383"
        launch("model")
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
        setPlacement("more")
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
        // While Stop is showing, the open keyboard leaves the More popover above the composer.
        // Dismiss it from the opposite edge before tapping Stop.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.24)).tap()
        XCTAssertTrue(app.buttons["composer.model.busy"].waitForNonExistence(timeout: 5))
        let stop = app.buttons["composer.main"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND label == %@", "Stop"), object: stop)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        stop.tap()
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

    func testModelSwitcherPlacementPersistsAndBothEntrancesSelectProfiles() {
        setPlacement("more")
        let work = "Work \(UUID().uuidString.prefix(4))"
        let personal = "Personal \(UUID().uuidString.prefix(4))"
        addProfile(work, key: "fixture-brain-work")
        addProfile(personal, key: "fixture-brain-personal")

        restartChat()
        let more = app.buttons["composer.more"]
        let brain = app.buttons["composer.model.brain"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        XCTAssertFalse(brain.exists)
        choose(work)
        XCTAssertEqual(app.buttons["composer.main"].label, "Talk to Poki")

        openAccountsFromMore()
        setPlacement("brain")
        restartChat()
        XCTAssertTrue(brain.waitForExistence(timeout: 10))
        XCTAssertTrue(brain.label.contains(work))
        XCTAssertTrue(brain.label.contains("deepseek-flash"))
        XCTAssertGreaterThanOrEqual(brain.frame.width, 44)
        XCTAssertGreaterThanOrEqual(brain.frame.height, 44)
        let input = app.descendants(matching: .any).matching(identifier: "capsule.field").firstMatch
        XCTAssertGreaterThan(input.frame.width, 90)
        XCTAssertLessThanOrEqual(input.frame.maxX, brain.frame.minX)
        XCTAssertLessThanOrEqual(brain.frame.maxX, app.buttons["composer.main"].frame.minX)

        more.tap()
        XCTAssertTrue(app.buttons["Accounts and Models"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["composer.model"].exists)
        XCTAssertTrue(app.buttons["Dictate"].isEnabled)
        XCTAssertEqual(app.buttons["composer.main"].label, "Talk to Poki")
        dismissMenu()

        input.tap()
        let draft = "Fixture draft stays in the message field while I switch accounts."
        input.typeText(draft)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 6))
        recordScreenshot("Composer before opening Brain")
        brain.tap()
        XCTAssertTrue(app.buttons["Accounts and Models"].waitForExistence(timeout: 5))
        recordScreenshot("Brain provider menu")
        app.buttons["DeepSeek"].tap()
        app.buttons[personal].tap()
        recordScreenshot("Brain profile model choices")
        app.buttons["DeepSeek V4.1 Flash"].tap()
        XCTAssertTrue(brain.label.contains(personal))
        XCTAssertTrue(brain.label.contains("deepseek-flash"))
        XCTAssertEqual(input.value as? String, draft)
        XCTAssertTrue(keyboard.exists)
        input.typeText("!")
        XCTAssertEqual(input.value as? String, draft + "!")
        XCTAssertEqual(app.buttons["composer.main"].label, "Send")
        recordScreenshot("Brain with selected profile and draft")

        restartChat()
        XCTAssertTrue(brain.waitForExistence(timeout: 10))
        XCTAssertTrue(brain.label.contains(personal))
        openAccountsFromMore()
        setPlacement("more")
        restartChat()
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        XCTAssertFalse(brain.exists)
        more.tap()
        let picker = app.buttons["composer.model"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains(personal))
        XCTAssertTrue(picker.label.contains("deepseek-flash"))
        recordScreenshot("More with the same selected profile")
        dismissMenu()
        input.tap()
        input.typeText("Draft in More mode")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 6))
        choose(work)
        XCTAssertTrue(keyboard.exists)
        input.typeText("!")
        XCTAssertEqual(input.value as? String, "Draft in More mode!")
    }

    func testBrainDismissalKeepsComposerUsableAtLargeTextSizes() {
        setPlacement("brain")
        restartChat()
        let brain = app.buttons["composer.model.brain"]
        let input = app.textViews["capsule.field"]
        let main = app.buttons["composer.main"]
        XCTAssertTrue(brain.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(brain.frame.width, 44)
        XCTAssertLessThanOrEqual(input.frame.maxX, brain.frame.minX)
        XCTAssertLessThanOrEqual(brain.frame.maxX, main.frame.minX)
        input.tap()
        input.typeText("Fixture draft")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 6))
        recordScreenshot("Composer before dismissal test")
        brain.tap()
        let accounts = app.buttons["Accounts and Models"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 5))
        recordScreenshot("Brain picker at large text size")
        dismissMenu()
        XCTAssertTrue(accounts.waitForNonExistence(timeout: 5))
        XCTAssertTrue(keyboard.exists)
        XCTAssertEqual(input.value as? String, "Fixture draft")
        XCTAssertEqual(main.label, "Send")
        recordScreenshot("Composer after dismissing Brain")
        app.terminate()
        launch("model")
        setPlacement("more")
    }

    func testBrainCannotSwitchDuringSyntheticTaskAndStopRemainsReachable() {
        setPlacement("brain")
        let label = "Brain Stop \(UUID().uuidString.prefix(4))"
        addProfile(label, key: "fixture-brain-stop")
        restartChat()
        let brain = app.buttons["composer.model.brain"]
        let sendStop = app.buttons["composer.main"]
        XCTAssertTrue(brain.waitForExistence(timeout: 10))
        brain.tap()
        app.buttons["DeepSeek"].tap()
        app.buttons[label].tap()
        app.buttons["DeepSeek V4.1 Flash"].tap()
        XCTAssertTrue(brain.label.contains(label))
        let input = app.descendants(matching: .any).matching(identifier: "capsule.field").firstMatch
        input.tap()
        input.typeText("hold-for-stop")
        sendStop.tap()
        let stopping = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Stop"), object: sendStop)
        XCTAssertEqual(XCTWaiter.wait(for: [stopping], timeout: 5), .completed)
        XCTAssertFalse(brain.isEnabled)
        recordScreenshot("Disabled Brain while Stop remains available")
        sendStop.tap()
        XCTAssertTrue(app.staticTexts["Stopped."].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(brain.isEnabled)
        openAccountsFromMore()
        setPlacement("more")
    }

    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }

    private func openAccountsFromMore() {
        app.buttons["composer.more"].tap()
        app.buttons["Accounts and Models"].tap()
    }

    private func setPlacement(_ placement: String) {
        let option = app.buttons["model.switcher.\(placement)"]
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
        XCTAssertTrue(option.isSelected)
        recordScreenshot("Accounts setting for \(placement)")
    }

    private func recordScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func restartChat() {
        app.terminate()
        launch("chat")
    }

    private func launch(_ screen: String) {
        app.launchArguments = ["-pokiScreen", screen, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
