import PokiCore
import XCTest
@testable import Poki

/// Faithful in-process WDA transport mirroring `InProcessWDA`'s pre-dispatch session contract:
/// - `POST /session` calls `InProcessWDA.openThroughGate { session.prepare() }` and returns `inprocess-<generation>`.
/// - Pre-dispatch check (`InProcessWDA.swift:340-342`) returns HTTP 404 `invalid session id` when the
///   session id no longer matches the open generation. Requests already dispatched complete normally.
/// - Tracks foreground app transitions (starting in Poki, switching to Settings on launch/activate, returning to Poki).
final class InProcessContractTransport: HTTPTransport, @unchecked Sendable {
    let usesDynamicScreenSize = true
    private let session: FakeAutomation
    private let pokiBundle: String
    private let beforeScreen: (@Sendable (Int) async -> Void)?
    private let lock = NSLock()
    private var frontBundle: String
    private var reads = 0
    private var screenCalls = 0

    var screenReads: Int { lock.withLock { reads } }
    var currentFrontBundle: String { lock.withLock { frontBundle } }

    init(
        session: FakeAutomation,
        pokiBundle: String = Bundle.main.bundleIdentifier ?? "nz.zheha.poki",
        beforeScreen: (@Sendable (Int) async -> Void)? = nil
    ) {
        self.session = session
        self.pokiBundle = pokiBundle
        self.frontBundle = pokiBundle
        self.beforeScreen = beforeScreen
    }

    func send(method: String, url: URL, body: Data?, timeout: Double) async throws -> (status: Int, body: Data) {
        let components = url.path.split(separator: "/").map(String.init)
        let sessionID: String?
        let path: String
        if components.count >= 2, components[0] == "session" {
            sessionID = components[1]
            path = "/" + components.dropFirst(2).joined(separator: "/")
        } else {
            sessionID = nil
            path = url.path
        }

        if method == "POST", path == "/session" {
            let prepared = InProcessWDA.openThroughGate { session.prepare() }
            guard prepared["ok"] as? Bool == true else {
                let msg = "the automation session could not be opened: \(prepared["code"] ?? "unknown")"
                return (500, (["value": ["error": "session not created", "message": .string(msg)]] as JSON).data())
            }
            return (200, (["value": ["sessionId": .string("inprocess-\(session.generation)")]] as JSON).data())
        }

        if method == "DELETE", sessionID != nil, path == "/" {
            return (200, (["value": .null] as JSON).data())
        }

        // Pre-dispatch session generation check, matching `InProcessWDA.swift:340-342`.
        if let sessionID {
            let expected = "inprocess-\(session.generation)"
            if !session.isOpen || sessionID != expected {
                let msg = "the automation session \(sessionID) has ended (now generation \(session.generation))"
                return (404, (["value": ["error": "invalid session id", "message": .string(msg)]] as JSON).data())
            }
        }

        let value: JSON
        switch "\(method) \(path)" {
        case "GET /status":
            value = ["ready": true]
        case "GET /wda/locked":
            value = false
        case "GET /wda/screen":
            let callIndex = lock.withLock { () -> Int in
                screenCalls += 1
                return screenCalls
            }
            await beforeScreen?(callIndex)
            value = ["screenSize": ["width": 390, "height": 844]]
        case "GET /wda/activeAppInfo":
            let bundle = lock.withLock { frontBundle }
            let name = bundle == pokiBundle ? "Poki" : "Settings"
            value = ["bundleId": .string(bundle), "name": .string(name)]
        case "POST /wda/apps/launch", "POST /wda/apps/activate":
            if let body, let bundle = (try? JSON.parse(body))?["bundleId"]?.string {
                lock.withLock { frontBundle = bundle }
            }
            value = .null
        case "GET /screenshot":
            value = .string("iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAADklEQVR4nGP4DwYMEAoAU7oL9ZisIGcAAAAASUVORK5CYII=")
        case "GET /source":
            lock.withLock { reads += 1 }
            let bundle = lock.withLock { frontBundle }
            let appName = bundle == pokiBundle ? "Poki" : "Settings"
            value = .string(#"<AppiumAUT><XCUIElementTypeApplication name="\#(appName)" label="\#(appName)" x="0" y="0" width="390" height="844"><XCUIElementTypeButton name="General" label="General" x="16" y="100" width="358" height="44" /></XCUIElementTypeApplication></AppiumAUT>"#)
        case "POST /appium/settings":
            value = .null
        default:
            value = .null
        }
        return (200, (["value": value] as JSON).data())
    }
}

@MainActor
final class AutomationWatermarkStopTests: XCTestCase {
    private let defaultsKeys = [
        "chat.provider", "chat.customURL", "chat.customModel",
        "custom.providers", "chat.customProvider", "chat.model.custom",
        "relayAddress", "relayEnabled", "chatEngine",
    ]
    private var savedDefaults: [Any?] = []
    private var savedSetup: SetupState!
    private var savedAllowance: Any?
    private var savedLanguage = AppLocalization.system
    private var model: AppModel!
    private var session: FakeAutomation!
    private var launcher: FakeLauncher!
    private var tempFolder: URL!
    private var suiteName: String!
    private var pokiBundle: String { Bundle.main.bundleIdentifier ?? "nz.zheha.poki" }

    override func setUp() async throws {
        try XCTSkipUnless(AutomationPath.current == .inProcess, "Poki Runner path")
        InProcessWDA.gate.withLock {
            $0 = InProcessWDA.OpenGate()
            $0.startedThisBoot = true
        }
        savedLanguage = AppLocalization.shared.preference
        AppLocalization.shared.preference = "en"
        savedAllowance = UserDefaults.standard.object(forKey: AutomationAllowance.key)
        UserDefaults.standard.removeObject(forKey: AutomationAllowance.key)
        savedSetup = SetupState.load()
        savedDefaults = defaultsKeys.map { UserDefaults.standard.object(forKey: $0) }
        UserDefaults.standard.removeObject(forKey: "chatEngine")
        tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("WatermarkStop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        suiteName = "WatermarkStop-\(UUID().uuidString)"
        session = FakeAutomation()
        launcher = FakeLauncher()
    }

    override func tearDown() async throws {
        session?.answer(nil)
        session?.releasePause()
        model?.stopSession()
        for (key, value) in zip(defaultsKeys, savedDefaults) {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.set(savedAllowance, forKey: AutomationAllowance.key)
        AppLocalization.shared.preference = savedLanguage
        savedSetup?.save()
        if let suiteName { UserDefaults().removePersistentDomain(forName: suiteName) }
        if let tempFolder { try? FileManager.default.removeItem(at: tempFolder) }
    }

    private func makeHarness(
        system major: Int = 27,
        server: FakeCompletions,
        beforeScreen: (@Sendable (Int) async -> Void)? = nil
    ) async throws -> (ChatModel, InProcessContractTransport) {
        ModelKeys.customURL = "http://127.0.0.1:\(server.port)/v1"
        ModelKeys.customModel = "fake-model"
        ModelKeys.selectedProvider = .custom
        let transport = InProcessContractTransport(
            session: session,
            pokiBundle: pokiBundle,
            beforeScreen: beforeScreen
        )
        model?.stopSession()
        model = AppModel(
            launcher: launcher,
            pairer: FakePairing(),
            automation: session,
            transport: transport,
            systemVersion: OperatingSystemVersion(majorVersion: major, minorVersion: 2, patchVersion: 0),
            simulatorRunnerAnswers: { true }
        )
        model.loopback.simulate(.working(ms: 9))
        model.setup.loopback = .proxy
        XCTAssertTrue(model.setRelay("https://relay.invalid"))
        model.startSession()
        XCTAssertTrue(model.sessionOn)

        let store = SessionStore(folder: tempFolder, defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let chat = ChatModel(app: model, store: store)
        AskPoki.install(app: model, chat: chat)
        return (chat, transport)
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        done.expectationDescription = what
        await fulfillment(of: [done], timeout: timeout)
    }

    private func launchSettingsTool() -> String {
        FakeCompletions.tool("do", ["actions": [["launch": "com.apple.Preferences"]]])
    }

    private func hasProblemNote(in chat: ChatModel) -> Bool {
        chat.entries.contains {
            if case .note(.problem) = $0.kind { return true }
            return false
        }
    }

    // MARK: - Baseline Control

    func testNormalCompletionClosesAutomationAndAllowsNextTask() async throws {
        let server = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.text("Done opening Settings."),
            launchSettingsTool(),
            FakeCompletions.text("Second task done."),
        ])
        let (chat, transport) = try await makeHarness(server: server)
        let closeBeforeFirst = model.lastInProcessClose?.number ?? 0

        chat.send("Open Settings.")
        await waitFor("first task finished and closed automation") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBeforeFirst
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }
        XCTAssertTrue(chat.entries.contains { $0.kind == .poki("Done opening Settings.") })
        XCTAssertEqual(transport.currentFrontBundle, pokiBundle, "normal completion returns to Poki")
        XCTAssertGreaterThanOrEqual(transport.screenReads, 1)
        XCTAssertFalse(model.hasOpenInProcessSession)

        // Start the next task directly from the chat entry without pre-injecting runner state.
        let closeBeforeSecond = model.lastInProcessClose?.number ?? 0
        chat.send("Open Settings again.")
        await waitFor("second task finished and closed automation") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBeforeSecond
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }
        XCTAssertTrue(chat.entries.contains { $0.kind == .poki("Second task done.") })
        XCTAssertEqual(transport.currentFrontBundle, pokiBundle)
        XCTAssertGreaterThanOrEqual(transport.screenReads, 2)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    // MARK: - Path 1: Task Failure

    func testTaskFailureAfterSwitchingBackToPokiClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                #"{"error":{"message":"simulated upstream failure"}}"#,
            ],
            responseStatuses: ["200 OK", "500 Internal Server Error"],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, _) = try await makeHarness(server: server)

        chat.send("Open Settings and check something.")
        await waitFor("task opened Settings and entered second model turn") {
            self.session.isOpen && server.requests.count == 2
        }
        model.wentToBackground()

        // User switches back to Poki to see what is happening; Poki closes automation on foreground.
        let closeBeforeForeground = model.lastInProcessClose?.number ?? 0
        model.becameActive()
        await waitFor("becameActive closed session") {
            (self.model.lastInProcessClose?.number ?? 0) > closeBeforeForeground
                && !self.session.isOpen && self.model.runnerPaused
        }

        // Now the model request fails.
        server.release()
        await waitFor("failed task recorded failure") {
            !chat.running && self.hasProblemNote(in: chat) && self.model.activityText == "Idle"
        }
        // Drain any teardown task queued on the runner without sleeping.
        await Task.yield()
        _ = await model.phoneSettles(within: 2)

        XCTAssertFalse(session.isOpen, "task failure after returning to Poki must not leave automation reopened")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testTaskFailureMidTaskInBackgroundClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                #"{"error":{"message":"simulated upstream failure"}}"#,
            ],
            responseStatuses: ["200 OK", "500 Internal Server Error"],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, transport) = try await makeHarness(server: server)

        chat.send("Open Settings and fail.")
        await waitFor("task opened Settings and entered second model turn") {
            self.session.isOpen && server.requests.count == 2
        }
        // Poki is now in the background while the model fails.
        model.wentToBackground()
        let closeBefore = model.lastInProcessClose?.number ?? 0
        server.release()

        await waitFor("background failure finished and closed automation") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBefore
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }
        XCTAssertTrue(hasProblemNote(in: chat), "model error must be recorded as a failure")
        XCTAssertGreaterThanOrEqual(transport.screenReads, 1)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    // MARK: - Path 2: Stop from Dynamic Island (Live Activity)

    func testLiveActivityStopWhileWaitingForModelClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, _) = try await makeHarness(server: server)

        chat.send("Open Settings and keep working.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }
        model.wentToBackground()
        let closeBefore = model.lastInProcessClose?.number ?? 0

        // Live Activity Stop handler (`StopRunnerIntent` posts to `stopFromOutside`).
        model.stopFromOutside(AppModel.liveActivityStop)
        await waitFor("task stopped and received close receipt") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBefore
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }

        XCTAssertFalse(session.isOpen, "Dynamic Island stop must close automation and never reopen it during teardown")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testLiveActivityStopDuringInFlightStepClosesAutomation() async throws {
        let gate = StepHoldGate()
        let server = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.tool("look", [:]),
            FakeCompletions.text("Should not finish."),
        ])
        // Hold `GET /wda/screen` on the second phone step so it returns 200 OK normally when
        // released, and the subsequent `GET /source` hits the real pre-dispatch 404 check.
        let (chat, _) = try await makeHarness(server: server, beforeScreen: { callIndex in
            if callIndex == 2 { await gate.wait() }
        })

        chat.send("Open Settings and read again.")
        await waitFor("second phone step is in flight") { gate.isBlocked }
        model.wentToBackground()

        // User taps Stop on Dynamic Island while the phone step is in flight.
        let closeBefore = model.lastInProcessClose?.number ?? 0
        model.stopFromOutside(AppModel.liveActivityStop)
        await waitFor("pauseRunner closed automation before the in-flight request returned") {
            (self.model.lastInProcessClose?.number ?? 0) > closeBefore
        }

        // Let the in-flight `GET /wda/screen` finish (200 OK); the next request (`GET /source`)
        // hits the pre-dispatch 404 generation check and retries `POST /session` before teardown closes it.
        gate.release()
        await waitFor("stopped in-flight step finished teardown") {
            !chat.running && chat.entries.contains { $0.kind == .poki("Stopped.") }
                && self.model.activityText == "Idle"
        }
        await Task.yield()
        _ = await model.phoneSettles(within: 2)

        XCTAssertFalse(session.isOpen, "Dynamic Island stop during an in-flight step must not leave automation open")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    // MARK: - Path 3: Stop inside Poki App

    func testInAppStopAfterSwitchingBackToPokiWhileWaitingForModelClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, _) = try await makeHarness(server: server)

        chat.send("Open Settings and wait.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }
        model.wentToBackground()

        // User switches back to Poki App, then taps Stop button in ChatView.
        let closeBeforeForeground = model.lastInProcessClose?.number ?? 0
        model.becameActive()
        await waitFor("becameActive closed session") {
            (self.model.lastInProcessClose?.number ?? 0) > closeBeforeForeground
                && !self.session.isOpen && self.model.runnerPaused
        }
        let closeBeforeStop = model.lastInProcessClose?.number ?? 0

        chat.stop()
        await waitFor("in-app stop finished teardown") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBeforeStop
                && self.model.activityText == "Idle"
        }

        XCTAssertFalse(session.isOpen, "In-app stop after switching back to Poki must not reopen automation")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testInAppStopDuringInFlightStepClosesAutomation() async throws {
        let gate = StepHoldGate()
        let server = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.tool("look", [:]),
            FakeCompletions.text("Should not finish."),
        ])
        let (chat, _) = try await makeHarness(server: server, beforeScreen: { callIndex in
            if callIndex == 2 { await gate.wait() }
        })

        chat.send("Open Settings and read again.")
        await waitFor("second phone step is in flight") { gate.isBlocked }
        model.wentToBackground()

        // User switches back to Poki App while the step is in flight, then taps Stop in ChatView.
        let closeBefore = model.lastInProcessClose?.number ?? 0
        model.becameActive()
        chat.stop()

        gate.release()
        await waitFor("in-app stop during in-flight step finished teardown") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBefore
                && chat.entries.contains { $0.kind == .poki("Stopped.") } && self.model.activityText == "Idle"
        }

        XCTAssertFalse(session.isOpen, "In-app stop during an in-flight step must close automation and not reopen it")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testInAppStopWhileWaitingForModelWithoutBecameActiveClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, _) = try await makeHarness(server: server)

        chat.send("Open Settings and wait.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }
        let closeBefore = model.lastInProcessClose?.number ?? 0

        // User taps Stop inside Poki App while the session is still open.
        chat.stop()
        await waitFor("automation closed after in-app stop") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBefore
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testInAppStopDuringInFlightStepFollowedImmediatelyByNextTaskClosesOldSession() async throws {
        let gate = StepHoldGate()
        // Hold request #3 (the next task's first model request) so we inspect session state at
        // the exact moment the next task starts — before the next task can end and mask a leak.
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.tool("look", [:]),
                FakeCompletions.text("Four."),
            ],
            holdAfter: 2
        )
        defer { server.release() }
        let (chat, _) = try await makeHarness(server: server, beforeScreen: { callIndex in
            if callIndex == 2 { await gate.wait() }
        })

        chat.send("Open Settings and read again.")
        await waitFor("second phone step is in flight") { gate.isBlocked }
        model.wentToBackground()

        // User switches back to Poki, taps Stop, and immediately sends the next (pure-chat) task
        // while the stopped task's in-flight phone step has not yet returned.
        let closeBefore = model.lastInProcessClose?.number ?? 0
        model.becameActive()
        chat.stop()
        chat.send("What is two plus two?")
        XCTAssertTrue(chat.running, "next task is queued immediately behind the stopped task")

        gate.release()
        await waitFor("next task reached the model after the stopped task exited") {
            server.requests.count == 3
        }

        // Check at the exact moment the next task begins (its reply is still held): the old
        // stopped task must already have closed its automation session.
        XCTAssertTrue(chat.running, "next task must still be running when verifying old-session closure")
        XCTAssertFalse(session.isOpen, "old stopped task must have closed automation before the next task starts")
        XCTAssertGreaterThanOrEqual(session.closes, 1, "old stopped task must have recorded a real close before the next task starts")
        XCTAssertGreaterThan(model.lastInProcessClose?.number ?? 0, closeBefore)
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)

        // Release the next pure-chat task and confirm it completes with automation still closed.
        server.release()
        await waitFor("next pure-chat task finished") {
            !chat.running && chat.entries.contains { $0.kind == .poki("Four.") } && self.model.activityText == "Idle"
        }
        XCTAssertFalse(session.isOpen)
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    // MARK: - Follow-up Tasks & iOS 26 Policy

    func testInAppStopOnIOS26PerformsFullCloseAndAllowsNextTask() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, transport) = try await makeHarness(system: 26, server: server)

        chat.send("Open Settings and wait.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }
        let closeBeforeStop = model.lastInProcessClose?.number ?? 0

        chat.stop()
        await waitFor("iOS 26 owner stop fully closes automation") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBeforeStop
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }
        XCTAssertGreaterThanOrEqual(session.closes, 1)
        XCTAssertEqual(session.pauses, 0)

        // Start the follow-up task directly from the chat entry without pre-injecting runner state.
        let closeBeforeNext = model.lastInProcessClose?.number ?? 0
        let nextServer = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.text("Next task done."),
        ])
        ModelKeys.customURL = "http://127.0.0.1:\(nextServer.port)/v1"
        chat.send("Open Settings again.")
        await waitFor("next task finished and stood by on iOS 26") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBeforeNext
                && self.model.runnerPaused && self.session.pauses >= 1 && self.model.activityText == "Idle"
        }
        XCTAssertTrue(chat.entries.contains { $0.kind == .poki("Next task done.") })
        XCTAssertGreaterThanOrEqual(transport.screenReads, 2)
    }

    func testImmediateNextTaskAfterLiveActivityStopReopensAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, transport) = try await makeHarness(server: server)

        chat.send("Open Settings and wait.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }
        model.wentToBackground()
        let closeBeforeStop = model.lastInProcessClose?.number ?? 0

        model.stopFromOutside(AppModel.liveActivityStop)
        await waitFor("task stopped and automation closed") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBeforeStop
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }

        // Start the next task directly from the chat entry without pre-injecting runner state.
        let closeBeforeNext = model.lastInProcessClose?.number ?? 0
        let nextServer = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.text("Second task done."),
        ])
        ModelKeys.customURL = "http://127.0.0.1:\(nextServer.port)/v1"
        chat.send("Open Settings again.")
        await waitFor("second task finished and closed automation") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBeforeNext
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }
        XCTAssertTrue(chat.entries.contains { $0.kind == .poki("Second task done.") })
        XCTAssertGreaterThanOrEqual(transport.screenReads, 2)
    }

    func testImmediateNextTaskAfterFailureReopensAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                #"{"error":{"message":"simulated upstream failure"}}"#,
            ],
            responseStatuses: ["200 OK", "500 Internal Server Error"],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, transport) = try await makeHarness(server: server)

        chat.send("Open Settings and fail.")
        await waitFor("task opened Settings and waiting on failing turn") {
            self.session.isOpen && server.requests.count == 2
        }
        model.wentToBackground()
        let closeBeforeFailure = model.lastInProcessClose?.number ?? 0
        server.release()

        await waitFor("failed task finished and closed automation") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBeforeFailure
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }
        XCTAssertTrue(hasProblemNote(in: chat))
        let readsAfterFailure = transport.screenReads
        XCTAssertGreaterThanOrEqual(readsAfterFailure, 1)

        // Start the retry task directly from the chat entry without pre-injecting runner state.
        let closeBeforeRetry = model.lastInProcessClose?.number ?? 0
        let retryServer = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.text("Recovered on retry."),
        ])
        ModelKeys.customURL = "http://127.0.0.1:\(retryServer.port)/v1"
        chat.send("Try again.")
        await waitFor("retry task finished and closed automation") {
            !chat.running && (self.model.lastInProcessClose?.number ?? 0) > closeBeforeRetry
                && !self.session.isOpen && self.model.runnerPaused && self.model.activityText == "Idle"
        }
        XCTAssertTrue(chat.entries.contains { $0.kind == .poki("Recovered on retry.") })
        XCTAssertGreaterThan(transport.screenReads, readsAfterFailure)
    }
}

private final class StepHoldGate: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var blocked = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var isBlocked: Bool { lock.withLock { blocked } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if released { return true }
                blocked = true
                continuations.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            released = true
            blocked = false
            defer { continuations.removeAll() }
            return continuations
        }
        pending.forEach { $0.resume() }
    }
}
