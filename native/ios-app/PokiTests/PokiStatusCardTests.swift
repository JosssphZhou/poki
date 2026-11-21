import PokiCore
import SwiftUI
import UIKit
import XCTest
@testable import Poki

@MainActor
final class PokiStatusCardTests: XCTestCase {
    func testStatusCardExpandsApprovalsInlineHidesAutoUnlockAndOpensCustomization() async throws {
        let savedMode = UserDefaults.standard.object(forKey: ApprovalClassifier.modeKey)
        defer { UserDefaults.standard.set(savedMode, forKey: ApprovalClassifier.modeKey) }
        UserDefaults.standard.set(ApprovalClassifier.Mode.confirm.rawValue, forKey: ApprovalClassifier.modeKey)

        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        let chat = ChatModel(app: model)
        var presented = true
        var openedCustomization = false
        let window = try showCard(
            model: model,
            chat: chat,
            isPresented: Binding(get: { presented }, set: { presented = $0 }),
            openCustomization: { openedCustomization = true }
        )
        defer { window.isHidden = true }

        let approvals = try await waitForElement(in: window, id: "status.approvals")
        XCTAssertNotNil(Self.element(in: window, id: "status.card"))
        XCTAssertNotNil(Self.element(in: window, id: "status.word"))
        XCTAssertNotNil(Self.element(in: window, id: "status.customizePoki"))
        XCTAssertNil(Self.element(in: window, id: "status.autoUnlock"),
                     "Automatic Unlock must stay hidden in the 0.4.7 candidate")

        XCTAssertTrue(approvals.accessibilityActivate())
        let offOption = try await waitForElement(in: window, id: "status.approvals.off")
        XCTAssertNotNil(Self.element(in: window, id: "status.approvals.reply"))
        XCTAssertNotNil(Self.element(in: window, id: "status.approvals.confirm"))

        XCTAssertTrue(offOption.accessibilityActivate())
        try await waitUntil(in: window) {
            model.approvalMode == .off && Self.element(in: window, id: "status.approvals.off") == nil
        }

        let customize = try await waitForElement(in: window, id: "status.customizePoki")
        XCTAssertTrue(customize.accessibilityActivate())
        try await waitUntil(in: window) { openedCustomization && !presented }
    }

    func testStatusCardExpandsCustomProviderModelsInlineAndSelectsChoice() async throws {
        let defaults = UserDefaults.standard
        let savedProviders = defaults.object(forKey: CustomProviders.storeKey)
        let savedCustomSelected = defaults.object(forKey: CustomProviders.selectedKey)
        let savedProvider = defaults.object(forKey: "chat.provider")
        let savedCustomModel = defaults.object(forKey: "chat.model.custom")
        let savedAvailable = defaults.object(forKey: "models.enabled.custom")

        let first = CustomProvider(
            name: "Alpha Gateway",
            endpoints: [CustomEndpoint(url: "https://alpha.invalid/v1")],
            model: "alpha-model"
        )
        let second = CustomProvider(
            name: "Beta Gateway",
            endpoints: [CustomEndpoint(url: "https://beta.invalid/v1")],
            model: "beta-model"
        )
        defer {
            CustomProviders.remove(first.id)
            CustomProviders.remove(second.id)
            Self.restore(savedProviders, forKey: CustomProviders.storeKey)
            Self.restore(savedCustomSelected, forKey: CustomProviders.selectedKey)
            Self.restore(savedProvider, forKey: "chat.provider")
            Self.restore(savedCustomModel, forKey: "chat.model.custom")
            Self.restore(savedAvailable, forKey: "models.enabled.custom")
            ModelKeys.saved += 1
        }

        CustomProviders.upsert(first)
        CustomProviders.upsert(second)
        let firstChoice = CustomProviders.choiceID(first.id, first.model)
        let secondChoice = CustomProviders.choiceID(second.id, second.model)
        ModelKeys.selectedProvider = .custom
        ModelKeys.selectedModel = firstChoice
        ModelKeys.saved += 1

        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        let chat = ChatModel(app: model)
        var presented = true
        let window = try showCard(
            model: model,
            chat: chat,
            isPresented: Binding(get: { presented }, set: { presented = $0 }),
            openCustomization: {}
        )
        defer { window.isHidden = true }

        let modelButton = try await waitForElement(in: window, id: "status.model")
        XCTAssertTrue(modelButton.accessibilityActivate())
        let betaButton = try await waitForElement(in: window, id: "status.model.\(secondChoice)")
        XCTAssertNotNil(Self.element(in: window, id: "status.model.\(firstChoice)"))

        XCTAssertTrue(betaButton.accessibilityActivate())
        try await waitUntil(in: window) {
            ModelKeys.selectedProvider == .custom
                && ModelKeys.selectedModel == secondChoice
                && Self.element(in: window, id: "status.model.\(secondChoice)") == nil
        }
    }

    private func showCard(
        model: AppModel,
        chat: ChatModel,
        isPresented: Binding<Bool>,
        openCustomization: (() -> Void)?
    ) throws -> UIWindow {
        let accessibility = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW))
        let setEnabled = unsafeBitCast(
            try XCTUnwrap(dlsym(accessibility, "_AXSSetAutomationEnabled")),
            to: (@convention(c) (Int32) -> Void).self
        )
        setEnabled(1)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        let root = Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pokiStatusCard(
                isPresented: isPresented,
                under: 240,
                openModel: {},
                openCustomization: openCustomization
            )
            .environment(model)
            .environment(chat)
            .environment(\.accessibilityEnabled, true)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        UIAccessibility.post(notification: .screenChanged, argument: window.rootViewController?.view)
        return window
    }

    private func waitForElement(in window: UIWindow, id: String) async throws -> NSObject {
        try await waitUntil(in: window) { Self.element(in: window, id: id) != nil }
        return try XCTUnwrap(Self.element(in: window, id: id))
    }

    private func waitUntil(in window: UIWindow, condition: @escaping @MainActor () -> Bool) async throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.layoutIfNeeded()
            return MainActor.assumeIsolated { condition() }
        }, object: nil)
        await fulfillment(of: [expectation], timeout: 5)
    }

    private static func restore(_ value: Any?, forKey key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private static func element(in root: NSObject, id: String) -> NSObject? {
        let selector = NSSelectorFromString("accessibilityIdentifier")
        return all(in: root).first { item in
            let identifier = item.responds(to: selector)
                ? item.perform(selector)?.takeUnretainedValue() as? String
                : nil
            return identifier == id
        }
    }

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
