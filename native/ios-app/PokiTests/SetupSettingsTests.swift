import SwiftUI
import UIKit
import UserNotifications
import XCTest
@testable import Poki

final class SetupSettingsTests: XCTestCase {
    func testSystemSetupStepsOpenSettingsRoot() {
        for step: SetupStep in [.runner, .developerMode, .pairing, .automation] {
            XCTAssertEqual(settingsURL(for: step)?.absoluteString, "App-prefs:", "\(step) must not open Poki's App permissions")
        }
    }

    func testBackgroundPermissionsStillOpenPokiSettings() {
        XCTAssertEqual(settingsURL(for: .background)?.absoluteString, UIApplication.openSettingsURLString)
    }

    func testDefaultDestinationRemainsPokiSettings() {
        XCTAssertEqual(settingsURL(for: nil)?.absoluteString, UIApplication.openSettingsURLString)
    }

    @MainActor
    func testPairingDoesNotHandOffToSettingsWithoutAWorkingConnection() async {
        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        model.loopback.simulate(.noAnswer)

        let started = await model.startPairing()

        XCTAssertFalse(started)
        XCTAssertFalse(model.pairingUnderWay)
        XCTAssertNil(model.guiding)
        guard case .failed(let advice)? = model.pairing else { return XCTFail("Expected inline pairing guidance") }
        XCTAssertEqual(advice, AppLocalization.text(LocalizedStringResource("Enable a local connection in Setup and wait for the connection check to pass, then try pairing again.")))
    }

    @MainActor
    func testImportAfterFailedPairingShowsSavedFileWithoutRetryOrVerification() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SetupSettingsTests.\(folder.lastPathComponent)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let path = folder.appendingPathComponent("pairing.plist")
        let storage = PokiStorage(defaults: defaults, appGroupDefaults: defaults, keychainService: suite,
                                  codexService: suite, codexHome: folder, pairingFileURL: path)
        defer {
            SetupVault.forget(storage: storage)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }

        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: storage)
        model.loopback.simulate(.noAnswer)
        _ = await model.startPairing()
        guard case .failed? = model.pairing else { return XCTFail("Expected a failed pairing attempt") }

        XCTAssertThrowsError(try model.importPairingFile(Data(), how: "fixture"))
        guard case .failed? = model.pairing else { return XCTFail("Invalid imports must not clear the failure") }

        let record: [String: Any] = ["identifier": "fixture", "public_key": Data(repeating: 1, count: 32),
                                     "private_key": Data(repeating: 2, count: 32)]
        let data = try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0)
        try model.importPairingFile(data, how: "fixture")

        XCTAssertNil(model.pairing)
        XCTAssertEqual(try Data(contentsOf: path), data)
        XCTAssertNil(model.pairingVerifiedAt, "Saving a valid file format does not verify it with the phone")

        let elements = try await renderElements(
            NavigationStack { SetupStepPage(step: .pairing).settingsPage() }
                .environment(model),
            waitForLabelContaining: "Pairing File Saved"
        )
        let labels = elements.compactMap(\.accessibilityLabel)
        XCTAssertTrue(labels.contains { $0.contains("Not Verified Yet") })
        XCTAssertFalse(labels.contains { $0.contains("Try Again") })
    }

    @MainActor
    func testSetupAndPairingCompletionNeverShowTaskStandby() {
        let controller = ActivityController()
        controller.canStart = { false }
        controller.update { $0.phase = .setup; $0.headline = "Setting up Poki" }
        XCTAssertEqual(controller.state.face.content, String(activity: "Setting up Poki"))
        XCTAssertNil(controller.state.face.subtitle)

        controller.update { $0.phase = .pairing; $0.headline = "Pair in Settings" }
        controller.update { $0.phase = .idle; $0.headline = "Paired" }
        let finished = controller.state.face
        XCTAssertEqual(finished.content, String(activity: "Pairing complete"))
        XCTAssertEqual(finished.subtitle, String(activity: "Return to Poki to continue."))
        XCTAssertNil(finished.event)

        controller.update { $0.headline = "Waiting for agent" }
        XCTAssertEqual(controller.state.face.subtitle, String(activity: "Runner on. Waiting for the agent."))
    }

    @MainActor
    func testPairingCodeIsShownOnceWhenNoLiveActivityCanStart() {
        let activity = ActivityController()
        activity.canStart = { false }
        activity.start(deviceName: "Test iPhone")
        var notices: [String] = []

        activity.showPairingCode("123456") { notices.append($0) }
        activity.showPairingCode("123456") { notices.append($0) }

        XCTAssertEqual(activity.state.pin, "123456")
        XCTAssertEqual(notices, ["123456"])
    }

    /// Settings › Setup is the whole setup list on purpose (build 72 parity, the owner's choice on
    /// Nov 24 2026): the required steps and Guide Me, then the features with their state, even where
    /// the Settings home has a row for the same page.
    @MainActor
    func testSetupSettingsPageListsTheWholeSetup() async throws {
        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        let chat = ChatModel(app: model)
        let elements = try await renderElements(
            NavigationStack { SetupSettingsPage(path: .constant(NavigationPath())) }
                .environment(model)
                .environment(chat),
            waitForLabelContaining: "Guide Me"
        )
        let labels = elements.compactMap(\.accessibilityLabel)
        XCTAssertTrue(labels.contains { $0.contains("Required Steps") }, "Required Steps card must stay on Setup; saw \(labels)")
        XCTAssertTrue(labels.contains { $0.contains("Guide Me") }, "Guide Me must stay on Setup; saw \(labels)")
        for feature in ["Screen History", "Memory"] {
            XCTAssertTrue(labels.contains { $0.contains(feature) }, "Setup must list \(feature); saw \(labels)")
        }
        // Settings home's Notifications row requests system authorization first while undetermined,
        // and opens iOS Settings once already decided.
        XCTAssertEqual(NotificationPermissionAction.forStatus(.notDetermined, openSettingsWhenAuthorized: true), .requestAuthorization)
        XCTAssertEqual(NotificationPermissionAction.forStatus(.denied, openSettingsWhenAuthorized: true), .openSystemSettings)
        XCTAssertEqual(NotificationPermissionAction.forStatus(.authorized, openSettingsWhenAuthorized: true), .openSystemSettings)
    }

    /// The loopback step page keeps its Loopback Shortcut section, whichever way it is opened.
    @MainActor
    func testLoopbackStepPageKeepsTheLoopbackShortcut() async throws {
        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        let loopbackElements = try await renderElements(
            NavigationStack { SetupStepPage(step: .loopback, hero: false).settingsPage() }
                .environment(model),
            waitForLabelContaining: "Pick One App"
        )
        let loopbackLabels = loopbackElements.compactMap(\.accessibilityLabel)
        XCTAssertTrue(
            loopbackLabels.contains { $0.contains("Set It Up Step by Step") || $0.contains("How It Is Set Up") },
            "Loopback step page must keep the loopback shortcut section; saw \(loopbackLabels)"
        )
    }

    /// R3: Guided manual steps keep only the bottom primary Open Settings button; settings subpages keep the in-card row.
    @MainActor
    func testGuidedManualStepsHideDuplicateOpenSettingsRow() async throws {
        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        for step: SetupStep in [.developerMode, .automation] {
            let guided = try await renderElements(
                NavigationStack { SetupStepPage(step: step, hero: true).settingsPage() }
                    .environment(model),
                waitForLabelContaining: step == .developerMode ? "Developer Mode Is On" : "UI Automation Is On"
            )
            let guidedOpenButtons = Self.openSettingsButtons(in: guided)
            XCTAssertTrue(guidedOpenButtons.isEmpty, "Guided \(step) must hide the in-card Open Settings row; found \(guidedOpenButtons.count)")

            let subpage = try await renderElements(
                NavigationStack { SetupStepPage(step: step, hero: false).settingsPage() }
                    .environment(model),
                waitForLabelContaining: step == .developerMode ? "Developer Mode Is On" : "UI Automation Is On"
            )
            let subpageOpenButtons = Self.openSettingsButtons(in: subpage)
            XCTAssertEqual(subpageOpenButtons.count, 1, "Settings subpage \(step) must keep its in-card Open Settings row")
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func openSettingsButtons(in elements: [NSObject]) -> [NSObject] {
        elements.filter {
            $0.accessibilityLabel == "Open Settings" && $0.accessibilityTraits.contains(.button)
        }
    }

    @MainActor
    private func renderElements<V: View>(
        _ view: V,
        waitForLabelContaining: String
    ) async throws -> [NSObject] {
        let accessibility = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW))
        defer { dlclose(accessibility) }
        let isEnabled = unsafeBitCast(try XCTUnwrap(dlsym(accessibility, "_AXSAutomationEnabled")), to: (@convention(c) () -> Int32).self)
        let setEnabled = unsafeBitCast(try XCTUnwrap(dlsym(accessibility, "_AXSSetAutomationEnabled")), to: (@convention(c) (Int32) -> Void).self)
        let previous = isEnabled()
        setEnabled(1)
        defer { setEnabled(previous) }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        // Tall frame ensures every List section is materialized in the viewport.
        window.frame = CGRect(x: 0, y: 0, width: scene.screen.bounds.width, height: 2400)
        window.rootViewController = UIHostingController(rootView: view.environment(\.accessibilityEnabled, true))
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer { window.isHidden = true }
        UIAccessibility.post(notification: .screenChanged, argument: window.rootViewController?.view)

        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Self.all(in: window).contains { $0.accessibilityLabel?.contains(waitForLabelContaining) == true }
        }, object: nil)
        await fulfillment(of: [ready], timeout: 5)
        return Self.all(in: window)
    }

    @MainActor
    private static func all(in root: NSObject) -> [NSObject] {
        var pending = [root], found: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        while let item = pending.popLast() {
            guard visited.insert(ObjectIdentifier(item)).inserted else { continue }
            found.append(item)
            if let view = item as? UIView { pending.append(contentsOf: view.subviews) }
            if let children = item.accessibilityElements { pending.append(contentsOf: children.compactMap { $0 as? NSObject }) }
            let count = item.accessibilityElementCount()
            if count > 0 && count < 1000 {
                for index in 0..<count {
                    if let child = item.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        return found
    }
}
