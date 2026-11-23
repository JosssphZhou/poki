import XCTest
import PiSwiftAI
@testable import Poki

/// OpenCode Go is a Models-page account, like the other providers the README lists.
/// Requests stay offline: ModelServerStub answers opencode.ai.
@MainActor
final class OpenCodeGoProviderTests: XCTestCase {
    private let key = "placeholder-go-key"
    private let session = "11111111-1111-1111-1111-111111111111"
    private var language = AppLocalization.system
    private var savedDefaults: [String: Any] = [:]
    private var savedKey: String?
    private let defaultsKeys = [
        "chat.provider",
        "chat.model.opencode-go",
        "models.listed.opencode-go",
        "models.enabled.opencode-go",
    ]

    override func setUp() {
        ModelServerStub.clear()
        URLProtocol.registerClass(ModelServerStub.self)
        language = AppLocalization.shared.preference
        AppLocalization.shared.preference = "en"
        savedKey = ModelKeys.key(.opencodeGo)
        savedDefaults = [:]
        for name in defaultsKeys {
            if let value = UserDefaults.standard.object(forKey: name) { savedDefaults[name] = value }
            UserDefaults.standard.removeObject(forKey: name)
        }
        ModelKeys.remove(.opencodeGo)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(ModelServerStub.self)
        ModelServerStub.clear()
        AppLocalization.shared.preference = language
        for name in defaultsKeys {
            if let value = savedDefaults[name] { UserDefaults.standard.set(value, forKey: name) }
            else { UserDefaults.standard.removeObject(forKey: name) }
        }
        if let savedKey { try? ModelKeys.save(savedKey, for: .opencodeGo) }
        else { ModelKeys.remove(.opencodeGo) }
    }

    func testModelsPageListsOpenCodeGoWithTheOtherAccounts() {
        XCTAssertEqual(ModelProvider.allCases.map(\.name), [
            "Anthropic", "OpenAI", "ChatGPT", "DeepSeek", "Gemini", "OpenRouter", "OpenCode Go", "Custom Endpoint",
        ])
        XCTAssertEqual(ModelProvider.opencodeGo.rawValue, "opencode-go")
        XCTAssertEqual(ModelProvider.opencodeGo.piProvider, "opencode-go")
        XCTAssertTrue(ModelProvider.opencodeGo.wired)
        XCTAssertFalse(ModelProvider.opencodeGo.signsIn)
        XCTAssertEqual(ModelAccounts.method(.opencodeGo), "API key")
        XCTAssertTrue(ModelAccounts.canChat(.opencodeGo))
        XCTAssertFalse(ModelAccounts.canTalkLive(.opencodeGo))
        XCTAssertEqual(
            ModelProvider.opencodeGo.keyHelp,
            "Subscribe to OpenCode Go at opencode.ai, then copy its API key from the OpenCode Console. Models and available regions depend on your Go plan and privacy settings."
        )
        XCTAssertEqual(ModelProvider.opencodeGo.models.map(\.id), [
            "deepseek-v4.1-flash", "kimi-k3", "gpt-5.6-luna", "glm-5.2",
        ])
        XCTAssertTrue(ModelCatalog.defaults(.opencodeGo).contains("deepseek-v4.1-flash"))
        XCTAssertEqual(ModelCatalog.available(.opencodeGo).map(\.id), ["deepseek-v4.1-flash"])
    }

    func testRoutesUseEachModelsGoAPIPath() throws {
        func routed(_ id: String) throws -> Model {
            try XCTUnwrap(ModelProvider.opencodeGo.piModel(id), "Missing Go model \(id)")
        }
        let openAI = "https://opencode.ai/inference/go/openai/v1"
        let flash = try routed("deepseek-v4.1-flash")
        XCTAssertEqual(flash.provider, "opencode-go")
        XCTAssertEqual(flash.api, .openAICompletions)
        XCTAssertEqual(flash.baseUrl, openAI)
        XCTAssertEqual(try routed("kimi-k3").api, .openAICompletions)
        XCTAssertEqual(try routed("glm-5.2").baseUrl, openAI)
        let luna = try routed("gpt-5.6-luna")
        XCTAssertEqual(luna.api, .openAIResponses)
        XCTAssertEqual(luna.baseUrl, openAI)
        XCTAssertEqual(try routed("claude-haiku-5-5").api, .anthropicMessages)
        XCTAssertEqual(try routed("claude-haiku-5-5").baseUrl, "https://opencode.ai/inference/go/anthropic")
        XCTAssertEqual(try routed("gemini-4-argon").api, .googleGenerativeAI)
        XCTAssertEqual(try routed("gemini-4-argon").baseUrl, "https://opencode.ai/inference/go/google/v1beta")
        XCTAssertNil(ModelProvider.opencodeGo.piModel("no-such-go-model"))
        let auth = PiLoop.openCodeGoAuth(model: try XCTUnwrap(ModelProvider.opencodeGo.piModel("claude-haiku-5-5")), apiKey: key)
        XCTAssertEqual(auth.apiKey, key)
        XCTAssertEqual(auth.headers?["Authorization"] ?? nil, "Bearer \(key)")
        let completions = PiLoop.openCodeGoAuth(model: try XCTUnwrap(ModelProvider.opencodeGo.piModel("deepseek-v4.1-flash")), apiKey: key)
        XCTAssertNil(completions.headers)
    }

    func testConnectionCheckAndChatSendTheSessionHeaderOnGoPaths() async throws {
        // A rejected key is enough: the request is what Go checks, and no stream has to parse.
        ModelServerStub.answer = (401, #"{"error":{"message":"Invalid credential"}}"#)

        ModelKeys.selectedProvider = .opencodeGo
        ModelKeys.selectedModel = "deepseek-v4.1-flash"
        _ = await ConnectionCheck.run(.opencodeGo, key: key)
        let flashSent = try XCTUnwrap(ModelServerStub.requests.first)
        XCTAssertEqual(flashSent.url?.absoluteString, "https://opencode.ai/inference/go/openai/v1/chat/completions")
        XCTAssertEqual(flashSent.request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
        assertGoHeaders(flashSent.request, sessionIsUUID: true)

        ModelServerStub.recordedReset()
        ModelCatalog.set("gpt-5.6-luna", on: true, for: .opencodeGo)
        ModelKeys.selectedModel = "gpt-5.6-luna"
        _ = await ConnectionCheck.run(.opencodeGo, key: key)
        let lunaSent = try XCTUnwrap(ModelServerStub.requests.first)
        XCTAssertEqual(lunaSent.url?.absoluteString, "https://opencode.ai/inference/go/openai/v1/responses")
        assertGoHeaders(lunaSent.request, sessionIsUUID: true)

        ModelServerStub.recordedReset()
        ModelCatalog.set("claude-haiku-5-5", on: true, for: .opencodeGo)
        ModelKeys.selectedModel = "claude-haiku-5-5"
        _ = await ConnectionCheck.run(.opencodeGo, key: key)
        let haikuSent = try XCTUnwrap(ModelServerStub.requests.first)
        XCTAssertEqual(haikuSent.url?.absoluteString, "https://opencode.ai/inference/go/anthropic/v1/messages")
        XCTAssertEqual(haikuSent.request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
        XCTAssertNil(haikuSent.request.value(forHTTPHeaderField: "x-api-key"))
        assertGoHeaders(haikuSent.request, sessionIsUUID: true)

        ModelServerStub.recordedReset()
        try ModelKeys.save(key, for: .opencodeGo)
        let model = try XCTUnwrap(ModelProvider.opencodeGo.piModel("deepseek-v4.1-flash"))
        let loop = PiLoop(provider: .opencodeGo, model: model, tools: [], sessionID: session) { _ in
            .init(text: "", jpeg: nil, isError: false)
        }
        _ = await loop.run("Reply with OK.", instructions: "Be brief.", maxTurns: 1) { _ in }
        let chatSent = try XCTUnwrap(ModelServerStub.requests.last)
        XCTAssertEqual(chatSent.url?.path, "/inference/go/openai/v1/chat/completions")
        XCTAssertEqual(chatSent.request.value(forHTTPHeaderField: "x-opencode-session"), session)
        XCTAssertEqual(chatSent.request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
        XCTAssertEqual(chatSent.request.value(forHTTPHeaderField: "User-Agent"), OpenCodeGoClient.userAgent)
        XCTAssertEqual(chatSent.request.value(forHTTPHeaderField: "x-opencode-client"), "Poki")
    }

    func testModelListKeepsOnlyCataloguedGoModels() async throws {
        try ModelKeys.save(key, for: .opencodeGo)
        ModelServerStub.answer = (200, #"{"data":[{"id":"deepseek-v4.1-flash"},{"id":"kimi-k3"},{"id":"not-a-go-model"}]}"#)
        let count = try await ModelCatalog.refresh(.opencodeGo)
        XCTAssertEqual(count, 2)
        let sent = try XCTUnwrap(ModelServerStub.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://opencode.ai/inference/go/v1/models")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "User-Agent"), OpenCodeGoClient.userAgent)
        XCTAssertEqual(ModelCatalog.listed(.opencodeGo).map(\.id), ["deepseek-v4.1-flash", "kimi-k3"])
    }

    private func assertGoHeaders(_ request: URLRequest, sessionIsUUID: Bool) {
        let session = request.value(forHTTPHeaderField: "x-opencode-session")
        if sessionIsUUID { XCTAssertNotNil(session.flatMap(UUID.init(uuidString:))) }
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), OpenCodeGoClient.userAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-opencode-client"), "Poki")
    }
}
