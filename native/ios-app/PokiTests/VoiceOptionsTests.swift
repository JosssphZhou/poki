import XCTest
@testable import Poki

@MainActor
final class VoiceOptionsTests: XCTestCase {
    private var isolated: IsolatedTestStorage!
    private var hostLocalization: HostLocalizationSnapshot!

    override func setUp() async throws {
        isolated = try IsolatedTestStorage(prefix: "voice-options")
        hostLocalization = HostLocalizationSnapshot.capture()
    }

    override func tearDown() async throws {
        hostLocalization?.restore()
        hostLocalization?.assertUnchanged()
        try isolated?.tearDown()
    }

    private func runCodexStartVoice(in storage: PokiStorage) async throws -> String? {
        var emit: (@MainActor (String) -> Void)?
        var sent: [[String: Any]] = []
        func push(_ payload: [String: Any]) {
            guard let bytes = try? JSONSerialization.data(withJSONObject: payload) else { return }
            let text = String(decoding: bytes, as: UTF8.self)
            Task { @MainActor in emit?(text) }
        }
        let codex = CodexVoice(
            startBridge: { _, next in
                emit = next
                return true
            },
            sendBridge: { text in
                guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return false }
                sent.append(object)
                guard let method = object["method"] as? String, let id = object["id"] else { return true }
                switch method {
                case "account/read":
                    push(["id": id, "result": ["account": ["type": "chatgpt"]]])
                case "thread/start":
                    push(["id": id, "result": ["thread": ["id": "thr-voice-test"]]])
                case "thread/realtime/start":
                    push(["id": id, "result": [:]])
                    push(["method": "thread/realtime/sdp", "params": ["threadId": "thr-voice-test", "sdp": "sdp-answer"]])
                default:
                    push(["id": id, "result": [:]])
                }
                return true
            },
            storage: storage
        )
        defer { codex.stop() }
        try await codex.prepare(onEvent: { _, _ in }, onTool: { _, _ in ("ok", false, nil) })
        let answer = try await codex.start(offer: "v=0")
        XCTAssertEqual(answer, "sdp-answer")
        let realtimeStart = try XCTUnwrap(sent.first { $0["method"] as? String == "thread/realtime/start" })
        let params = try XCTUnwrap(realtimeStart["params"] as? [String: Any])
        return params["voice"] as? String
    }

    private func sessionVoice(in storage: PokiStorage) -> String? {
        let session = VoiceDirect.session(in: storage)
        return ((session["audio"] as? [String: Any])?["output"] as? [String: Any])?["voice"] as? String
    }

    func testRealtimeAPIOfficialVoicesMatchSpecification() {
        let options = LiveVoiceRoute.realtimeAPI.options
        XCTAssertEqual(
            options.map(\.rawValue),
            ["marin", "cedar", "alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse"]
        )
        XCTAssertEqual(LiveVoiceRoute.realtimeAPI.defaultVoice, .marin)
    }

    func testChatGPTOfficialVoicesMatchCodexV3Specification() {
        let options = LiveVoiceRoute.chatgpt.options
        XCTAssertEqual(
            options.map(\.rawValue),
            ["cove", "juniper", "maple", "spruce", "ember", "vale", "breeze", "arbor", "sol"]
        )
        XCTAssertEqual(LiveVoiceRoute.chatgpt.defaultVoice, .cove)
    }

    func testLocalizedVoiceNamesAndPersonalitiesCoverAllLanguagesWithoutBannedPunctuation() {
        let bannedSymbols = ["——", "—", "§", "·", "•", "・"]
        let uiKeys: [String.LocalizationValue] = [
            "Speaking Voice",
            "Choose Voice",
            "Changes apply to your next voice conversation.",
            "Poki uses this ChatGPT sign-in for live voice when ChatGPT is selected as your chat account. Choose from ChatGPT’s official voices.",
        ]

        var englishNames: [LiveVoiceOption: String] = [:]
        var englishTraits: [LiveVoiceOption: String] = [:]
        AppLocalization.shared.preference = "en"
        XCTAssertEqual(AppLocalization.text("Speaking Voice"), "Voice")
        XCTAssertEqual(AppLocalization.text("Choose Voice"), "Choose Voice")
        for option in LiveVoiceOption.allCases {
            englishNames[option] = option.displayName
            englishTraits[option] = option.personality
            XCTAssertFalse(option.displayName.isEmpty, option.rawValue)
            XCTAssertFalse(option.personality.isEmpty, option.rawValue)
            for symbol in bannedSymbols {
                XCTAssertFalse(option.displayName.contains(symbol), "\(option.rawValue) en name has \(symbol)")
                XCTAssertFalse(option.personality.contains(symbol), "\(option.rawValue) en trait has \(symbol)")
            }
        }
        for key in uiKeys {
            let text = AppLocalization.text(LocalizedStringResource(key))
            XCTAssertFalse(text.isEmpty)
            for symbol in bannedSymbols {
                XCTAssertFalse(text.contains(symbol), "en UI key has \(symbol): \(text)")
            }
        }

        for language in ["zh-Hans", "zh-Hant"] {
            AppLocalization.shared.preference = language
            XCTAssertEqual(AppLocalization.text("Speaking Voice"), "音色", language)
            XCTAssertEqual(AppLocalization.text("Voice"), language == "zh-Hans" ? "语音" : "語音", "existing Voice key must remain unchanged")
            XCTAssertEqual(LiveVoiceOption.ember.displayName, language == "zh-Hans" ? "余烬（Ember）" : "餘燼（Ember）", language)
            for option in LiveVoiceOption.allCases {
                let name = option.displayName
                let trait = option.personality
                let englishName = englishNames[option] ?? ""
                let englishTrait = englishTraits[option] ?? ""
                XCTAssertFalse(name.isEmpty, "\(option.rawValue) \(language)")
                XCTAssertFalse(trait.isEmpty, "\(option.rawValue) \(language)")
                XCTAssertNotEqual(name, englishName, "\(option.rawValue) \(language) name should be localized")
                XCTAssertTrue(name.contains(englishName), "\(option.rawValue) \(language) name should keep official name \(englishName): \(name)")
                XCTAssertNotEqual(trait, englishTrait, "\(option.rawValue) \(language) personality should be localized")
                for symbol in bannedSymbols {
                    XCTAssertFalse(name.contains(symbol), "\(option.rawValue) \(language) name has \(symbol)")
                    XCTAssertFalse(trait.contains(symbol), "\(option.rawValue) \(language) trait has \(symbol)")
                }
            }
            for key in uiKeys {
                let text = AppLocalization.text(LocalizedStringResource(key))
                XCTAssertFalse(text.isEmpty, language)
                for symbol in bannedSymbols {
                    XCTAssertFalse(text.contains(symbol), "\(language) UI key has \(symbol): \(text)")
                }
            }
        }
    }

    func testVoiceSelectionPersistsPerRouteAndSurvivesSettingsVaultRestoration() throws {
        let storage = isolated.storage
        XCTAssertEqual(VoiceCatalog.voice(for: .realtimeAPI, in: storage), .marin)
        XCTAssertEqual(VoiceCatalog.voice(for: .chatgpt, in: storage), .cove)

        VoiceCatalog.setVoice(.coral, for: .realtimeAPI, in: storage)
        VoiceCatalog.setVoice(.juniper, for: .chatgpt, in: storage)
        XCTAssertEqual(VoiceCatalog.voice(for: .realtimeAPI, in: storage), .coral)
        XCTAssertEqual(VoiceCatalog.voice(for: .chatgpt, in: storage), .juniper)
        XCTAssertEqual(storage.defaults.string(forKey: LiveVoiceRoute.realtimeAPI.storageKey), "coral")
        XCTAssertEqual(storage.defaults.string(forKey: LiveVoiceRoute.chatgpt.storageKey), "juniper")

        let vaultBackup = try Keychain.read("settings.v1")
        let origRealtime = UserDefaults.standard.object(forKey: LiveVoiceRoute.realtimeAPI.storageKey)
        let origChatGPT = UserDefaults.standard.object(forKey: LiveVoiceRoute.chatgpt.storageKey)
        defer {
            if let origRealtime { UserDefaults.standard.set(origRealtime, forKey: LiveVoiceRoute.realtimeAPI.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: LiveVoiceRoute.realtimeAPI.storageKey) }
            if let origChatGPT { UserDefaults.standard.set(origChatGPT, forKey: LiveVoiceRoute.chatgpt.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: LiveVoiceRoute.chatgpt.storageKey) }
            if let vaultBackup { try? Keychain.write(vaultBackup, account: "settings.v1") }
            else { Keychain.delete("settings.v1") }
        }

        VoiceCatalog.setVoice(.sage, for: .realtimeAPI, in: .live)
        VoiceCatalog.setVoice(.maple, for: .chatgpt, in: .live)
        SettingsVault.save()
        UserDefaults.standard.removeObject(forKey: LiveVoiceRoute.realtimeAPI.storageKey)
        UserDefaults.standard.removeObject(forKey: LiveVoiceRoute.chatgpt.storageKey)
        SettingsVault.restore()
        XCTAssertEqual(VoiceCatalog.voice(for: .realtimeAPI, in: .live), .sage)
        XCTAssertEqual(VoiceCatalog.voice(for: .chatgpt, in: .live), .maple)
    }

    func testInvalidOrCrossRouteValuesFallBackSmoothlyToValidRouteDefaults() {
        let storage = isolated.storage

        XCTAssertEqual(VoiceCatalog.resolve("  CORAL ", for: .realtimeAPI), .coral)
        XCTAssertEqual(VoiceCatalog.resolve(" Juniper ", for: .chatgpt), .juniper)
        XCTAssertEqual(VoiceCatalog.resolve("cove", for: .realtimeAPI), .marin)
        XCTAssertEqual(VoiceCatalog.resolve("onyx", for: .realtimeAPI), .marin)
        XCTAssertEqual(VoiceCatalog.resolve("", for: .realtimeAPI), .marin)
        XCTAssertEqual(VoiceCatalog.resolve(nil, for: .realtimeAPI), .marin)
        XCTAssertEqual(VoiceCatalog.resolve("marin", for: .chatgpt), .cove)
        XCTAssertEqual(VoiceCatalog.resolve("coral", for: .chatgpt), .cove)
        XCTAssertEqual(VoiceCatalog.resolve("legacy-invalid", for: .chatgpt), .cove)
        XCTAssertEqual(VoiceCatalog.resolve(nil, for: .chatgpt), .cove)

        for bad in ["cove", "juniper", "onyx", "fable", ""] {
            storage.defaults.set(bad, forKey: LiveVoiceRoute.realtimeAPI.storageKey)
            XCTAssertEqual(VoiceCatalog.voice(for: .realtimeAPI, in: storage), .marin, bad)
        }
        for bad in ["marin", "alloy", "coral", "nova", ""] {
            storage.defaults.set(bad, forKey: LiveVoiceRoute.chatgpt.storageKey)
            XCTAssertEqual(VoiceCatalog.voice(for: .chatgpt, in: storage), .cove, bad)
        }

        VoiceCatalog.setVoice(.juniper, for: .realtimeAPI, in: storage)
        XCTAssertEqual(storage.defaults.string(forKey: LiveVoiceRoute.realtimeAPI.storageKey), "marin")
        VoiceCatalog.setVoice(.coral, for: .chatgpt, in: storage)
        XCTAssertEqual(storage.defaults.string(forKey: LiveVoiceRoute.chatgpt.storageKey), "cove")
    }

    func testSwitchingAuthMethodsRoutesAndEmitsIsolatedVoices() async throws {
        let storage = isolated.storage
        try ModelKeys.save("sk-openai-test", for: .openai, storage: storage)
        ModelKeys.setSelectedProvider(.openai, in: storage)
        VoiceDirect.set(.openai, on: true, storage: storage)
        VoiceCatalog.setVoice(.coral, for: .realtimeAPI, in: storage)

        let voiceModel = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { _, _, _ in ("", false, nil) },
            codex: CodexVoice(storage: storage),
            storage: storage
        )

        XCTAssertFalse(voiceModel.usesChatGPTSubscription)
        XCTAssertEqual(VoiceDirect.account(in: storage), .openai)
        XCTAssertEqual(sessionVoice(in: storage), "coral")

        let custom = CustomProvider(name: "Gateway", endpoints: [CustomEndpoint(url: "https://example.com/v1")], model: "gpt-realtime-2.1", liveVoice: true)
        CustomProviders.upsert(custom, storage: storage)
        VoiceDirect.set(.custom(custom.id), on: true, storage: storage)
        XCTAssertFalse(voiceModel.usesChatGPTSubscription)
        XCTAssertEqual(VoiceDirect.account(in: storage), .custom(custom.id))
        XCTAssertEqual(sessionVoice(in: storage), "coral")

        try isolated.seedCodexCredential()
        ModelKeys.setSelectedProvider(.chatgpt, in: storage)
        XCTAssertTrue(voiceModel.usesChatGPTSubscription)
        let defaultChatGPTVoice = try await runCodexStartVoice(in: storage)
        XCTAssertEqual(defaultChatGPTVoice, "cove")

        VoiceCatalog.setVoice(.breeze, for: .chatgpt, in: storage)
        let selectedChatGPTVoice = try await runCodexStartVoice(in: storage)
        XCTAssertEqual(selectedChatGPTVoice, "breeze")

        ModelKeys.setSelectedProvider(.openai, in: storage)
        XCTAssertFalse(voiceModel.usesChatGPTSubscription)
        XCTAssertEqual(sessionVoice(in: storage), "coral")
    }

    func testVoiceDirectSessionUsesSelectedVoiceAndFallsBackWhenInvalid() throws {
        let storage = isolated.storage
        try ModelKeys.save("sk-openai-test", for: .openai, storage: storage)
        VoiceDirect.set(.openai, on: true, storage: storage)

        XCTAssertEqual(sessionVoice(in: storage), "marin")

        VoiceCatalog.setVoice(.ballad, for: .realtimeAPI, in: storage)
        XCTAssertEqual(sessionVoice(in: storage), "ballad")

        let custom = CustomProvider(name: "CustomRT", endpoints: [CustomEndpoint(url: "https://custom.example.com/v1")], model: "gpt-realtime-2.1", liveVoice: true)
        CustomProviders.upsert(custom, storage: storage)
        VoiceDirect.set(.custom(custom.id), on: true, storage: storage)
        XCTAssertEqual(sessionVoice(in: storage), "ballad")

        storage.defaults.set("juniper", forKey: LiveVoiceRoute.realtimeAPI.storageKey)
        XCTAssertEqual(sessionVoice(in: storage), "marin")
    }

    func testExchangeLiveOfferSendsSelectedVoiceAndSanitizesUnsupportedValues() async throws {
        URLProtocol.registerClass(OpenAIStub.self)
        defer { URLProtocol.unregisterClass(OpenAIStub.self) }
        let storage = isolated.storage

        func capturedVoice() -> String? {
            ((OpenAIStub.session?["audio"] as? [String: Any])?["output"] as? [String: Any])?["voice"] as? String
        }

        _ = try await VoiceDirect.exchangeLiveOffer("offer", model: "gpt-live-1.1", apiKey: "sk-test", storage: storage)
        XCTAssertEqual(capturedVoice(), "marin")

        VoiceCatalog.setVoice(.sage, for: .realtimeAPI, in: storage)
        _ = try await VoiceDirect.exchangeLiveOffer("offer", model: "gpt-live-1.1", apiKey: "sk-test", storage: storage)
        XCTAssertEqual(capturedVoice(), "sage")

        storage.defaults.set("cove", forKey: LiveVoiceRoute.realtimeAPI.storageKey)
        _ = try await VoiceDirect.exchangeLiveOffer("offer", model: "gpt-live-1.1", apiKey: "sk-test", storage: storage)
        XCTAssertEqual(capturedVoice(), "marin")

        storage.defaults.set("onyx", forKey: LiveVoiceRoute.realtimeAPI.storageKey)
        _ = try await VoiceDirect.exchangeLiveOffer("offer", model: "gpt-live-1.1", apiKey: "sk-test", storage: storage)
        XCTAssertEqual(capturedVoice(), "marin")
    }

    func testCodexVoiceStartSendsSelectedChatGPTVoiceAndSanitizesUnsupportedValues() async throws {
        let storage = isolated.storage
        try isolated.seedCodexCredential()

        let defaultVoice = try await runCodexStartVoice(in: storage)
        XCTAssertEqual(defaultVoice, "cove")

        VoiceCatalog.setVoice(.juniper, for: .chatgpt, in: storage)
        let selectedVoice = try await runCodexStartVoice(in: storage)
        XCTAssertEqual(selectedVoice, "juniper")

        storage.defaults.set("marin", forKey: LiveVoiceRoute.chatgpt.storageKey)
        let fallbackVoice = try await runCodexStartVoice(in: storage)
        XCTAssertEqual(fallbackVoice, "cove")
    }
}
