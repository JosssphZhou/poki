import Foundation
import PiSwiftAI
import XCTest
@testable import Poki

@MainActor
final class ChatModelRouteTests: XCTestCase {
    func testToolContinuationAndRetryKeepTheCapturedProfile() async throws {
        let profiles = ProfileStorage().open()
        let first = try await profiles.authorize(nil) { _ in grant("oaiapp_a") }
        let second = try await profiles.authorize(nil) { _ in grant("oaiapp_b") }
        let previous = UserDefaults.standard.object(forKey: "chat.chatGPTProfile")
        defer { UserDefaults.standard.set(previous, forKey: "chat.chatGPTProfile") }
        UserDefaults.standard.set(first.id.uuidString, forKey: "chat.chatGPTProfile")

        let recorder = TurnRecorder()
        let model = try XCTUnwrap(ModelProvider.chatgpt.piModel("gpt-6.1-sol"))
        let selection = ModelSelection(provider: .chatgpt, modelID: model.id, profileID: first.id)
        let route = ModelRoute(selection: selection, model: model, key: nil)
        let tool = ToolSpec(name: "fixture", description: "Offline fixture", schema: ["type": "object"])
        let loop = PiLoop(route: route, tools: [tool], profiles: profiles, stream: { model, _, options in
            let count = await recorder.record(options.apiKey)
            if count == 1 {
                return reply(model, [.toolCall(PiSwiftAI.ToolCall(id: "fixture-call", name: "fixture", arguments: [:]))], reason: .toolUse)
            }
            return reply(model)
        }) { _ in
            UserDefaults.standard.set(second.id.uuidString, forKey: "chat.chatGPTProfile")
            do {
                _ = try await profiles.signOut(first.id, remove: true) { _ in XCTFail("No revocation while a run is active"); return true }
                XCTFail("Active account removal must wait")
            } catch ChatGPTOAuth.Failure.accountBusy {} catch { XCTFail("Unexpected account state") }
            return .init(text: "fixture result", jpeg: nil, isError: false)
        }

        let result = await loop.run("fixture question", instructions: "fixture instructions", maxTurns: 5) { _ in }
        XCTAssertEqual(result, .done)
        let retry = await loop.run("fixture retry", instructions: "fixture instructions", maxTurns: 5) { _ in }
        XCTAssertEqual(retry, .done)
        let recorded = await recorder.keys
        XCTAssertEqual(recorded, Array(repeating: first.credentials?.access, count: 3))

        let otherRoute = ModelRoute(selection: .init(provider: .chatgpt, modelID: model.id, profileID: second.id), model: model, key: nil)
        XCTAssertFalse(route.sameAccount(as: otherRoute))
        let otherLoop = PiLoop(route: otherRoute, tools: [], profiles: profiles, stream: { model, _, options in
            _ = await recorder.record(options.apiKey)
            return reply(model)
        }) { _ in .init(text: "", jpeg: nil, isError: true) }
        let resultB = await otherLoop.run("new message", instructions: "fixture instructions", maxTurns: 5) { _ in }
        XCTAssertEqual(resultB, .done)
        let otherKeys = await recorder.keys
        XCTAssertEqual(otherKeys.last, second.credentials?.access)

        _ = try await profiles.signOut(first.id, remove: true) { _ in true }
        let afterRemoval = await loop.run("should never stream", instructions: "fixture instructions", maxTurns: 5) { _ in }
        guard case .failed = afterRemoval else { return XCTFail("Removed profile must fail closed") }
        let requestCount = await recorder.keys.count
        XCTAssertEqual(requestCount, 4)
    }

    func testStoppingDuringToolDoesNotStartAnotherRequest() async throws {
        let profiles = ProfileStorage().open()
        let first = try await profiles.authorize(nil) { _ in grant("oaiapp_a") }
        let model = try XCTUnwrap(ModelProvider.chatgpt.piModel("gpt-6.1-sol"))
        let route = ModelRoute(selection: .init(provider: .chatgpt, modelID: model.id, profileID: first.id), model: model, key: nil)
        let recorder = TurnRecorder()
        let tool = ToolSpec(name: "fixture", description: "Offline fixture", schema: ["type": "object"])
        let handle = LoopHandle()
        let loop = PiLoop(route: route, tools: [tool], profiles: profiles, stream: { model, _, options in
            _ = await recorder.record(options.apiKey)
            return reply(model, [.toolCall(PiSwiftAI.ToolCall(id: "fixture-call", name: "fixture", arguments: [:]))], reason: .toolUse)
        }) { _ in
            handle.loop?.stop()
            return .init(text: "fixture result", jpeg: nil, isError: false)
        }
        handle.loop = loop
        let result = await loop.run("fixture question", instructions: "fixture instructions", maxTurns: 5) { _ in }
        XCTAssertEqual(result, .stopped)
        let requests = await recorder.keys
        XCTAssertEqual(requests, [first.credentials?.access])
    }

    func testSavedSelectionCannotSendChatGPTTokenToAnotherProviderOrHost() async throws {
        let profiles = ProfileStorage().open()
        let account = try await profiles.authorize(nil) { _ in grant("oaiapp_a") }
        let model = try XCTUnwrap(ModelProvider.chatgpt.piModel("gpt-6.1-sol"))
        let mismatched = ModelSelection(provider: .custom, modelID: model.id, profileID: account.id)
        XCTAssertNil(mismatched.route)
        let custom = ModelRoute(selection: mismatched, model: model.with(baseUrl: "https://example.invalid/v1"), key: "fixture-key")
        let customToken = await custom.accessToken(profiles: profiles)
        XCTAssertNil(customToken)
        let selection = ModelSelection(provider: .chatgpt, modelID: model.id, profileID: account.id)
        let changedHost = ModelRoute(selection: selection, model: model.with(baseUrl: "https://example.invalid/v1"), key: nil)
        let changedHostToken = await changedHost.accessToken(profiles: profiles)
        XCTAssertNil(changedHostToken)
    }

    func testMenuFormatsSubscriptionAndAPIAccountsConsistently() {
        let profile = ChatGPTProfile(id: UUID(), number: 2, clientID: "oaiapp_fixture", label: "ChatGPT Demo B")
        XCTAssertEqual(ModelProvider.chatgpt.menuAccountName(profile), "ChatGPT · Demo B")
        XCTAssertEqual(ModelProvider.deepseek.menuAccountName(), "DeepSeek · API key")
        XCTAssertEqual(ModelProvider.chatgpt.removingProviderPrefix(from: "GPT-6.1 Terra"), "GPT-6.1 Terra")
        XCTAssertEqual(ModelProvider.deepseek.removingProviderPrefix(from: "DeepSeek V4.1 Flash"), "V4.1 Flash")
    }

    func testSessionSelectionRoundTripsAndOldTranscriptStillDecodes() throws {
        let selection = ModelSelection(provider: .chatgpt, modelID: "gpt-6.1-sol", profileID: UUID())
        let now = Date()
        var saved = SavedSession(id: "fixture", kind: .poki, title: "Fixture", started: now, updated: now,
                                 live: false, entries: [], calls: [])
        let old = try JSONEncoder().encode(saved)
        XCTAssertNil(try JSONDecoder().decode(SavedSession.self, from: old).modelSelection)
        saved.modelSelection = selection
        let encoded = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(SavedSession.self, from: encoded).modelSelection, selection)
        XCTAssertTrue(selection.sameAccount(as: .init(provider: .chatgpt, modelID: "gpt-6.1-terra", profileID: selection.profileID)))
        XCTAssertFalse(selection.sameAccount(as: .init(provider: .openai, modelID: "gpt-6.1-sol")))
    }
}

@MainActor
private final class LoopHandle { weak var loop: PiLoop? }

private actor TurnRecorder {
    private(set) var keys: [String?] = []
    func record(_ key: String?) -> Int {
        keys.append(key)
        return keys.count
    }
}

private func reply(_ model: Model, _ content: [ContentBlock] = [.text(TextContent(text: "fixture reply"))],
                   reason: StopReason = .stop) -> AssistantMessageEventStream {
    let stream = AssistantMessageEventStream()
    let message = AssistantMessage(content: content, api: model.api, provider: model.provider, model: model.id,
                                   usage: Usage(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0), stopReason: reason)
    stream.push(.done(reason: reason, message: message))
    stream.end(message)
    return stream
}
