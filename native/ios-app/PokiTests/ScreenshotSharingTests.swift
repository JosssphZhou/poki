import PokiCore
import UIKit
import XCTest
@testable import Poki

@MainActor
final class ScreenshotSharingTests: XCTestCase {
    private var clipboard: [[String: Any]] = []
    private var saved: [String: Any?] = [:]
    private let keys = ["chat.provider", "chat.customURL", "chat.customModel"]

    override func setUp() {
        clipboard = UIPasteboard.general.items
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
    }

    override func tearDown() {
        UIPasteboard.general.items = clipboard
        for key in keys { UserDefaults.standard.set(saved[key] ?? nil, forKey: key) }
    }

    private var picture: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 24, height: 32)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 32))
        }
    }

    func testFreshScreenshotCopiesAnImage() {
        UIPasteboard.general.string = "old clipboard"
        let captured = picture
        let result = ScreenshotClipboard.copy(.init(text: "screenshot: fresh", jpeg: captured, isError: false))
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(UIPasteboard.general.image?.pngData(), UIImage(data: captured)?.pngData())
        XCTAssertNil(UIPasteboard.general.string)
        XCTAssertTrue(result.text.contains("Nothing has been sent"))
    }

    func testFailedMissingInvalidAndStaleScreenshotsPreserveClipboard() {
        let reads: [PokiCore.ToolAnswer] = [
            .init(text: "read failed", jpeg: picture, isError: true),
            .init(text: "Poki is in front", jpeg: nil, isError: false),
            .init(text: "screenshot", jpeg: Data("invalid".utf8), isError: false),
            .init(text: "the screenshot is the one of the read before, 12 s old (no newer one came)", jpeg: picture, isError: false),
        ]
        for read in reads {
            UIPasteboard.general.string = "keep this"
            XCTAssertTrue(ScreenshotClipboard.copy(read).isError)
            XCTAssertEqual(UIPasteboard.general.string, "keep this")
        }
    }

    func testSequentialScreenshotTaskUsesClipboardWithoutWorkspaceSetup() async throws {
        let session = FakeAutomation()
        _ = session.prepare()
        let transport = SharingTransport(screen: SessionScreenTransport(session: session))
        let server = try FakeCompletions(replies: [
            FakeCompletions.text("NORMAL"),
            FakeCompletions.tool("copy_screenshot", [:]),
            FakeCompletions.tool("finish_task", ["success": true, "summary": "Copied the screenshot only."]),
            FakeCompletions.text("Copied the screenshot only."),
        ])
        let (model, chat) = makeChat(server, transport: transport, session: session, kind: .poki)
        defer { model.stopSession() }
        chat.restore(SavedSession(id: UUID().uuidString, kind: .poki, title: "Screenshot test", started: Date(),
                                  updated: Date(), live: false, entries: [ChatEntry(.you("Prior message", delivered: true))], calls: []))
        chat.send("Open Instagram and send me a screenshot to myself over Telegram", attachments: [])
        await waitForEnd(chat)
        XCTAssertTrue(chat.savedCalls.contains { $0.name == "copy_screenshot" && $0.ok })
        XCTAssertNotNil(UIPasteboard.general.image)
        XCTAssertEqual(transport.workspaceRequests, 0)
        XCTAssertFalse(chat.isRunningInSplitView)
        XCTAssertFalse(chat.entries.contains { if case .note(.problem) = $0.kind { true } else { false } })
        let offered = server.requests.dropFirst().first?["tools"] as? [[String: Any]] ?? []
        XCTAssertTrue(offered.contains { ($0["function"] as? [String: Any])?["name"] as? String == "copy_screenshot" })
    }

    func testModelFailureDoesNotLeaveTheTaskCardDone() async throws {
        let server = try FakeCompletions(replies: [
            FakeCompletions.tool("report_plan", ["steps": ["Copy screenshot", "Send attachment"], "currentStep": 1]),
            "data: {\"error\":{\"message\":\"Fixture model failure\",\"type\":\"server_error\"}}\n\ndata: [DONE]\n\n",
        ])
        let (model, chat) = makeChat(server)
        defer { model.stopSession() }
        let result = await chat.runDelegated("Copy a screenshot and send it")
        XCTAssertTrue(result.text.contains("error:"), result.text)
        let plans = chat.entries.compactMap { entry -> [PlanStep]? in
            if case .plan(let steps) = entry.kind { return steps }
            return nil
        }
        XCTAssertEqual(plans.count, 1)
        XCTAssertTrue(plans.first?.contains { $0.state == .failed } == true)
    }

    private func makeChat(_ server: FakeCompletions, transport: HTTPTransport? = nil,
                          session: FakeAutomation = FakeAutomation(), kind: SavedSession.Kind = .handoff) -> (AppModel, ChatModel) {
        ModelKeys.customURL = "http://127.0.0.1:\(server.port)/v1"
        ModelKeys.customModel = "fake-model"
        ModelKeys.selectedProvider = .custom
        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), automation: session, transport: transport)
        model.inProcessReadyForProbe()
        return (model, ChatModel(app: model, kind: kind, requester: kind == .handoff ? "Test" : nil))
    }

    private func waitForEnd(_ chat: ChatModel) async {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !chat.running }, object: nil)
        await fulfillment(of: [done], timeout: 15)
        XCTAssertFalse(chat.running)
        if chat.running { chat.stop() }
    }
}

private final class SharingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var workspaces = 0
    private let screen: SessionScreenTransport
    var workspaceRequests: Int { lock.withLock { workspaces } }
    init(screen: SessionScreenTransport) { self.screen = screen }
    func send(method: String, url: URL, body: Data?, timeout: Double) async throws -> (status: Int, body: Data) {
        if url.path.contains("workspace") { lock.withLock { workspaces += 1 } }
        return try await screen.send(method: method, url: url, body: body, timeout: timeout)
    }
}
