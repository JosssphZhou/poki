import Foundation
import PiSwiftAI
import XCTest
@testable import Poki

@MainActor
final class ModelProfilesTests: XCTestCase {
    func testEveryWiredAPIProviderKeepsTwoIndependentConnections() throws {
        let fixture = ConnectionStorage()
        let store = fixture.open()
        for provider in ModelProvider.allCases where provider != .chatgpt && provider != .custom {
            let a = try store.save(nil, provider: provider, label: "Work", key: "fixture-a")
            let b = try store.save(nil, provider: provider, label: "Personal", key: "fixture-b")
            XCTAssertNotEqual(a.id, b.id)
            let model = try XCTUnwrap(store.available(a.id).first)
            let selection = ModelSelection(provider: provider, modelID: model.id, profileID: a.id)
            let route = try XCTUnwrap(selection.route(in: store))
            XCTAssertEqual(route.key, "fixture-a")
            try store.rename(a.id, to: "Research")
            _ = try store.save(a.id, provider: provider, label: "Research", key: "fixture-replacement")
            XCTAssertEqual(store.profile(b.id)?.key, "fixture-b")
            XCTAssertEqual(store.profile(a.id)?.id, a.id)
            XCTAssertEqual(route.key, "fixture-a")
            try store.remove(a.id)
            XCTAssertNil(selection.route(in: store))
            XCTAssertEqual(store.profile(b.id)?.key, "fixture-b")
        }
        XCTAssertEqual(fixture.open().all.count, 5)
    }

    func testAtomicMigrationRetriesWithoutDestroyingLegacyAndDoesNotResurrectDeletedProfiles() throws {
        let fixture = ConnectionStorage()
        fixture.legacy[.openai] = "legacy-openai"
        fixture.legacy[.deepseek] = "legacy-deepseek"
        fixture.defaults.set("https://fixture.invalid/v1", forKey: "chat.customURL")
        fixture.defaults.set("fixture-model", forKey: "chat.customModel")
        fixture.defaults.set(["gpt-6.1-sol"], forKey: "models.enabled.openai")
        fixture.failWrite = true
        XCTAssertThrowsError(try fixture.open().load())
        XCTAssertNil(fixture.data)
        XCTAssertEqual(fixture.legacy[.openai], "legacy-openai")
        fixture.failWrite = false
        let store = fixture.open()
        let records = try store.load()
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(try store.load().map(\.id), records.map(\.id))
        let custom = try XCTUnwrap(records.first { $0.provider == .custom })
        XCTAssertEqual(custom.endpoint, "https://fixture.invalid/v1")
        XCTAssertEqual(store.available(custom.id).map(\.id), ["fixture-model"])
        let openai = try XCTUnwrap(records.first { $0.provider == .openai })
        XCTAssertEqual(store.available(openai.id).map(\.id), ["gpt-6.1-sol"])
        fixture.failWrite = true
        XCTAssertThrowsError(try store.remove(openai.id))
        XCTAssertEqual(store.profile(openai.id)?.key, "legacy-openai")
        fixture.failWrite = false
        try store.remove(openai.id)
        XCTAssertNil(fixture.open().profile(openai.id))
        XCTAssertNil(fixture.legacy[.openai])
    }

    func testPerProfileModelListsAndEnabledStatesDoNotLeak() async throws {
        let fixture = ConnectionStorage(); let store = fixture.open()
        let a = try store.save(nil, provider: .openai, label: "A", key: "a")
        let b = try store.save(nil, provider: .openai, label: "B", key: "b")
        try await store.refresh(a.id) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer a")
            return response(request, #"{"data":[{"id":"gpt-6.1-sol"}]}"#)
        }
        try await store.refresh(b.id) { request in response(request, #"{"data":[{"id":"gpt-6.1-terra"}]}"#) }
        try store.setModel("gpt-6.1-sol", enabled: true, profileID: a.id)
        XCTAssertEqual(store.available(a.id).map(\.id), ["gpt-6.1-sol"])
        XCTAssertEqual(store.available(b.id).map(\.id), ["gpt-6.1-terra"])
        try store.setModel("gpt-6.1-sol", enabled: false, profileID: a.id)
        XCTAssertTrue(store.available(a.id).isEmpty)
        XCTAssertEqual(store.available(b.id).count, 1)
        do {
            try await store.refresh(a.id) { request in
                _ = try store.save(a.id, provider: .openai, label: "A", key: "changed")
                return response(request, #"{"data":[{"id":"gpt-obsolete"}]}"#)
            }
            XCTFail("A stale response must not overwrite new credentials")
        } catch ModelProfiles.Failure.changed {}
        XCTAssertNil(store.profile(a.id)?.listed)
    }

    func testCustomEndpointsCaptureURLKeyAndModelTogether() async throws {
        let store = ConnectionStorage().open()
        let a = try store.save(nil, provider: .custom, label: "Local", key: nil, endpoint: "http://127.0.0.1:19001/v1", model: "local-a")
        let b = try store.save(nil, provider: .custom, label: "Gateway", key: "b", endpoint: "https://gateway.invalid/v1", model: "remote-b")
        let selection = ModelSelection(provider: .custom, modelID: "local-a", profileID: a.id)
        let route = try XCTUnwrap(selection.route(in: store))
        _ = try store.save(a.id, provider: .custom, label: "Moved", key: "new", endpoint: "http://127.0.0.1:19002/v1", model: "local-new")
        XCTAssertEqual(route.model.baseUrl, "http://127.0.0.1:19001/v1")
        XCTAssertEqual(route.model.id, "local-a")
        let key = await route.accessToken(profiles: store.chatGPT, connections: store)
        XCTAssertEqual(key, "none")
        XCTAssertEqual(store.profile(b.id)?.customModel, "remote-b")
        XCTAssertThrowsError(try store.save(a.id, provider: .custom, label: "Bad", key: nil, endpoint: "https://user:secret@host.invalid/v1", model: "x"))
        XCTAssertEqual(store.profile(a.id)?.customModel, "local-new")
    }

    func testProviderAuthenticationHeadersStayCorrect() throws {
        let anthropic = try XCTUnwrap(ModelCatalog.request(.anthropic, key: "fixture"))
        XCTAssertEqual(anthropic.value(forHTTPHeaderField: "x-api-key"), "fixture")
        XCTAssertNil(anthropic.value(forHTTPHeaderField: "Authorization"))
        let gemini = try XCTUnwrap(ModelCatalog.request(.gemini, key: "fixture"))
        XCTAssertEqual(URLComponents(url: gemini.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "key" }?.value, "fixture")
        let custom = try XCTUnwrap(ModelCatalog.request(.custom, key: nil, endpoint: "http://127.0.0.1:19001/v1"))
        XCTAssertEqual(custom.url?.absoluteString, "http://127.0.0.1:19001/v1/models")
        XCTAssertNil(custom.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(ModelCatalog.request(.chatgpt, key: "fixture"))
    }

    func testExplicitSelectionRestoresAndDeletedSelectionDoesNotPickAnotherAccount() throws {
        let fixture = ConnectionStorage(); let store = fixture.open()
        let a = try store.save(nil, provider: .openai, label: "A", key: "a")
        _ = try store.save(nil, provider: .openai, label: "B", key: "b")
        let selection = ModelSelection(provider: .openai, modelID: "gpt-6.1-terra", profileID: a.id)
        try store.select(selection)
        XCTAssertEqual(fixture.open().defaultSelection, selection)
        let data = try JSONEncoder().encode(selection)
        XCTAssertEqual(try JSONDecoder().decode(ModelSelection.self, from: data), selection)
        try store.remove(a.id)
        XCTAssertEqual(store.defaultSelection.profileID, a.id)
        XCTAssertNil(store.defaultSelection.route(in: store))
    }

    func testAPIToolContinuationUsesCapturedRouteAfterEditingAndSwitching() async throws {
        let store = ConnectionStorage().open()
        let a = try store.save(nil, provider: .custom, label: "A", key: "fixture-a", endpoint: "http://127.0.0.1:19001/v1", model: "fixture-model")
        let b = try store.save(nil, provider: .custom, label: "B", key: "fixture-b", endpoint: "http://127.0.0.1:19002/v1", model: "other")
        let route = try XCTUnwrap(ModelSelection(provider: .custom, modelID: "fixture-model", profileID: a.id).route(in: store))
        let recorder = TurnRecorder()
        let loop = PiLoop(route: route, tools: [.init(name: "fixture", description: "fixture", schema: ["type": "object"])], connections: store, stream: { model, _, options in
            XCTAssertEqual(model.baseUrl, "http://127.0.0.1:19001/v1")
            let count = await recorder.record(options.apiKey)
            if count == 1 { return reply(model, [.toolCall(.init(id: "call", name: "fixture", arguments: [:]))], reason: .toolUse) }
            return reply(model)
        }) { _ in
            do { _ = try store.save(a.id, provider: .custom, label: "A", key: "new", endpoint: "http://127.0.0.1:19003/v1", model: "changed") }
            catch { XCTFail("\(error)") }
            store.choose(b.id)
            return .init(text: "done", jpeg: nil, isError: false)
        }
        let outcome = await loop.run("offline", instructions: "offline", maxTurns: 3) { _ in }
        XCTAssertEqual(outcome, .done)
        let keys = await recorder.keys
        XCTAssertEqual(keys, ["fixture-a", "fixture-a"])
    }

    func testInvalidIdentityUnavailableModelAndCrossProviderSelectionFailClosed() throws {
        let store = ConnectionStorage().open()
        let a = try store.save(nil, provider: .openai, label: "A", key: "fixture")
        XCTAssertNil(ModelSelection(provider: .anthropic, modelID: "claude-haiku-5-5", profileID: a.id).route(in: store))
        XCTAssertNil(ModelSelection(provider: .openai, modelID: "unavailable", profileID: a.id).route(in: store))
        XCTAssertNil(ModelSelection(provider: .openai, modelID: "gpt-6.1-terra", profileID: UUID()).route(in: store))
        XCTAssertThrowsError(try store.save(a.id, provider: .deepseek, label: "A", key: "replacement"))
        XCTAssertEqual(store.profile(a.id)?.key, "fixture")
    }
}

@MainActor
private final class ConnectionStorage {
    var data: Data?
    var legacy: [ModelProvider: String] = [:]
    var failWrite = false
    let defaults: UserDefaults
    private let suite = UUID().uuidString
    init() { defaults = UserDefaults(suiteName: suite)! }
    deinit { defaults.removePersistentDomain(forName: suite) }
    func open() -> ModelProfiles {
        ModelProfiles(read: { self.data }, write: {
            if self.failWrite { throw URLError(.cannotWriteToFile) }
            self.data = $0
        }, legacyKey: { self.legacy[$0] }, defaults: defaults, chatGPT: ProfileStorage().open(), eraseLegacy: { self.legacy.removeValue(forKey: $0) }, changed: {})
    }
}

private func response(_ request: URLRequest, _ body: String) -> (Data, URLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
}

extension ModelProfilesTests {
    func testReplacementKeepsCapturedRouteButDeletionPreventsFutureAuthentication() async throws {
        let store = ConnectionStorage().open()
        let profile = try store.save(nil, provider: .openai, label: "Work", key: "captured-key")
        let selection = ModelSelection(provider: .openai, modelID: "gpt-6.1-terra", profileID: profile.id)
        let captured = try XCTUnwrap(selection.route(in: store))
        _ = try store.save(profile.id, provider: .openai, label: "Work", key: "replacement-key")
        let oldKey = await captured.accessToken(profiles: store.chatGPT, connections: store)
        XCTAssertEqual(oldKey, "captured-key")
        XCTAssertEqual(selection.route(in: store)?.key, "replacement-key")
        try store.remove(profile.id)
        let afterRemoval = await captured.accessToken(profiles: store.chatGPT, connections: store)
        XCTAssertNil(afterRemoval)
        XCTAssertNil(selection.route(in: store))
        // Removing local state cannot cancel a network request that already sent its headers.
        XCTAssertEqual(captured.key, "captured-key")
    }
}

extension ModelProfilesTests {
    func testEditorRoundTripAndRenamePreserveCatalogAndDisabledCustomModel() async throws {
        let store = ConnectionStorage().open()
        let api = try store.save(nil, provider: .openai, label: "Work", key: "fixture")
        try await store.refresh(api.id) { request in response(request, #"{"data":[{"id":"gpt-6.1-sol"}]}"#) }
        try store.setModel("gpt-6.1-sol", enabled: true, profileID: api.id)
        let before = try XCTUnwrap(store.profile(api.id))
        let after = try store.save(api.id, provider: .openai, label: "Renamed", key: "fixture", endpoint: "", model: "")
        XCTAssertEqual(before.listed, after.listed)
        XCTAssertEqual(before.enabled, after.enabled)
        let custom = try store.save(nil, provider: .custom, label: "Local", key: nil, endpoint: "http://127.0.0.1:19383/v1", model: "fixture")
        try store.setModel("fixture", enabled: false, profileID: custom.id)
        try store.rename(custom.id, to: "Renamed Local")
        XCTAssertTrue(store.available(custom.id).isEmpty)
    }
    func testCorruptOrWrongProviderPreferenceCannotFallbackToAnotherCredential() async throws {
        let fixture = ConnectionStorage(); let store = fixture.open()
        _ = try store.save(nil, provider: .openai, label: "A", key: "fixture-a")
        let other = try store.save(nil, provider: .deepseek, label: "B", key: "fixture-b")
        fixture.defaults.set("not-a-uuid", forKey: "chat.profile.openai")
        XCTAssertNil(store.preferred(.openai))
        fixture.defaults.set(other.id.uuidString, forKey: "chat.profile.openai")
        XCTAssertNil(store.preferred(.openai))
        _ = try await store.chatGPT.authorize(nil) { _ in grant("oaiapp_corrupt_preference") }
        fixture.defaults.set("chatgpt", forKey: "chat.provider")
        fixture.defaults.set("not-a-uuid", forKey: "chat.chatGPTProfile")
        XCTAssertNil(store.defaultSelection.profileID)
        XCTAssertNil(store.defaultSelection.route(in: store))
    }
}
