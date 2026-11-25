import XCTest
@testable import Poki

/// Settings › Models › an account › Text Chat said "Off" for every account except the one the chat
/// was using, even after a model on that account was switched on (#738). The switches only change
/// which models the menu offers.
@MainActor
final class TextChatSummaryTests: XCTestCase {
    private var storage: IsolatedTestStorage!

    override func setUp() async throws {
        storage = try IsolatedTestStorage(prefix: "text-chat-summary")
    }

    override func tearDown() async throws {
        if let storage {
            self.storage = nil
            try storage.tearDown()
        }
    }

    private var off: String { AppLocalization.text(LocalizedStringResource("Off")) }

    func testAnotherAccountsRowShowsTheModelsSwitchedOn() {
        let store = storage.storage
        ModelKeys.setSelectedProvider(.anthropic, in: store)

        XCTAssertEqual(ModelAccounts.textChatSummary(.openai, storage: store), "GPT-6.1 Terra")
        XCTAssertNotEqual(ModelAccounts.textChatSummary(.openai, storage: store), off)
        XCTAssertEqual(ModelAccounts.textChatSummary(.anthropic, storage: store), "Claude Haiku 5.5")
    }

    func testRowSaysOffOnlyAfterEveryModelOnThatAccountIsSwitchedOff() {
        let store = storage.storage
        ModelKeys.setSelectedProvider(.anthropic, in: store)
        ModelCatalog.set("gpt-6.1-terra", on: false, for: .openai, storage: store)
        XCTAssertEqual(ModelAccounts.textChatSummary(.openai, storage: store), off)

        ModelCatalog.set("gpt-6.1-sol", on: true, for: .openai, storage: store)
        XCTAssertEqual(ModelAccounts.textChatSummary(.openai, storage: store), "GPT-6.1 Sol")
        XCTAssertEqual(ModelAccounts.textChatSummary(.anthropic, storage: store), "Claude Haiku 5.5")
    }

    func testSeveralSwitchedOnModelsAreListedForTheAccountTheChatIsNotUsing() {
        let store = storage.storage
        ModelKeys.setSelectedProvider(.openai, in: store)
        let summary = ModelAccounts.textChatSummary(.anthropic, storage: store)
        XCTAssertTrue(summary.contains("Claude Haiku 5.5"), summary)
        XCTAssertTrue(summary.contains("Claude Sonnet 5.5"), summary)
        XCTAssertFalse(summary.contains("Claude Opus"), summary)
        XCTAssertNotEqual(summary, off)
    }

    func testCustomServiceRowShowsItsModelWhileAnotherServiceAnswers() {
        let store = storage.storage
        let alpha = CustomProviders.upsert(service("Alpha", "https://alpha.example/v1", "alpha-model"), storage: store)
        let beta = CustomProviders.upsert(service("Beta", "https://beta.example/v1", "beta-model"), storage: store)
        ModelKeys.setSelectedProvider(.custom, in: store)
        ModelKeys.setSelectedModel(CustomProviders.choiceID(alpha.id, alpha.model), in: store)

        XCTAssertEqual(ModelAccounts.textChatSummary(alpha, storage: store), "alpha-model")
        XCTAssertEqual(ModelAccounts.textChatSummary(beta, storage: store), "beta-model")

        ModelCatalog.set(CustomProviders.choiceID(beta.id, beta.model), on: false, for: .custom, storage: store)
        XCTAssertEqual(ModelAccounts.textChatSummary(beta, storage: store), off)
        XCTAssertEqual(ModelAccounts.textChatSummary(alpha, storage: store), "alpha-model")
    }

    private func service(_ name: String, _ url: String, _ model: String) -> CustomProvider {
        CustomProvider(name: name, endpoints: [CustomEndpoint(url: url)], model: model)
    }
}
