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
        restartChat()
        choose(work)
        send("private-work-context")
        choose(personal)
        send("personal-new-task")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["composer.model.brain"].waitForExistence(timeout: 10))
        // Open the saved conversation through the actual drawer.
        let saved = app.buttons.containing(.staticText, identifier: "Synthetic reply").firstMatch
        if !saved.isHittable {
            app.buttons["chat.threads"].tap()
        }
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        let brain = app.buttons["composer.model.brain"]
        XCTAssertTrue(brain.waitForExistence(timeout: 5))
        XCTAssertTrue(brain.label.contains(personal))
        screenshot("Selected Personal profile and restored conversation")
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
        // The Brain shortcut must not open a picker while a task runs.
        let brain = app.buttons["composer.model.brain"]
        XCTAssertFalse(brain.isEnabled)
        brain.tap()
        XCTAssertFalse(app.buttons["Accounts and Models"].waitForExistence(timeout: 2))
        // Send/Stop stays functional.
        let stop = app.buttons["composer.main"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND label == %@", "Stop"), object: stop)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        stop.tap()
        XCTAssertTrue(app.staticTexts["Stopped."].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(brain.isEnabled)
    }
    func testUpstreamModelsInUseAndChangeChatModelUseTheChosenProfile() {
        let label = "Settings fixture \(UUID().uuidString.prefix(4))"
        addProfile(label, key: "fixture-settings")
        screenshot("Multiple account profiles")
        for _ in 0..<8 where !app.buttons["model.inUse.action"].isHittable { app.swipeDown() }
        let action = app.buttons["model.inUse.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
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
        let brain = app.buttons["composer.model.brain"]
        XCTAssertTrue(brain.waitForExistence(timeout: 10))
        XCTAssertTrue(brain.label.contains(label))
        screenshot("Models selection shown by the Brain shortcut")
    }

    private func screenshot(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    func testFreshInstallShowsTheComposerShortcutByDefault() {
        // On a simulator where no shortcut preference has been stored yet, the shortcut is on.
        restartChat()
        let brain = app.buttons["composer.model.brain"]
        XCTAssertTrue(brain.waitForExistence(timeout: 10))
        screenshot("Fresh install shows the composer Brain shortcut")
    }

    func testNativeToggleHidesAndRestoresTheShortcutAndTheChoicePersists() {
        // The native Models switch turns the shortcut off.
        setShortcut(false)
        restartChat()
        XCTAssertFalse(app.buttons["composer.model.brain"].exists)
        // More keeps account management without a chat-model selector.
        app.buttons["composer.more"].tap()
        XCTAssertTrue(app.buttons["Accounts and Models"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["composer.model"].exists)
        screenshot("More without a chat-model selector while the shortcut is off")
        app.buttons["Accounts and Models"].tap()
        // The saved-off preference survives another launch.
        restartChat()
        XCTAssertFalse(app.buttons["composer.model.brain"].exists)
        // Models remains the route to account and model management.
        openAccountsFromMore()
        XCTAssertTrue(app.buttons["model.inUse.action"].waitForExistence(timeout: 10))
        // Restore the default-on preference for the rest of the suite.
        setShortcut(true)
        restartChat()
        XCTAssertTrue(app.buttons["composer.model.brain"].waitForExistence(timeout: 10))
    }

    func testBrainPickerSelectsProfilesAndModelsAndKeepsTheDraft() {
        let work = "Work \(UUID().uuidString.prefix(4))"
        let personal = "Personal \(UUID().uuidString.prefix(4))"
        addProfile(work, key: "fixture-brain-work")
        addProfile(personal, key: "fixture-brain-personal")

        restartChat()
        let brain = app.buttons["composer.model.brain"]
        let input = app.descendants(matching: .any).matching(identifier: "capsule.field").firstMatch
        let main = app.buttons["composer.main"]
        XCTAssertTrue(brain.waitForExistence(timeout: 10))
        // Layout: the shortcut sits between the field and Send with a full touch target.
        XCTAssertGreaterThanOrEqual(brain.frame.width, 44)
        XCTAssertGreaterThanOrEqual(brain.frame.height, 44)
        XCTAssertLessThanOrEqual(input.frame.maxX, brain.frame.minX)
        XCTAssertLessThanOrEqual(brain.frame.maxX, main.frame.minX)
        choose(work)
        XCTAssertEqual(main.label, "Talk to Poki")

        // More keeps the other actions without a chat-model selector.
        app.buttons["composer.more"].tap()
        XCTAssertTrue(app.buttons["Accounts and Models"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["composer.model"].exists)
        XCTAssertTrue(app.buttons["Dictate"].isEnabled)
        dismissMenu()

        // The draft and keyboard survive opening the picker and switching accounts.
        input.tap()
        let draft = "Fixture draft stays in the message field while I switch accounts."
        input.typeText(draft)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 6))
        recordScreenshot("Composer before opening Brain")
        brain.tap()
        XCTAssertTrue(app.buttons["Accounts and Models"].waitForExistence(timeout: 5))
        recordScreenshot("Brain account picker")
        let row = app.buttons["DeepSeek, \(personal)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        recordScreenshot("Brain profile model choices")
        let model = app.buttons["DeepSeek V4.1 Flash"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.tap()
        XCTAssertTrue(brain.waitForExistence(timeout: 5))
        XCTAssertTrue(brain.label.contains(personal))
        XCTAssertTrue(brain.label.contains("deepseek-flash"))
        XCTAssertEqual(input.value as? String, draft)
        XCTAssertTrue(keyboard.exists)
        input.typeText("!")
        XCTAssertEqual(input.value as? String, draft + "!")
        XCTAssertEqual(main.label, "Send")
        recordScreenshot("Brain selection with the draft preserved")
    }

    func testBrainDismissalKeepsComposerUsableAtLargeTextSizes() {
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
    }

    func testBrainCannotSwitchDuringSyntheticTaskAndStopRemainsReachable() {
        let label = "Brain Stop \(UUID().uuidString.prefix(4))"
        addProfile(label, key: "fixture-brain-stop")
        restartChat()
        let brain = app.buttons["composer.model.brain"]
        let sendStop = app.buttons["composer.main"]
        XCTAssertTrue(brain.waitForExistence(timeout: 10))
        brain.tap()
        let row = app.buttons["DeepSeek, \(label)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let flash = app.buttons["DeepSeek V4.1 Flash"]
        XCTAssertTrue(flash.waitForExistence(timeout: 5))
        flash.tap()
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
    }

    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }

    private func openAccountsFromMore() {
        app.buttons["composer.more"].tap()
        app.buttons["Accounts and Models"].tap()
    }

    /// The native Models switch for the composer shortcut; the app must be on the Models screen.
    /// Tap the trailing switch control itself and verify the outcome behaviorally after a relaunch.
    private func setShortcut(_ enabled: Bool) {
        let toggle = app.switches["model.switcher.shortcut"]
        for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let frame = toggle.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + frame.width - 20, dy: frame.midY))
            .tap()
        usleep(500000)
        recordScreenshot("Composer shortcut tapped for \(enabled ? "on" : "off")")
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
        let brain = app.buttons["composer.model.brain"]
        XCTAssertTrue(brain.waitForExistence(timeout: 10))
        brain.tap()
        XCTAssertTrue(app.buttons["Accounts and Models"].waitForExistence(timeout: 5))
        let row = app.buttons["\(provider), \(label)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        let choice = app.buttons[model]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        XCTAssertTrue(brain.waitForExistence(timeout: 5))
        XCTAssertTrue(brain.label.contains(label))
    }
    private func send(_ text: String) {
        let input = app.descendants(matching: .any).matching(identifier: "capsule.field").firstMatch
        input.tap(); input.typeText(text)
        app.buttons["composer.main"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic reply"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "composer.main", "Talk to Poki")).firstMatch.waitForExistence(timeout: 15))
    }
}
