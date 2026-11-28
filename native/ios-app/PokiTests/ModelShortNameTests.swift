import PiSwiftAI
import PokiCore
import SwiftUI
import UIKit
import XCTest
@testable import Poki

@MainActor
final class ModelShortNameTests: XCTestCase {
    private var window: UIWindow?
    private var hostLocalization: HostLocalizationSnapshot!
    private var storage: IsolatedTestStorage!
    private var accessibilityHandle: UnsafeMutableRawPointer?
    private var setAccessibilityAutomationEnabled: (@convention(c) (Int32) -> Void)?
    private var previousAccessibilityAutomationEnabled: Int32?

    override func setUp() async throws {
        hostLocalization = HostLocalizationSnapshot.capture()
        storage = try IsolatedTestStorage(prefix: "model-short-name")
        AppLocalization.shared.preference = "en"
        let handle = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW))
        accessibilityHandle = handle
        let isEnabled = unsafeBitCast(
            try XCTUnwrap(dlsym(handle, "_AXSAutomationEnabled")),
            to: (@convention(c) () -> Int32).self
        )
        let setEnabled = unsafeBitCast(
            try XCTUnwrap(dlsym(handle, "_AXSSetAutomationEnabled")),
            to: (@convention(c) (Int32) -> Void).self
        )
        setAccessibilityAutomationEnabled = setEnabled
        previousAccessibilityAutomationEnabled = isEnabled()
        setEnabled(1)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        if let previous = previousAccessibilityAutomationEnabled {
            setAccessibilityAutomationEnabled?(previous)
        }
        previousAccessibilityAutomationEnabled = nil
        setAccessibilityAutomationEnabled = nil
        if let handle = accessibilityHandle {
            dlclose(handle)
            accessibilityHandle = nil
        }
        hostLocalization.restore()
        hostLocalization.assertUnchanged()
        if let storage {
            self.storage = nil
            try storage.tearDown()
        }
    }

    func testComposerModelButtonShowsShortNameWithoutProviderPrefix() throws {
        let store = storage.storage
        try configureChatGPT(in: store)
        for provider in [ModelProvider.anthropic, .deepseek, .gemini] {
            try ModelKeys.save("sk-test-\(provider.rawValue)", for: provider, storage: store)
        }
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: store)

        let window = try show(
            ComposerInputView(
                input: .constant("Draft"),
                focused: .constant(true),
                adding: .constant(false),
                settingsPresented: .constant(false),
                running: false,
                send: { _, _ in },
                stop: {},
                openVoice: {}
            )
            .frame(width: 393, height: 180)
            .environment(app)
        )

        let uniqueCases: [(ModelProvider, String, String)] = [
            (.chatgpt, "gpt-6.1-terra", "6.1 Terra"),
            (.anthropic, "claude-sonnet-5-5", "Sonnet 5.5"),
            (.deepseek, "deepseek-flash", "V4.1 Flash"),
            (.gemini, "gemini-3.8-flash", "3.8 Flash"),
        ]
        for (provider, id, expectedShortName) in uniqueCases {
            ModelKeys.choose(provider, model: id, in: store)
            settle {
                self.accessibilityValue(identifier: "composer.settings.model", in: window) == expectedShortName
            }
            let shown = accessibilityValue(identifier: "composer.settings.model", in: window)
            XCTAssertEqual(shown, expectedShortName, "Provider \(provider.rawValue) model \(id) should show short name")
        }

        // Direct OpenAI alone (without ChatGPT or OpenRouter colliding) shows pure short name.
        try ModelKeys.removeChatGPTSignIn(storage: store)
        try ModelKeys.save("sk-test-openai", for: .openai, storage: store)
        ModelKeys.choose(.openai, model: "gpt-6.2-sol", in: store)
        settle {
            self.accessibilityValue(identifier: "composer.settings.model", in: window) == "6.2 Sol"
        }
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: window), "6.2 Sol")

        // OpenRouter alone (without OpenAI colliding) shows pure short name.
        ModelKeys.remove(.openai, storage: store)
        try ModelKeys.save("sk-test-openrouter", for: .openrouter, storage: store)
        ModelCatalog.set("openai/gpt-6.2-sol", on: true, for: .openrouter, notify: false, storage: store)
        ModelKeys.choose(.openrouter, model: "openai/gpt-6.2-sol", in: store)
        settle {
            self.accessibilityValue(identifier: "composer.settings.model", in: window) == "6.2 Sol"
        }
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: window), "6.2 Sol")

        // Single custom gateway provider drops its slash-delimited prefix.
        let workbuddy = CustomProviders.upsert(
            CustomProvider(
                name: "WorkBuddy",
                endpoints: [CustomEndpoint(url: "http://127.0.0.1:8767/v1")],
                model: "workbuddy/deepseek-v4.1-flash"
            ),
            storage: store
        )
        ModelKeys.choose(.custom, model: CustomProviders.choiceID(workbuddy.id, "workbuddy/deepseek-v4.1-flash"), in: store)
        settle {
            self.accessibilityValue(identifier: "composer.settings.model", in: window) == "v4.1-flash"
        }
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: window), "v4.1-flash")
    }

    func testClosedPillAndMenuSubtitleDistinguishDirectOpenAIAndOpenRouterSameModel() throws {
        let store = storage.storage
        try configureChatGPT(in: store)
        try ModelKeys.save("sk-test-openai", for: .openai, storage: store)
        try ModelKeys.save("sk-test-openrouter", for: .openrouter, storage: store)
        ModelCatalog.set("openai/gpt-6.2-sol", on: true, for: .openrouter, notify: false, storage: store)
        let office = CustomProviders.upsert(
            CustomProvider(name: "Office", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8765/v1")], model: "shared-model"),
            storage: store
        )
        let home = CustomProviders.upsert(
            CustomProvider(name: "Home", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8766/v1")], model: "shared-model"),
            storage: store
        )

        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: store)
        let bearPlace = CGRect(x: 161, y: 260, width: 80, height: 80)

        let composerWindow = try show(
            ComposerInputView(
                input: .constant("Draft"),
                focused: .constant(true),
                adding: .constant(false),
                settingsPresented: .constant(false),
                running: false,
                send: { _, _ in },
                stop: {},
                openVoice: {}
            )
            .frame(width: 393, height: 180)
            .environment(app)
        )

        // Direct OpenAI, OpenRouter, and ChatGPT all offer "6.2 Sol": closed pill and VoiceOver distinguish every account.
        ModelKeys.choose(.openai, model: "gpt-6.2-sol", in: store)
        settle { self.accessibilityValue(identifier: "composer.settings.model", in: composerWindow) == "6.2 Sol (OpenAI)" }
        XCTAssertEqual(accessibilityLabel(identifier: "composer.settings.model", in: composerWindow), "Model")
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: composerWindow), "6.2 Sol (OpenAI)")

        ModelKeys.choose(.openrouter, model: "openai/gpt-6.2-sol", in: store)
        settle { self.accessibilityValue(identifier: "composer.settings.model", in: composerWindow) == "6.2 Sol (OpenRouter)" }
        XCTAssertEqual(accessibilityLabel(identifier: "composer.settings.model", in: composerWindow), "Model")
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: composerWindow), "6.2 Sol (OpenRouter)")

        ModelKeys.choose(.chatgpt, model: "gpt-6.2-sol", in: store)
        settle { self.accessibilityValue(identifier: "composer.settings.model", in: composerWindow) == "6.2 Sol (ChatGPT)" }
        XCTAssertEqual(accessibilityLabel(identifier: "composer.settings.model", in: composerWindow), "Model")
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: composerWindow), "6.2 Sol (ChatGPT)")

        // Remove ChatGPT so OpenAI "6.1 Terra" is unique (not offered by OpenRouter) and keeps the bare short name.
        try ModelKeys.removeChatGPTSignIn(storage: store)
        ModelKeys.choose(.openai, model: "gpt-6.1-terra", in: store)
        settle { self.accessibilityValue(identifier: "composer.settings.model", in: composerWindow) == "6.1 Terra" }
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: composerWindow), "6.1 Terra")

        // Identical custom model across two custom providers disambiguates with the provider display name.
        ModelKeys.choose(.custom, model: CustomProviders.choiceID(home.id, "shared-model"), in: store)
        settle { self.accessibilityValue(identifier: "composer.settings.model", in: composerWindow) == "shared-model (Home)" }
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: composerWindow), "shared-model (Home)")

        ModelKeys.choose(.custom, model: CustomProviders.choiceID(office.id, "shared-model"), in: store)
        settle { self.accessibilityValue(identifier: "composer.settings.model", in: composerWindow) == "shared-model (Office)" }
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: composerWindow), "shared-model (Office)")

        // PokiMenu subtitle disambiguates colliding providers while grouped sections stay bare short names.
        ModelKeys.choose(.openrouter, model: "openai/gpt-6.2-sol", in: store)
        let menuWindow = try show(
            PokiFlight(
                status: PokiStatus(.ready),
                home: true,
                places: [.home: bearPlace],
                pokes: 0,
                tap: {},
                openModel: {},
                openCustomization: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(app)
        )
        settle { self.modelMenu(in: menuWindow)?.subtitle == "6.2 Sol (OpenRouter)" }
        XCTAssertEqual(modelMenu(in: menuWindow)?.subtitle, "6.2 Sol (OpenRouter)")
        XCTAssertEqual(groupActionTitles(in: menuWindow, group: "OpenAI"), ["6.1 Terra", "6.2 Sol"])
        XCTAssertEqual(groupActionTitles(in: menuWindow, group: "OpenRouter"), ["3.8 Flash", "Sonnet 5.5", "6.2 Sol"])
        XCTAssertEqual(groupActionTitles(in: menuWindow, group: "Office"), ["shared-model"])
        XCTAssertEqual(groupActionTitles(in: menuWindow, group: "Home"), ["shared-model"])

        ModelKeys.choose(.openai, model: "gpt-6.2-sol", in: store)
        settle { self.modelMenu(in: menuWindow)?.subtitle == "6.2 Sol (OpenAI)" }
        XCTAssertEqual(modelMenu(in: menuWindow)?.subtitle, "6.2 Sol (OpenAI)")

        // Once OpenRouter turns off "6.2 Sol", OpenAI "6.2 Sol" is unique again and drops the account suffix.
        ModelCatalog.set("openai/gpt-6.2-sol", on: false, for: .openrouter, notify: true, storage: store)
        settle { self.modelMenu(in: menuWindow)?.subtitle == "6.2 Sol" }
        XCTAssertEqual(modelMenu(in: menuWindow)?.subtitle, "6.2 Sol")
    }

    func testModelUsePickerCollapsedDisplayAndVoiceOverDistinguishSameNameModels() throws {
        try withLiveModelSnapshot {
            try ChatGPTAccount.save(
                OAuthCredentials(
                    refresh: "live-refresh",
                    access: "live-access",
                    expires: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                    clientId: "live-client"
                )
            )
            try ModelKeys.save("sk-live-openai", for: .openai)
            try ModelKeys.save("sk-live-openrouter", for: .openrouter)
            ModelCatalog.set("openai/gpt-6.2-sol", on: true, for: .openrouter, notify: false)
            let office = CustomProviders.upsert(
                CustomProvider(name: "Office", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8765/v1")], model: "shared-model")
            )
            let home = CustomProviders.upsert(
                CustomProvider(name: "Home", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8766/v1")], model: "shared-model")
            )

            // Grouped options stay bare short names inside each provider section.
            let chatGroups = Dictionary(uniqueKeysWithValues: ModelPicks.groups(.chat).map { ($0.name, $0.items.map(\.name)) })
            XCTAssertEqual(chatGroups["OpenAI"], ["6.1 Terra", "6.2 Sol"])
            XCTAssertEqual(chatGroups["OpenRouter"], ["3.8 Flash", "Sonnet 5.5", "6.2 Sol"])
            XCTAssertEqual(chatGroups["ChatGPT"], ["6.1 Terra", "6.2 Sol"])
            XCTAssertEqual(chatGroups["Office"], ["shared-model"])
            XCTAssertEqual(chatGroups["Home"], ["shared-model"])

            ModelPicks.pick(.account(.openai, "gpt-6.2-sol"), for: .chat)
            ModelPicks.pick(.account(.openai, "gpt-6.1-terra"), for: .decision)

            let settingsWindow = try show(
                NavigationStack {
                    ModelSettingsView()
                }
                .environment(\.locale, AppLocalization.locale)
            )
            settle { self.accessibilityElement(identifier: "models.use.chat", in: settingsWindow) != nil }

            @MainActor func collapsedSummary(_ identifier: String) throws -> (label: String?, value: String?, texts: [String]) {
                let element = try XCTUnwrap(accessibilityElement(identifier: identifier, in: settingsWindow), "Missing \(identifier)")
                return (element.accessibilityLabel, element.accessibilityValue, visibleTexts(in: element))
            }

            @MainActor func containsToken(_ token: String, in identifier: String) -> Bool {
                guard let element = accessibilityElement(identifier: identifier, in: settingsWindow) else { return false }
                let all = [element.accessibilityLabel, element.accessibilityValue].compactMap { $0 } + visibleTexts(in: element)
                return all.contains { $0.contains(token) }
            }

            // Collapsed Chat picker distinguishes direct OpenAI vs OpenRouter vs ChatGPT "6.2 Sol".
            settle { containsToken("6.2 Sol (OpenAI)", in: "models.use.chat") }
            let openAIChat = try collapsedSummary("models.use.chat")
            XCTAssertTrue(
                containsToken("6.2 Sol (OpenAI)", in: "models.use.chat"),
                "Collapsed Chat picker must distinguish OpenAI 6.2 Sol, got label=\(String(describing: openAIChat.label)) value=\(String(describing: openAIChat.value)) texts=\(openAIChat.texts)"
            )

            ModelPicks.pick(.account(.openrouter, "openai/gpt-6.2-sol"), for: .chat)
            settle { containsToken("6.2 Sol (OpenRouter)", in: "models.use.chat") }
            let openRouterChat = try collapsedSummary("models.use.chat")
            XCTAssertTrue(
                containsToken("6.2 Sol (OpenRouter)", in: "models.use.chat"),
                "Collapsed Chat picker must distinguish OpenRouter 6.2 Sol, got label=\(String(describing: openRouterChat.label)) value=\(String(describing: openRouterChat.value)) texts=\(openRouterChat.texts)"
            )

            ModelPicks.pick(.account(.chatgpt, "gpt-6.2-sol"), for: .chat)
            settle { containsToken("6.2 Sol (ChatGPT)", in: "models.use.chat") }
            let chatGPTChat = try collapsedSummary("models.use.chat")
            XCTAssertTrue(
                containsToken("6.2 Sol (ChatGPT)", in: "models.use.chat"),
                "Collapsed Chat picker must distinguish ChatGPT 6.2 Sol, got label=\(String(describing: chatGPTChat.label)) value=\(String(describing: chatGPTChat.value)) texts=\(chatGPTChat.texts)"
            )

            // Collapsed Chat picker distinguishes same-name custom providers.
            ModelPicks.pick(.account(.custom, CustomProviders.choiceID(home.id, "shared-model")), for: .chat)
            settle { containsToken("shared-model (Home)", in: "models.use.chat") }
            let homeChat = try collapsedSummary("models.use.chat")
            XCTAssertTrue(
                containsToken("shared-model (Home)", in: "models.use.chat"),
                "Collapsed Chat picker must distinguish Home custom provider, got label=\(String(describing: homeChat.label)) value=\(String(describing: homeChat.value)) texts=\(homeChat.texts)"
            )

            ModelPicks.pick(.account(.custom, CustomProviders.choiceID(office.id, "shared-model")), for: .chat)
            settle { containsToken("shared-model (Office)", in: "models.use.chat") }
            let officeChat = try collapsedSummary("models.use.chat")
            XCTAssertTrue(
                containsToken("shared-model (Office)", in: "models.use.chat"),
                "Collapsed Chat picker must distinguish Office custom provider, got label=\(String(describing: officeChat.label)) value=\(String(describing: officeChat.value)) texts=\(officeChat.texts)"
            )

            // Collapsed Decisions picker distinguishes colliding ChatGPT vs OpenAI "6.1 Terra" and keeps unique "6 Luna" bare.
            settle { containsToken("6.1 Terra (OpenAI)", in: "models.use.decision") }
            let openAIDecision = try collapsedSummary("models.use.decision")
            XCTAssertTrue(
                containsToken("6.1 Terra (OpenAI)", in: "models.use.decision"),
                "Collapsed Decisions picker must distinguish OpenAI 6.1 Terra, got label=\(String(describing: openAIDecision.label)) value=\(String(describing: openAIDecision.value)) texts=\(openAIDecision.texts)"
            )

            ModelPicks.pick(.account(.chatgpt, "gpt-6.1-terra"), for: .decision)
            settle { containsToken("6.1 Terra (ChatGPT)", in: "models.use.decision") }
            let chatGPTDecision = try collapsedSummary("models.use.decision")
            XCTAssertTrue(
                containsToken("6.1 Terra (ChatGPT)", in: "models.use.decision"),
                "Collapsed Decisions picker must distinguish ChatGPT 6.1 Terra, got label=\(String(describing: chatGPTDecision.label)) value=\(String(describing: chatGPTDecision.value)) texts=\(chatGPTDecision.texts)"
            )

            ModelPicks.pick(.account(.openai, AccountDecisions.luna), for: .decision)
            settle { containsToken("6 Luna", in: "models.use.decision") && !containsToken("(OpenAI)", in: "models.use.decision") }
            let lunaDecision = try collapsedSummary("models.use.decision")
            XCTAssertTrue(containsToken("6 Luna", in: "models.use.decision"), "Expected bare 6 Luna, got \(lunaDecision)")
            XCTAssertFalse(containsToken("(OpenAI)", in: "models.use.decision"), "Unique decision model must stay bare, got \(lunaDecision)")

            // Removing competing providers restores the bare short name on the collapsed Chat picker.
            ModelPicks.pick(.account(.openai, "gpt-6.2-sol"), for: .chat)
            try ModelKeys.removeChatGPTSignIn()
            ModelCatalog.set("openai/gpt-6.2-sol", on: false, for: .openrouter, notify: true)
            settle { containsToken("6.2 Sol", in: "models.use.chat") && !containsToken("(OpenAI)", in: "models.use.chat") }
            let uniqueChat = try collapsedSummary("models.use.chat")
            XCTAssertTrue(containsToken("6.2 Sol", in: "models.use.chat"), "Expected bare 6.2 Sol, got \(uniqueChat)")
            XCTAssertFalse(containsToken("(OpenAI)", in: "models.use.chat"), "Unique chat model must drop account suffix, got \(uniqueChat)")
        }
    }

    func testPokiMenuGroupsShowShortModelNamesForEveryProviderAndKeepStorageIDs() throws {
        let store = storage.storage
        try configureAllBuiltInProviders(in: store)
        for provider in [ModelProvider.chatgpt, .openai, .anthropic, .deepseek, .gemini, .openrouter] {
            for choice in provider.models(in: store) {
                ModelCatalog.set(choice.id, on: true, for: provider, notify: false, storage: store)
            }
        }
        store.defaults.set(["gpt-6.3-mini"], forKey: "models.listed.openai")
        ModelCatalog.set("gpt-6.3-mini", on: true, for: .openai, notify: false, storage: store)
        let firstCustom = CustomProviders.upsert(
            CustomProvider(name: "Office", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8765/v1")], model: "shared-model"),
            storage: store
        )
        let secondCustom = CustomProviders.upsert(
            CustomProvider(name: "Home", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8766/v1")], model: "shared-model"),
            storage: store
        )
        let workbuddy = CustomProviders.upsert(
            CustomProvider(name: "WorkBuddy", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8767/v1")], model: "workbuddy/deepseek-v4.1-flash"),
            storage: store
        )

        ModelKeys.choose(.chatgpt, model: "gpt-6.1-terra", in: store)
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: store)
        let bearPlace = CGRect(x: 161, y: 260, width: 80, height: 80)
        let window = try show(
            PokiFlight(
                status: PokiStatus(.ready),
                home: true,
                places: [.home: bearPlace],
                pokes: 0,
                tap: {},
                openModel: {},
                openCustomization: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(app)
        )

        settle { self.modelMenu(in: window) != nil }
        let menu = try XCTUnwrap(modelMenu(in: window))
        let groups = Dictionary(
            uniqueKeysWithValues: menu.children.compactMap { $0 as? UIMenu }.map { section in
                (section.title, section.children.compactMap { $0 as? UIAction })
            }
        )

        XCTAssertEqual(groups["ChatGPT"]?.map(\.title), ["6.1 Terra", "6.2 Sol", "6.2 Astra", "6.1 Sol"])
        XCTAssertEqual(groups["OpenAI"]?.map(\.title), ["6.1 Terra", "6.2 Sol", "6.2 Astra", "6.1 Sol", "6.3-mini"])
        XCTAssertEqual(groups["Anthropic"]?.map(\.title), ["Haiku 5.5", "Sonnet 5.5", "Opus 5.5"])
        XCTAssertEqual(groups["DeepSeek"]?.map(\.title), ["V4.1 Flash", "V4 Pro (no screenshots)"])
        XCTAssertEqual(groups["Gemini"]?.map(\.title), ["3.8 Flash", "4 Argon"])
        XCTAssertEqual(groups["OpenRouter"]?.map(\.title), ["3.8 Flash", "Sonnet 5.5", "Opus 5.5", "6.2 Sol", "6.1 Sol"])
        XCTAssertEqual(groups["Office"]?.map(\.title), ["shared-model"])
        XCTAssertEqual(groups["Home"]?.map(\.title), ["shared-model"])
        XCTAssertEqual(groups["WorkBuddy"]?.map(\.title), ["v4.1-flash"])

        // Picking identically named short labels under separate groups keeps distinct provider + ID storage.
        let openAITerra = try XCTUnwrap(groups["OpenAI"]?.first(where: { $0.title == "6.1 Terra" }))
        openAITerra.performWithSender(nil, target: nil)
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .openai)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "gpt-6.1-terra")

        let openRouterSol = try XCTUnwrap(groups["OpenRouter"]?.first(where: { $0.title == "6.2 Sol" }))
        openRouterSol.performWithSender(nil, target: nil)
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .openrouter)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "openai/gpt-6.2-sol")

        let chatGPTSol = try XCTUnwrap(groups["ChatGPT"]?.first(where: { $0.title == "6.2 Sol" }))
        chatGPTSol.performWithSender(nil, target: nil)
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .chatgpt)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "gpt-6.2-sol")

        let homeShared = try XCTUnwrap(groups["Home"]?.first(where: { $0.title == "shared-model" }))
        homeShared.performWithSender(nil, target: nil)
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .custom)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), CustomProviders.choiceID(secondCustom.id, "shared-model"))
        XCTAssertNotEqual(ModelKeys.selectedModel(in: store), CustomProviders.choiceID(firstCustom.id, "shared-model"))

        let workbuddyFlash = try XCTUnwrap(groups["WorkBuddy"]?.first(where: { $0.title == "v4.1-flash" }))
        workbuddyFlash.performWithSender(nil, target: nil)
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .custom)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), CustomProviders.choiceID(workbuddy.id, "workbuddy/deepseek-v4.1-flash"))

        // Multi-language consistency: zh-Hans, zh-Hant, en, and Japanese fallback (ja -> en).
        AppLocalization.shared.preference = "zh-Hans"
        ModelKeys.saved += 1
        settle {
            self.groupActionTitles(in: window, group: "DeepSeek") == ["V4.1 Flash", "V4 Pro（不支持截图）"]
        }
        XCTAssertEqual(groupActionTitles(in: window, group: "DeepSeek"), ["V4.1 Flash", "V4 Pro（不支持截图）"])
        XCTAssertEqual(groupActionTitles(in: window, group: "ChatGPT"), ["6.1 Terra", "6.2 Sol", "6.2 Astra", "6.1 Sol"])

        AppLocalization.shared.preference = "zh-Hant"
        ModelKeys.saved += 1
        settle {
            self.groupActionTitles(in: window, group: "DeepSeek") == ["V4.1 Flash", "V4 Pro（不支援截圖）"]
        }
        XCTAssertEqual(groupActionTitles(in: window, group: "DeepSeek"), ["V4.1 Flash", "V4 Pro（不支援截圖）"])
        XCTAssertEqual(groupActionTitles(in: window, group: "ChatGPT"), ["6.1 Terra", "6.2 Sol", "6.2 Astra", "6.1 Sol"])

        XCTAssertEqual(
            AppLocalization.resolve("system", supported: ["en", "zh-Hans", "zh-Hant"], preferred: ["ja-JP"]),
            "en"
        )
        AppLocalization.shared.preference = "ja"
        ModelKeys.saved += 1
        settle {
            self.groupActionTitles(in: window, group: "DeepSeek") == ["V4.1 Flash", "V4 Pro (no screenshots)"]
        }
        XCTAssertEqual(groupActionTitles(in: window, group: "DeepSeek"), ["V4.1 Flash", "V4 Pro (no screenshots)"])
        XCTAssertEqual(groupActionTitles(in: window, group: "ChatGPT"), ["6.1 Terra", "6.2 Sol", "6.2 Astra", "6.1 Sol"])
    }

    func testLegacySavedSelectionKeepsOriginalProviderModelIDAndAPIRequest() async throws {
        let store = storage.storage
        try configureChatGPT(in: store)
        try ModelKeys.save("sk-test-openrouter", for: .openrouter, storage: store)

        // Write legacy UserDefaults keys directly as previous releases saved them.
        store.defaults.set("chatgpt", forKey: "chat.provider")
        store.defaults.set("gpt-6.1-terra", forKey: "chat.model.chatgpt")
        store.defaults.set(["gpt-6.1-terra", "gpt-6.2-sol"], forKey: "models.enabled.chatgpt")

        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .chatgpt)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "gpt-6.1-terra")
        let chatGPTRequestModel = try XCTUnwrap(ModelProvider.chatgpt.piModel(ModelKeys.selectedModel(in: store), storage: store))
        XCTAssertEqual(chatGPTRequestModel.id, "gpt-6.1-terra")

        // Verify OpenRouter legacy ID and API model ID stay intact.
        store.defaults.set("openrouter", forKey: "chat.provider")
        store.defaults.set("anthropic/claude-sonnet-5.5", forKey: "chat.model.openrouter")
        XCTAssertEqual(ModelKeys.selectedProvider(in: store), .openrouter)
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "anthropic/claude-sonnet-5.5")
        let openRouterRequestModel = try XCTUnwrap(ModelProvider.openrouter.piModel(ModelKeys.selectedModel(in: store), storage: store))
        XCTAssertEqual(openRouterRequestModel.id, "anthropic/claude-sonnet-5.5")

        // Switch back to legacy ChatGPT selection and confirm UI renders short label while keeping IDs.
        store.defaults.set("chatgpt", forKey: "chat.provider")
        let isolatedApp = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: store)
        let window = try show(
            ComposerInputView(
                input: .constant("Hi"),
                focused: .constant(true),
                adding: .constant(false),
                settingsPresented: .constant(false),
                running: false,
                send: { _, _ in },
                stop: {},
                openVoice: {}
            )
            .frame(width: 393, height: 180)
            .environment(isolatedApp)
        )
        settle { self.accessibilityValue(identifier: "composer.settings.model", in: window) == "6.1 Terra" }
        XCTAssertEqual(accessibilityValue(identifier: "composer.settings.model", in: window), "6.1 Terra")
        XCTAssertEqual(ModelKeys.selectedModel(in: store), "gpt-6.1-terra")

        // End-to-end upgrade check: legacy UserDefaults keys select the original provider and send the
        // exact original model ID over the real ChatModel -> PiLoop -> URLSession request path.
        try await withLiveModelSnapshotAsync {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let suite = "ModelShortNameLegacy-\(UUID().uuidString)"
            let sessionDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let responsesSSE = [
                #"data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_legacy","role":"assistant"}}"#,
                #"data: {"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"OK"}"#,
                #"data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_legacy","role":"assistant","content":[{"type":"output_text","text":"OK"}]}}"#,
                #"data: {"type":"response.completed","response":{"status":"completed"}}"#,
            ].joined(separator: "\n\n") + "\n\n"

            ModelServerStub.clear()
            ModelServerStub.additionalHosts = ["api.openai.com"]
            ModelServerStub.responder = { request, _ in
                if request.url?.path.contains("/responses") == true {
                    return (200, "text/event-stream", responsesSSE)
                }
                return (200, "text/event-stream", FakeCompletions.text("OK"))
            }
            URLProtocol.registerClass(ModelServerStub.self)
            defer {
                URLProtocol.unregisterClass(ModelServerStub.self)
                ModelServerStub.clear()
                try? FileManager.default.removeItem(at: folder)
                sessionDefaults.removePersistentDomain(forName: suite)
            }

            let sessionStore = SessionStore(folder: folder, defaults: sessionDefaults)
            let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
            app.inProcessReadyForProbe()
            let chat = ChatModel(app: app, store: sessionStore)
            defer {
                chat.stop()
                app.stopSession()
            }

            @MainActor func sendAndCapture(marker: String) async throws -> ModelServerStub.Sent {
                ModelServerStub.recordedReset()
                chat.newConversation()
                chat.send(marker)
                let deadline = ContinuousClock.now + .seconds(10)
                while chat.running && ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(20))
                }
                XCTAssertFalse(chat.running, "Chat task did not finish for \(marker)")
                let matching = ModelServerStub.requests.filter {
                    let body = String(decoding: $0.body, as: UTF8.self)
                    return body.contains(marker) && !body.contains("You name chat conversations")
                }
                return try XCTUnwrap(matching.last, "Expected outgoing model request for \(marker), saw \(ModelServerStub.requests.map { $0.url?.absoluteString ?? "nil" })")
            }

            // 1. Legacy OpenAI + OpenRouter both offering "6.2 Sol": legacy OpenAI keeps provider & "gpt-6.2-sol".
            try ModelKeys.save("sk-live-openai", for: .openai)
            try ModelKeys.save("sk-live-openrouter", for: .openrouter)
            UserDefaults.standard.set("openai", forKey: "chat.provider")
            UserDefaults.standard.set("gpt-6.2-sol", forKey: "chat.model.openai")
            UserDefaults.standard.set(["gpt-6.1-terra", "gpt-6.2-sol"], forKey: "models.enabled.openai")
            UserDefaults.standard.set("openai/gpt-6.2-sol", forKey: "chat.model.openrouter")
            UserDefaults.standard.set(["openai/gpt-6.2-sol"], forKey: "models.enabled.openrouter")

            XCTAssertEqual(ModelKeys.selectedProvider, .openai)
            XCTAssertEqual(ModelKeys.selectedModel, "gpt-6.2-sol")
            XCTAssertEqual(ModelKeys.selectedShortModelName, "6.2 Sol (OpenAI)")
            let openAISent = try await sendAndCapture(marker: "Legacy OpenAI payload check")
            XCTAssertEqual(openAISent.url?.host(), "api.openai.com")
            XCTAssertEqual(openAISent.json["model"] as? String, "gpt-6.2-sol")

            // 2. Legacy OpenRouter selection keeps provider & "openai/gpt-6.2-sol" in outgoing JSON.
            UserDefaults.standard.set("openrouter", forKey: "chat.provider")
            XCTAssertEqual(ModelKeys.selectedProvider, .openrouter)
            XCTAssertEqual(ModelKeys.selectedModel, "openai/gpt-6.2-sol")
            XCTAssertEqual(ModelKeys.selectedShortModelName, "6.2 Sol (OpenRouter)")
            let openRouterSent = try await sendAndCapture(marker: "Legacy OpenRouter payload check")
            XCTAssertEqual(openRouterSent.url?.host(), "openrouter.ai")
            XCTAssertEqual(openRouterSent.json["model"] as? String, "openai/gpt-6.2-sol")

            // 3. Legacy single custom endpoint (chat.customURL + chat.customModel) migrates cleanly,
            // displays "v4.1-flash", and sends the full "workbuddy/deepseek-v4.1-flash" ID.
            UserDefaults.standard.removeObject(forKey: CustomProviders.storeKey)
            UserDefaults.standard.removeObject(forKey: CustomProviders.selectedKey)
            UserDefaults.standard.removeObject(forKey: "chat.model.custom")
            UserDefaults.standard.removeObject(forKey: "models.enabled.custom")
            UserDefaults.standard.set("custom", forKey: "chat.provider")
            UserDefaults.standard.set("https://model-server.test/v1", forKey: "chat.customURL")
            UserDefaults.standard.set("workbuddy/deepseek-v4.1-flash", forKey: "chat.customModel")

            XCTAssertEqual(ModelKeys.selectedProvider, .custom)
            XCTAssertEqual(ModelKeys.selectedShortModelName, "v4.1-flash")
            let customSent = try await sendAndCapture(marker: "Legacy custom payload check")
            XCTAssertEqual(customSent.url?.host(), "model-server.test")
            XCTAssertEqual(customSent.json["model"] as? String, "workbuddy/deepseek-v4.1-flash")
        }
    }

    func testComposerSheetModelUsesAndSettingsRowsUseShortDisplayNames() throws {
        let store = storage.storage
        try configureChatGPT(in: store)
        try ModelKeys.save("sk-test-deepseek", for: .deepseek, storage: store)
        try ModelKeys.save("sk-test-openrouter", for: .openrouter, storage: store)
        for choice in ModelProvider.deepseek.models(in: store) {
            ModelCatalog.set(choice.id, on: true, for: .deepseek, notify: false, storage: store)
        }
        ModelCatalog.set("openai/gpt-6.2-sol", on: true, for: .openrouter, notify: false, storage: store)
        let workbuddy = CustomProviders.upsert(
            CustomProvider(
                name: "WorkBuddy",
                endpoints: [CustomEndpoint(url: "http://127.0.0.1:8767/v1")],
                model: "workbuddy/deepseek-v4.1-flash"
            ),
            storage: store
        )
        let workbuddyChoiceID = CustomProviders.choiceID(workbuddy.id, "workbuddy/deepseek-v4.1-flash")
        ModelKeys.choose(.chatgpt, model: "gpt-6.1-terra", in: store)
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: store)
        let chat = ChatModel(app: app)
        defer { app.stopSession() }

        // 1. ComposerTaskSettings model picker sheet.
        let sheetWindow = try show(
            ComposerTaskSettings(
                kind: .model,
                approvalIconSize: 22,
                previewSelection: .constant(nil),
                openModelSetup: {}
            )
            .environment(app)
        )
        settle {
            self.accessibilityLabel(identifier: "composer.model.chatgpt.gpt-6.1-terra", in: sheetWindow) != nil
        }
        XCTAssertEqual(accessibilityLabel(identifier: "composer.model.chatgpt.gpt-6.1-terra", in: sheetWindow), "6.1 Terra")
        XCTAssertEqual(accessibilityLabel(identifier: "composer.model.deepseek.deepseek-flash", in: sheetWindow), "V4.1 Flash")
        XCTAssertEqual(accessibilityLabel(identifier: "composer.model.deepseek.deepseek-v4-pro", in: sheetWindow), "V4 Pro (no screenshots)")
        XCTAssertEqual(accessibilityLabel(identifier: "composer.model.openrouter.openai/gpt-6.2-sol", in: sheetWindow), "6.2 Sol")
        XCTAssertEqual(accessibilityLabel(identifier: "composer.model.custom.\(workbuddyChoiceID)", in: sheetWindow), "v4.1-flash")

        // 2. Settings home Models row (PokiDetailsView) for custom slash-prefixed and built-in ChatGPT models.
        ModelKeys.choose(.custom, model: workbuddyChoiceID, in: store)
        AppLocalization.shared.preference = "zh-Hans"
        let detailsWindow = try show(
            PokiDetailsView(openSetup: {}, path: .constant(NavigationPath()))
                .environment(app)
                .environment(chat)
                .environment(\.locale, AppLocalization.locale)
        )
        settle { self.accessibilityElement(identifier: "details.accountsAndModels", in: detailsWindow) != nil }
        let modelRow = try XCTUnwrap(accessibilityElement(identifier: "details.accountsAndModels", in: detailsWindow))
        let rowTexts = visibleTexts(in: modelRow)
        XCTAssertTrue(rowTexts.contains { $0.contains("模型") }, "Expected Settings Models title, got: \(rowTexts)")
        XCTAssertTrue(rowTexts.contains { $0.contains("v4.1-flash") }, "Expected short name without workbuddy/ prefix, got: \(rowTexts)")
        XCTAssertFalse(rowTexts.contains { $0.contains("workbuddy/") }, "Provider prefix must not appear on Settings Models row, got: \(rowTexts)")

        ModelKeys.choose(.chatgpt, model: "gpt-6.1-terra", in: store)
        settle {
            guard let row = self.accessibilityElement(identifier: "details.accountsAndModels", in: detailsWindow) else { return false }
            return self.visibleTexts(in: row).contains { $0.contains("6.1 Terra") }
        }
        let updatedRow = try XCTUnwrap(accessibilityElement(identifier: "details.accountsAndModels", in: detailsWindow))
        let updatedTexts = visibleTexts(in: updatedRow)
        XCTAssertTrue(updatedTexts.contains { $0.contains("6.1 Terra") }, "Expected short built-in model name, got: \(updatedTexts)")
        XCTAssertFalse(updatedTexts.contains { $0.contains("ChatGPT GPT-") }, "Provider prefix must not appear on Settings Models row, got: \(updatedTexts)")

        // 3. ModelUses (ModelPicks, ProviderUseValue, ModelTickList) and SetupSections on live settings storage.
        AppLocalization.shared.preference = "en"
        try withLiveModelSnapshot {
            try ChatGPTAccount.save(
                OAuthCredentials(
                    refresh: "live-refresh",
                    access: "live-access",
                    expires: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                    clientId: "live-client"
                )
            )
            try ModelKeys.save("sk-live-openai", for: .openai)
            try ModelKeys.save("sk-live-openrouter", for: .openrouter)
            ModelCatalog.set("openai/gpt-6.2-sol", on: true, for: .openrouter, notify: false)
            let liveWorkbuddy = CustomProviders.upsert(
                CustomProvider(
                    name: "WorkBuddy",
                    endpoints: [CustomEndpoint(url: "http://127.0.0.1:8767/v1")],
                    model: "workbuddy/deepseek-v4.1-flash"
                )
            )
            let liveCustomID = CustomProviders.choiceID(liveWorkbuddy.id, "workbuddy/deepseek-v4.1-flash")
            UserDefaults.standard.set(["workbuddy/deepseek-v4.1-flash"], forKey: "models.listed.custom.\(liveWorkbuddy.id.uuidString)")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "models.listedAt.custom.\(liveWorkbuddy.id.uuidString)")
            defer {
                UserDefaults.standard.removeObject(forKey: "models.listed.custom.\(liveWorkbuddy.id.uuidString)")
                UserDefaults.standard.removeObject(forKey: "models.listedAt.custom.\(liveWorkbuddy.id.uuidString)")
            }

            let chatGroups = Dictionary(uniqueKeysWithValues: ModelPicks.groups(.chat).map { ($0.name, $0.items.map(\.name)) })
            XCTAssertEqual(chatGroups["ChatGPT"], ["6.1 Terra", "6.2 Sol"])
            XCTAssertEqual(chatGroups["OpenAI"], ["6.1 Terra", "6.2 Sol"])
            XCTAssertEqual(chatGroups["OpenRouter"], ["3.8 Flash", "Sonnet 5.5", "6.2 Sol"])
            XCTAssertEqual(chatGroups["WorkBuddy"], ["v4.1-flash"])

            let decisionGroups = Dictionary(uniqueKeysWithValues: ModelPicks.groups(.decision).map { ($0.name, $0.items.map(\.name)) })
            XCTAssertEqual(decisionGroups["OpenAI"], ["6 Luna", "6.1 Terra"])

            let voiceGroups = Dictionary(uniqueKeysWithValues: ModelPicks.groups(.voice).map { ($0.name, $0.items.map(\.name)) })
            XCTAssertEqual(voiceGroups["OpenAI"], ["GPT-Live 1.1"])

            ModelPicks.pick(.account(.custom, liveCustomID), for: .chat)
            XCTAssertEqual(ProviderUseValue.text(.chat, for: .custom(liveWorkbuddy.id)), "v4.1-flash")
            XCTAssertEqual(ModelKeys.selectedModel, liveCustomID)

            ModelPicks.pick(.account(.openai, "gpt-6.2-sol"), for: .chat)
            XCTAssertEqual(ProviderUseValue.text(.chat, for: .account(.openai)), "6.2 Sol")
            XCTAssertEqual(ModelKeys.selectedModel, "gpt-6.2-sol")

            ModelPicks.pick(.account(.openrouter, "openai/gpt-6.2-sol"), for: .chat)
            XCTAssertEqual(ProviderUseValue.text(.chat, for: .account(.openrouter)), "6.2 Sol")
            XCTAssertEqual(ModelKeys.selectedModel, "openai/gpt-6.2-sol")

            // ModelTickList for ChatGPT shows short names without "ChatGPT GPT-".
            let tickWindow = try show(
                NavigationStack {
                    ModelTickList(use: .chat, provider: .account(.chatgpt))
                }
                .environment(\.locale, AppLocalization.locale)
            )
            settle { self.visibleTexts(in: tickWindow).contains("6.2 Sol") }
            let tickTexts = visibleTexts(in: tickWindow)
            XCTAssertTrue(tickTexts.contains { $0.contains("6.1 Terra") }, "Expected short name in ChatGPT ModelTickList, got: \(tickTexts)")
            XCTAssertTrue(tickTexts.contains("6.2 Sol"), "Expected short name in ChatGPT ModelTickList, got: \(tickTexts)")
            XCTAssertFalse(tickTexts.contains { $0.contains("ChatGPT GPT-") }, "Provider prefix must not appear in ModelTickList, got: \(tickTexts)")

            // ModelTickList for custom provider drops slash-delimited gateway prefix.
            let customTickWindow = try show(
                NavigationStack {
                    ModelTickList(use: .chat, provider: .custom(liveWorkbuddy.id))
                }
                .environment(\.locale, AppLocalization.locale)
            )
            settle { self.visibleTexts(in: customTickWindow).contains { $0.contains("v4.1-flash") } }
            let customTickTexts = visibleTexts(in: customTickWindow)
            XCTAssertTrue(customTickTexts.contains { $0.contains("v4.1-flash") }, "Expected short name in custom ModelTickList, got: \(customTickTexts)")
            XCTAssertFalse(customTickTexts.contains { $0.contains("workbuddy/") }, "Provider prefix must not appear in custom ModelTickList, got: \(customTickTexts)")

            // ModelTickList for Voice keeps Realtime model labels intact.
            let voiceTickWindow = try show(
                NavigationStack {
                    ModelTickList(use: .voice, provider: .account(.openai))
                }
                .environment(\.locale, AppLocalization.locale)
            )
            settle { self.visibleTexts(in: voiceTickWindow).contains("GPT-Live 1.1") }
            let voiceTickTexts = visibleTexts(in: voiceTickWindow)
            XCTAssertTrue(voiceTickTexts.contains("GPT-Live 1.1"), "Expected Voice model label unchanged, got: \(voiceTickTexts)")
            XCTAssertTrue(voiceTickTexts.contains("GPT Realtime 2.1"), "Expected Voice model label unchanged, got: \(voiceTickTexts)")

            // SetupSections (WelcomePanel) Accounts row displays short name when ChatGPT is configured alone.
            ModelKeys.remove(.openai)
            ModelKeys.remove(.openrouter)
            CustomProviders.remove(liveWorkbuddy.id)
            ModelKeys.choose(.chatgpt, model: "gpt-6.1-terra", in: .live)
            let setupWindow = try show(
                NavigationStack {
                    List {
                        SetupSections(path: .constant(NavigationPath()))
                    }
                }
                .environment(app)
                .environment(\.locale, AppLocalization.locale)
            )
            settle { self.accessibilityElement(identifier: "firstRun.models", in: setupWindow) != nil }
            let accountsRow = try XCTUnwrap(accessibilityElement(identifier: "firstRun.models", in: setupWindow))
            let accountsTexts = visibleTexts(in: accountsRow)
            XCTAssertTrue(accountsTexts.contains { $0.contains("6.1 Terra") }, "Expected short name on Setup Accounts row, got: \(accountsTexts)")
            XCTAssertFalse(accountsTexts.contains { $0.contains("ChatGPT GPT-") }, "Provider prefix must not appear on Setup Accounts row, got: \(accountsTexts)")
        }
    }

    func testShortDisplayNameEdgeCasesAndMultiCustomSelection() throws {
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "o4-mini"), "o4-mini")
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "GPT-"), "GPT-")
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "openai/gpt-6.2-sol"), "6.2-sol")
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "anthropic/claude-opus-5-6"), "opus-5-6")
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "google/gemini-4.0-pro"), "4.0-pro")
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "deepseek/deepseek-reasoner"), "reasoner")
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "workbuddy/deepseek-v4.1-flash"), "v4.1-flash")
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "workbuddy/qwen3-coder"), "qwen3-coder")
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "workbuddy/"), "workbuddy/")
        XCTAssertEqual(ChatModelChoice.stripProviderPrefix(from: "Model A / Model B"), "Model A / Model B")

        let store = storage.storage
        let first = CustomProviders.upsert(
            CustomProvider(name: "Office", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8765/v1")], model: "shared-model"),
            storage: store
        )
        ModelKeys.choose(.custom, model: CustomProviders.choiceID(first.id, "shared-model"), in: store)
        XCTAssertEqual(ModelKeys.selectedModelName(in: store), "shared-model")
        XCTAssertEqual(ModelKeys.selectedShortModelName(in: store), "shared-model")

        let second = CustomProviders.upsert(
            CustomProvider(name: "Home", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8766/v1")], model: "shared-model"),
            storage: store
        )
        ModelKeys.choose(.custom, model: CustomProviders.choiceID(second.id, "shared-model"), in: store)
        XCTAssertEqual(ModelKeys.selectedModelName(in: store), "shared-model (Home)")
        XCTAssertEqual(ModelKeys.selectedShortModelName(in: store), "shared-model (Home)")
        XCTAssertNotEqual(first.id, second.id)

        let uniqueCustom = CustomProviders.upsert(
            CustomProvider(name: "WorkBuddy", endpoints: [CustomEndpoint(url: "http://127.0.0.1:8767/v1")], model: "workbuddy/qwen3-coder"),
            storage: store
        )
        ModelKeys.choose(.custom, model: CustomProviders.choiceID(uniqueCustom.id, "workbuddy/qwen3-coder"), in: store)
        XCTAssertEqual(ModelKeys.selectedShortModelName(in: store), "qwen3-coder")
    }

    // MARK: Helpers

    private func configureChatGPT(in store: PokiStorage) throws {
        try ChatGPTAccount.save(
            OAuthCredentials(
                refresh: "test-refresh",
                access: "test-access",
                expires: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                clientId: "test-client"
            ),
            service: store.keychainService
        )
    }

    private func configureAllBuiltInProviders(in store: PokiStorage) throws {
        try configureChatGPT(in: store)
        for provider in [ModelProvider.openai, .anthropic, .deepseek, .gemini, .openrouter] {
            try ModelKeys.save("sk-test-\(provider.rawValue)", for: provider, storage: store)
        }
    }

    private static let liveSnapshotKeys = [
        "pokiChat", "chatEngine",
        "custom.providers", "chat.customProvider", "chat.customURL", "chat.customModel", "chat.provider",
        "chat.model.chatgpt", "chat.model.openai", "chat.model.openrouter", "chat.model.custom",
        "models.enabled.chatgpt", "models.enabled.openai", "models.enabled.openrouter", "models.enabled.custom",
        "models.introduced.chatgpt", "models.introduced.openai", "models.introduced.openrouter",
        "models.listed.openai", "models.listed.openrouter", "models.listed.custom", "models.revision.custom",
        "decisions.offered.chatgpt", "decisions.offered.openai", "decisions.offered.openrouter", "decisions.offered.custom",
        "quickFixes.choice", "quickFixes.account.provider", "quickFixes.account.model",
    ]

    private func captureLiveModelSnapshot() -> (defaults: [String: Any], keys: [ModelProvider: String]) {
        var savedDefaults: [String: Any] = [:]
        for key in Self.liveSnapshotKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        let savedProviders: [ModelProvider] = [.chatgpt, .openai, .anthropic, .deepseek, .gemini, .openrouter]
        var savedKeys: [ModelProvider: String] = [:]
        for provider in savedProviders {
            if let existing = ModelKeys.key(provider) {
                savedKeys[provider] = existing
            }
            ModelKeys.remove(provider)
        }
        return (savedDefaults, savedKeys)
    }

    private func restoreLiveModelSnapshot(_ snapshot: (defaults: [String: Any], keys: [ModelProvider: String])) {
        for custom in CustomProviders.all { CustomProviders.remove(custom.id) }
        for key in Self.liveSnapshotKeys {
            if let previous = snapshot.defaults[key] {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let savedProviders: [ModelProvider] = [.chatgpt, .openai, .anthropic, .deepseek, .gemini, .openrouter]
        for provider in savedProviders {
            if let previous = snapshot.keys[provider] {
                try? ModelKeys.save(previous, for: provider)
            } else {
                ModelKeys.remove(provider)
            }
        }
    }

    private func withLiveModelSnapshot(_ body: @MainActor () throws -> Void) throws {
        let snapshot = captureLiveModelSnapshot()
        defer { restoreLiveModelSnapshot(snapshot) }
        try body()
    }

    private func withLiveModelSnapshotAsync(_ body: @MainActor () async throws -> Void) async throws {
        let snapshot = captureLiveModelSnapshot()
        defer { restoreLiveModelSnapshot(snapshot) }
        try await body()
    }

    private func modelMenu(in window: UIWindow) -> UIMenu? {
        guard let button = menuButton(in: window, identifier: "home.poki"),
              let menu = button.menu else { return nil }
        return flattenMenuElements(menu).first(where: { $0.accessibilityIdentifier == "status.model" }) as? UIMenu
    }

    private func groupActionTitles(in window: UIWindow, group: String) -> [String]? {
        guard let menu = modelMenu(in: window),
              let section = menu.children.compactMap({ $0 as? UIMenu }).first(where: { $0.title == group }) else {
            return nil
        }
        return section.children.compactMap { ($0 as? UIAction)?.title }
    }

    private func show(_ view: some View) throws -> UIWindow {
        window?.isHidden = true
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let next = UIWindow(windowScene: scene)
        next.frame = scene.screen.bounds
        next.rootViewController = UIHostingController(rootView: view.environment(\.accessibilityEnabled, true))
        next.makeKeyAndVisible()
        next.layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: next.rootViewController?.view)
        self.window = next
        return next
    }

    private func settle(for seconds: TimeInterval = 2, until done: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func menuButton(in root: UIView, identifier: String) -> UIButton? {
        if let button = root as? UIButton,
           button.showsMenuAsPrimaryAction,
           button.accessibilityIdentifier == identifier {
            return button
        }
        for subview in root.subviews {
            if let found = menuButton(in: subview, identifier: identifier) { return found }
        }
        return nil
    }

    private func flattenMenuElements(_ menu: UIMenu) -> [UIMenuElement] {
        var result: [UIMenuElement] = []
        for child in menu.children {
            result.append(child)
            if let submenu = child as? UIMenu {
                result.append(contentsOf: flattenMenuElements(submenu))
            }
        }
        return result
    }

    private func accessibilityElement(identifier: String, in root: NSObject) -> NSObject? {
        var pending = [root]
        var visited = Set<ObjectIdentifier>()
        let selector = NSSelectorFromString("accessibilityIdentifier")
        while let item = pending.popLast() {
            guard visited.insert(ObjectIdentifier(item)).inserted else { continue }
            let id = item.responds(to: selector) ? item.perform(selector)?.takeUnretainedValue() as? String : nil
            if id == identifier { return item }
            if let view = item as? UIView { pending.append(contentsOf: view.subviews) }
            if let children = item.accessibilityElements {
                pending.append(contentsOf: children.compactMap { $0 as? NSObject })
            }
            let count = item.accessibilityElementCount()
            if count > 0 && count < 1000 {
                for index in 0..<count {
                    if let child = item.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        return nil
    }

    private func accessibilityValue(identifier: String, in root: NSObject) -> String? {
        accessibilityElement(identifier: identifier, in: root)?.accessibilityValue
    }

    private func accessibilityLabel(identifier: String, in root: NSObject) -> String? {
        accessibilityElement(identifier: identifier, in: root)?.accessibilityLabel
    }

    private func visibleTexts(in root: NSObject) -> [String] {
        var pending = [root]
        var visited = Set<ObjectIdentifier>()
        var result: [String] = []
        while let item = pending.popLast() {
            guard visited.insert(ObjectIdentifier(item)).inserted else { continue }
            if let label = item.accessibilityLabel, !label.isEmpty { result.append(label) }
            if let uiLabel = item as? UILabel, let text = uiLabel.text, !text.isEmpty { result.append(text) }
            if let view = item as? UIView { pending.append(contentsOf: view.subviews) }
            if let children = item.accessibilityElements {
                pending.append(contentsOf: children.compactMap { $0 as? NSObject })
            }
            let count = item.accessibilityElementCount()
            if count > 0 && count < 1000 {
                for index in 0..<count {
                    if let child = item.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        return result
    }
}
