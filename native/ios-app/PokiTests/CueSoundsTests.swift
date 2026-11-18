import XCTest
@testable import Poki

@MainActor
final class CueSoundsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "cue-sounds-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testTaskAndApprovalEventsPlayTheSelectedFilesOnce() {
        let output = RecordingCueOutput()
        let sounds = CueSounds(output: output, defaults: defaults)
        let first = UUID(), second = UUID()
        sounds.taskStarted(first)
        sounds.taskStarted(first)
        sounds.approvalPresented("first-approval")
        sounds.approvalPresented("first-approval")
        sounds.taskEnded(first, succeeded: true)
        sounds.taskEnded(first, succeeded: true)
        sounds.taskStarted(second)
        sounds.taskEnded(second, succeeded: false)
        sounds.taskEnded(second, succeeded: false)
        XCTAssertEqual(output.files, ["start", "notification", "complete", "start", "blocked"])
    }

    func testDisablingSoundsPersistsAndDoesNotReplayMissedEvents() {
        let output = RecordingCueOutput()
        let sounds = CueSounds(output: output, defaults: defaults)
        XCTAssertTrue(sounds.enabled)
        sounds.enabled = false
        let reloaded = CueSounds(output: output, defaults: defaults)
        XCTAssertFalse(reloaded.enabled)
        let task = UUID()
        reloaded.taskStarted(task)
        reloaded.approvalPresented("muted-approval")
        reloaded.taskEnded(task, succeeded: false)
        XCTAssertEqual(output.files, [])
        reloaded.enabled = true
        reloaded.approvalPresented("muted-approval")
        XCTAssertEqual(output.files, [])
        reloaded.approvalPresented("new-approval")
        XCTAssertEqual(output.files, ["notification"])
    }
}

@MainActor
final class RecordingCueOutput: CueSoundOutput {
    private(set) var files: [String] = []
    func play(_ cue: TaskCue) { files.append(cue.rawValue) }
}

/// The chat's own task path against a scripted endpoint, with the cue output recorded at the
/// system playback boundary: what plays, in what order, and what stays quiet.
@MainActor
final class CueSoundsFlowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var saved: [String: Any?] = [:]
    private static let settings = ["chat.provider", "chat.customURL", "chat.customModel"]
    private let payment = "a payment (\"pay\")"

    override func setUp() async throws {
        suite = "cue-sounds-flow.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        for key in Self.settings { saved[key] = UserDefaults.standard.object(forKey: key) }
        await SessionStore.shared.waitUntilLoaded()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        for key in Self.settings { UserDefaults.standard.set(saved[key] ?? nil, forKey: key) }
    }

    private func chat(on server: FakeCompletions, output: RecordingCueOutput) -> (ChatModel, AppModel) {
        ModelKeys.customURL = "http://127.0.0.1:\(server.port)/v1"
        ModelKeys.customModel = "fake-model"
        ModelKeys.selectedProvider = .custom
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        app.inProcessReadyForProbe()
        app.cueSounds = CueSounds(output: output, defaults: defaults)
        return (ChatModel(app: app, kind: .handoff, requester: "Test agent"), app)
    }

    private func approval(_ id: String) -> PendingApproval {
        PendingApproval(id: id, app: "Messages", summary: "Pay", reason: payment, expires: Date().addingTimeInterval(60))
    }

    /// One task that is asked once, answers, and finishes, then one that fails: four cues in order.
    func testStartApprovalCompleteAndFailureEachPlayOnce() async throws {
        let output = RecordingCueOutput()
        let box = AppBox()
        let ask = approval("flow-approval")
        let done = try FakeCompletions(replies: [
            FakeCompletions.tool("finish_task", ["success": true, "summary": "Done."]),
            FakeCompletions.text("Done."),
        ], onRequest: { body in
            guard (body["messages"] as? [[String: Any]])?.contains(where: { $0["role"] as? String == "tool" }) == true else { return }
            let asked = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { MainActor.assumeIsolated { box.app?.handle(.approvalRequested(ask)); box.app?.handle(.approvalRequested(ask)) }; asked.signal() }
            _ = asked.wait(timeout: .now() + 5)
        })
        let (first, app) = chat(on: done, output: output)
        box.app = app
        _ = await first.runDelegated("Pay the bill")
        XCTAssertEqual(output.files, ["start", "notification", "complete"])

        let broken = try FakeCompletions(replies: ["{}"], responseStatus: "500 Internal Server Error")
        let (second, _) = chat(on: broken, output: output)
        _ = await second.runDelegated("Pay the bill again")
        XCTAssertEqual(output.files, ["start", "notification", "complete", "start", "blocked"])
    }

    /// Stop ends a task with no completion or failure cue.
    func testStoppingATaskPlaysNeitherCompletionNorFailure() async throws {
        let output = RecordingCueOutput()
        let started = expectation(description: "request in flight")
        let server = try FakeCompletions(replies: [FakeCompletions.text("Never sent.")], holdFirstReply: { started.fulfill() })
        let (chat, _) = chat(on: server, output: output)
        chat.send("Hold on")
        await fulfillment(of: [started], timeout: 5)
        chat.stop()
        for _ in 0..<40 where chat.running { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(output.files, ["start"])
    }

    /// A bundle without the sounds (or sounds the system refuses) leaves every cue silent and harmless.
    func testMissingSoundFilesPlayNothingAndDoNotCrash() async throws {
        let empty = Bundle(path: NSTemporaryDirectory()) ?? Bundle()
        let output = SystemCueOutput(bundle: empty)
        for cue in TaskCue.allCases { output.play(cue) }
        try await Task.sleep(for: .milliseconds(200))
    }
}

@MainActor
private final class AppBox { var app: AppModel? }
