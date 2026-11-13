import ActivityKit
import Foundation
import Network
import PokiCore
import SwiftUI
import XCTest
@testable import Poki

@MainActor
final class UnresponsiveAppTests: XCTestCase {
    private var saved: [String: Any?] = [:]
    private let keys = ["chat.provider", "chat.customURL", "chat.customModel", "relayEnabled", ApprovalChoice.modeKey, ApprovalChoice.levelKey]
    private var window: UIWindow?
    private var previousRoot: UIViewController?

    override func setUp() async throws {
        try XCTSkipUnless(AutomationPath.current == .runner, "Run on an isolated simulator with -automationPath runner")
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults.standard.set(false, forKey: "relayEnabled")
        UserDefaults.standard.set("confirm", forKey: ApprovalChoice.modeKey)
        UserDefaults.standard.set("everything", forKey: ApprovalChoice.levelKey)
        window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        previousRoot = window?.rootViewController
    }

    override func tearDown() async throws {
        ChatModel.afterTask = nil
        window?.rootViewController = previousRoot
        ActivityController.endAll()
        for key in keys { UserDefaults.standard.set(saved[key] ?? nil, forKey: key) }
    }

    func testTaskContinuesWhenTheForegroundAppAnswers() async throws {
        try await runScenario(name: "recovers", delay: 8, label: "Continue")
    }

    func testTaskFailsWithProgressAndRetryWhenTheAppNeverAnswers() async throws {
        try await runScenario(name: "never-answers", delay: nil, label: "Continue")
    }

    func testSensitiveStepsStillAskAndDenialSendsNothingAfterRecovery() async throws {
        for label in ["Send", "Pay", "Delete"] {
            try await runScenario(name: "deny-\(label.lowercased())", delay: 8, label: label)
        }
    }

    private func runScenario(name: String, delay: Double?, label: String) async throws {
        let phone = try SilentAppServer(delay: delay, label: label)
        defer { phone.stop() }
        let sensitive = label != "Continue"
        let model = try FakeCompletions(replies: []) { request in
            guard request["tools"] != nil else { return FakeCompletions.text("Test app task") }
            let messages = request["messages"] as? [[String: Any]] ?? []
            let last = messages.last { $0["role"] as? String == "tool" }
            let content = (last?["content"] as? String) ?? (last?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
            if last == nil {
                return FakeCompletions.tool("report_plan", ["steps": ["Open the test app", label], "currentStep": 1, "title": "Test app response"])
            }
            if content == Harness.planPublished {
                return FakeCompletions.tool("do", ["actions": [["launch": phone.bundleID]]])
            }
            if content.contains("did: launch"), content.contains("1 Button \"\(label)\"") {
                return FakeCompletions.tool("do", ["actions": [["tap": 1]]])
            }
            if content == Harness.resultRecorded { return FakeCompletions.text("Test task ended.") }
            let completed = content.contains("Completed") && !sensitive
            return FakeCompletions.tool("finish_task", ["success": completed, "summary": completed ? "Completed." : "The step did not complete.", "details": [], "answer": ["kind": "action"]])
        }
        ModelKeys.customURL = "http://127.0.0.1:\(model.port)/v1"
        ModelKeys.customModel = "fake-model"
        ModelKeys.selectedProvider = .custom
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), automation: FakeAutomation())
        app.loopback.simulate(.working(ms: 1))
        app.setup.loopback = .proxy
        app.startSession()
        XCTAssertTrue(app.sessionOn)
        app.inProcessReadyForProbe()
        defer { app.stopSession() }
        let chat = ChatModel(app: app)
        chat.newConversation()
        window?.rootViewController = UIHostingController(rootView: ChatView(openDetails: { _ in }, openVoice: {}, openSetup: {}, openModel: {}).environment(app).environment(chat).transaction { $0.disablesAnimations = true })
        window?.makeKeyAndVisible()
        var liveProgress: [Int] = []
        let activity = try XCTUnwrap(Activity<PokiActivityAttributes>.activities.first, "the simulator starts a real Live Activity")
        let activityUpdates = Task { @MainActor in
            for await content in activity.contentUpdates {
                if let seconds = content.state.screenWaitSeconds, liveProgress.last != seconds {
                    liveProgress.append(seconds)
                    self.captureActivity(content.state, name: "\(name)-activity-preview-\(seconds)")
                }
            }
        }
        defer { activityUpdates.cancel() }
        let done = expectation(description: "the real chat loop ends")
        var record: TaskRecord?
        var progress: [Int] = []
        var approvals = 0
        var denials = 0
        var captured = Set<Int>()
        ChatModel.afterTask = { result in
            record = result
            Task { @MainActor in await Task.yield(); done.fulfill() }
        }
        app.addShellObserver { [weak self, weak app] event in
            switch event {
            case .screenWaiting(let seconds, _):
                progress.append(seconds)
                let bucket = seconds
                guard captured.insert(bucket).inserted else { return }
                Task { @MainActor in
                    await Task.yield()
                    guard let self, let app else { return }
                    XCTAssertTrue(app.activityText.contains("Waiting"))
                    await self.capture("\(name)-wait-\(seconds)")
                }
            case .approvalRequested:
                approvals += 1
                Task { @MainActor in
                    await Task.yield()
                    await self?.capture("\(name)-approval")
                }
            case .approvalEnded(_, let approved):
                if approved == false { denials += 1 }
            default: break
            }
        }
        chat.send("Open the test app and \(label.lowercased()).")
        await fulfillment(of: [done], timeout: 100)
        await Task.yield()
        await capture("\(name)-finished")
        let result = try XCTUnwrap(record)
        let calls = result.calls.map { ["tool": $0.name, "arguments": $0.arguments, "answer": $0.answer] }
        try JSONSerialization.data(withJSONObject: calls, options: [.prettyPrinted, .sortedKeys]).write(to: evidence.appendingPathComponent(name + "-calls.json"))
        XCTAssertFalse(progress.isEmpty, "the chat receives waiting progress")
        XCTAssertGreaterThan(liveProgress.count, 1, "ActivityKit receives changing waiting state: \(liveProgress)")
        if delay == nil {
            XCTAssertEqual(result.result?.success, false)
            XCTAssertTrue(chat.canRetry, "the actual chat offers Try Again")
            XCTAssertTrue(chat.entries.contains { if case .note(.problem(let words)) = $0.kind { return words.contains("not responding") }; return false })
            XCTAssertGreaterThan(progress.last ?? 0, 45)
            XCTAssertEqual(phone.touches, 0)
        } else if sensitive {
            XCTAssertEqual(approvals, 1, "\(label) still needs the owner's approval")
            XCTAssertEqual(denials, 1, "the owner declined using the displayed approval card")
            XCTAssertEqual(phone.touches, 0, "denial must keep \(label) from reaching the app")
        } else {
            XCTAssertEqual(result.result?.success, true)
            XCTAssertEqual(phone.touches, 1)
            XCTAssertTrue(result.calls.contains { $0.answer.contains("Completed") }, "the last read verifies the action")
            XCTAssertGreaterThan(progress.count, 1)
        }
        print("SIM_APP_RESPONSE \(name) launch_to_first_tree=\(phone.firstReadSeconds.map { String(format: "%.3f", $0) } ?? "none") progress=\(progress) touches=\(phone.touches) approvals=\(approvals) task_success=\(String(describing: result.result?.success))")
        print("SIM_ACTIVITY_PROGRESS \(name) \(liveProgress)")
    }

    private var evidence: URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("app-response-evidence")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func capture(_ name: String) async {
        await DisplayFrames.rendered()
        guard let window else { return XCTFail("no simulator window") }
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try? image.pngData()?.write(to: evidence.appendingPathComponent(name + ".png"))
    }

    private func captureActivity(_ state: PokiState, name: String) {
        let renderer = ImageRenderer(content: LockScreenCard(face: state.face).frame(width: 390).background(Color.blue))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return XCTFail("Activity preview did not render") }
        try? image.pngData()?.write(to: evidence.appendingPathComponent(name + ".png"))
    }
}

@MainActor
private final class DisplayFrames: NSObject {
    private var remaining = 2
    private var continuation: CheckedContinuation<Void, Never>?

    static func rendered() async {
        let frames = DisplayFrames()
        await withCheckedContinuation { continuation in
            frames.continuation = continuation
            let link = CADisplayLink(target: frames, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        remaining -= 1
        guard remaining == 0 else { return }
        link.invalidate()
        continuation?.resume()
        continuation = nil
    }
}

private final class SilentAppServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "silent-app-http")
    private let lock = NSLock()
    private let delay: Double?
    private let label: String
    let bundleID: String
    private var launched: Date?
    private var firstRead: Double?
    private var touched = 0
    private let png: Data
    private lazy var local = LocalRunner(serve: { [unowned self] in self.serve($0) }, unanswered: { [unowned self] in
        self.lock.withLock {
            guard let launched = self.launched else { return nil }
            let elapsed = Date().timeIntervalSince(launched)
            guard self.delay == nil || elapsed < self.delay! else { return nil }
            return ("foreground accessibility request", min(59, elapsed))
        }
    })

    var touches: Int { lock.withLock { touched } }
    var firstReadSeconds: Double? { lock.withLock { firstRead } }

    @MainActor init(delay: Double?, label: String) throws {
        self.delay = delay
        self.label = label
        bundleID = label == "Send" ? "com.apple.MobileSMS" : "com.example.slow-test"
        png = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
            ("Simulated app response" as NSString).draw(at: CGPoint(x: 30, y: 100), withAttributes: [.foregroundColor: UIColor.black])
        }.pngData()!
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8100)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        _ = local
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global())
            self?.receive(connection, Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else { throw URLError(.cannotConnectToHost) }
    }

    func stop() { listener.cancel() }

    private func serve(_ request: LocalRunner.Request) -> (status: Int, body: Data) {
        func ok(_ value: JSON) -> (Int, Data) { (200, (["value": value] as JSON).data()) }
        return lock.withLock {
            switch request.key {
            case "POST /session": return ok(["sessionId": "local-test"])
            case "POST /appium/settings", "DELETE /session": return ok(.null)
            case "GET /wda/locked": return ok(false)
            case "GET /wda/screen": return ok(["screenSize": ["width": 390, "height": 844]])
            case "GET /wda/activeAppInfo": return ok(["bundleId": .string(bundleID), "name": "Slow Test App"])
            case "POST /wda/apps/activate", "POST /wda/apps/launch":
                if request.body?["bundleId"]?.string == bundleID, launched == nil { launched = Date() }
                return ok(.null)
            case "GET /source":
                if let launched, firstRead == nil { firstRead = Date().timeIntervalSince(launched) }
                let text = touched == 0 ? label : "Completed"
                return ok(.string("<AppiumAUT><XCUIElementTypeApplication label=\"Slow Test App\"><XCUIElementTypeButton name=\"\(text)\" label=\"\(text)\" x=\"40\" y=\"180\" width=\"200\" height=\"50\"/></XCUIElementTypeApplication>"))
            case "GET /screenshot": return ok(.string(png.base64EncodedString()))
            case "POST /wda/tap": touched += 1; return ok(.null)
            default: return (404, (["value": ["error": "unknown command", "message": .string(request.key)]] as JSON).data())
            }
        }
    }

    private func receive(_ connection: NWConnection, _ data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] more, _, done, error in
            guard let self else { return }
            let data = data + (more ?? Data())
            guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
                if done || error != nil { connection.cancel() } else { self.receive(connection, data) }
                return
            }
            let header = String(decoding: data[..<end.lowerBound], as: UTF8.self)
            let length = header.lowercased().components(separatedBy: "\r\n").first { $0.hasPrefix("content-length:") }.flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
            let body = Data(data[end.upperBound...])
            guard body.count >= length else { self.receive(connection, data); return }
            let request = header.components(separatedBy: "\r\n")[0].split(separator: " ")
            guard request.count >= 2, let url = URL(string: "http://127.0.0.1:8100" + request[1]) else { connection.cancel(); return }
            Task {
                let result = try? await self.local.send(method: String(request[0]), url: url, body: length == 0 ? nil : Data(body.prefix(length)), timeout: 10)
                guard let result else { connection.cancel(); return }
                let head = "HTTP/1.1 \(result.status) OK\r\nContent-Type: application/json\r\nContent-Length: \(result.body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + result.body, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}
