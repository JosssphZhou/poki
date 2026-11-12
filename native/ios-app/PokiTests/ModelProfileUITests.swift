import SwiftUI
import UIKit
import XCTest
@testable import Poki

@MainActor
final class ModelProfileUITests: XCTestCase {
    private var apiIDs: [UUID] = []
    private var oauthIDs: [UUID] = []
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        for id in apiIDs { try ModelProfiles.shared.remove(id) }
        for id in oauthIDs { _ = try await ChatGPTProfiles.shared.signOut(id, remove: true) { _ in true } }
    }

    func testChineseCompositionSurvivesAPIAndOAuthSelectionAtLargeTextSize() async throws {
        let api = try ModelProfiles.shared.save(nil, provider: .deepseek, label: "UI fixture \(UUID())", key: "offline-fixture")
        apiIDs.append(api.id)
        let account = try await ChatGPTProfiles.shared.authorize(nil) { _ in grant("oaiapp_ui_\(UUID().uuidString)") }
        oauthIDs.append(account.id)
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        let chat = ChatModel(app: app)
        let draft = Draft()
        let placementKey = ChatModelSwitcherPlacement.preferenceKey
        let previousPlacement = UserDefaults.standard.object(forKey: placementKey)
        defer { UserDefaults.standard.set(previousPlacement, forKey: placementKey) }
        UserDefaults.standard.set(ChatModelSwitcherPlacement.more.rawValue, forKey: placementKey)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 360)
        window.rootViewController = UIHostingController(rootView: Host(draft: draft)
            .environment(app).environment(chat).environment(\.dynamicTypeSize, .accessibility3))
        self.window = window
        window.makeKeyAndVisible()
        settle { self.field(in: window) != nil }
        let field = try XCTUnwrap(field(in: window))
        field.becomeFirstResponder()
        field.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0))
        field.delegate?.textViewDidChange?(field)
        settle { draft.text == "nihao" }
        chat.selectModel(.init(provider: .deepseek, modelID: "deepseek-flash", profileID: api.id))
        XCTAssertEqual(chat.selection.profileID, api.id)
        let beforePlacementChange = chat.selection
        UserDefaults.standard.set(ChatModelSwitcherPlacement.brain.rawValue, forKey: placementKey)
        settle { self.field(in: window) === field }
        XCTAssertEqual(chat.selection, beforePlacementChange)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(draft.text, "nihao")
        XCTAssertNotNil(field.markedTextRange)
        chat.selectModel(.init(provider: .chatgpt, modelID: "gpt-6.1-sol", profileID: account.id))
        settle { chat.selection.profileID == account.id }
        XCTAssertTrue(self.field(in: window) === field)
        XCTAssertEqual(draft.text, "nihao")
        XCTAssertNotNil(field.markedTextRange)
        XCTAssertTrue(draft.sent.isEmpty)
        field.setMarkedText("你好", selectedRange: NSRange(location: 2, length: 0))
        field.unmarkText()
        field.delegate?.textViewDidChange?(field)
        settle { draft.text == "你好" }
        XCTAssertGreaterThan(field.bounds.width, 100)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        })
        attachment.name = "Unified profile composer with Chinese draft and accessibility text size"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRestoredConversationKeepsItsExplicitProfileAndTranscript() throws {
        let p = try ModelProfiles.shared.save(nil, provider: .openai, label: "Restoration fixture \(UUID())", key: "offline-fixture")
        apiIDs.append(p.id)
        let selection = ModelSelection(provider: .openai, modelID: "gpt-6.1-terra", profileID: p.id)
        let entry = ChatEntry(.you("Existing private message", delivered: true))
        let session = SavedSession(id: UUID().uuidString, kind: .poki, title: "Fixture", started: Date(), updated: Date(),
                                   live: false, entries: [entry], calls: [], modelSelection: selection)
        let decoded = try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(session))
        let chat = ChatModel(app: AppModel(launcher: FakeLauncher(), pairer: FakePairing()))
        chat.restore(decoded)
        XCTAssertEqual(chat.selection, selection)
        XCTAssertEqual(chat.entries.map(\.id), [entry.id])
        XCTAssertNotNil(chat.selection.route)
        try ModelProfiles.shared.remove(p.id)
        apiIDs.removeAll { $0 == p.id }
        XCTAssertNil(chat.selection.route)
        XCTAssertEqual(chat.entries.map(\.id), [entry.id])
    }

    private func field(in view: UIView) -> CapsuleTextView? {
        if let field = view as? CapsuleTextView { return field }
        return view.subviews.lazy.compactMap { self.field(in: $0) }.first
    }

    private func settle(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) } while !condition() && Date() < deadline
        XCTAssertTrue(condition())
    }

    private final class Draft: ObservableObject {
        @Published var text = ""
        @Published var focused = true
        var sent: [String] = []
    }
    private struct Host: View {
        @ObservedObject var draft: Draft
        var body: some View {
            ComposerInputView(input: $draft.text, focused: $draft.focused, running: false,
                              send: { draft.sent.append($0) }, stop: {}, openVoice: {}, openModel: {}, newConversation: {})
        }
    }
}
