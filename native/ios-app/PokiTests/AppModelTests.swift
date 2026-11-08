import PokiCore
import XCTest
@testable import Poki

/// A launcher that records what the app asked of it and plays back runner events.
final class FakeLauncher: RunnerLauncher, @unchecked Sendable {
    var starts = 0, restarts = 0, stops = 0
    var emit: (@Sendable (RunnerStatus) -> Void)?
    func start(config: LauncherConfig, onEvent: @escaping @Sendable (RunnerStatus) -> Void) throws { starts += 1; emit = onEvent }
    func restart() { restarts += 1 }
    func stop() { stops += 1 }
}

/// Poki's own automation session as iOS keeps it: open (Automation Mode on, the banner showing) or
/// not, and how many times it was opened.
final class FakeAutomation: InProcessAutomation, @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private var opened = 0
    private var gate: DispatchSemaphore?
    private var answer: [String: Any]?
    var isOpen: Bool { lock.withLock { open } }
    var timesOpened: Int { lock.withLock { opened } }
    /// The next open waits, as one does while iOS asks for the passcode, until `answer(_:)`.
    func holdNextOpen() { lock.withLock { gate = DispatchSemaphore(value: 0) } }
    /// Lets a held open go on, with this answer instead of opening (nil opens).
    func answer(_ result: [String: Any]?) { lock.withLock { answer = result; gate?.signal(); gate = nil } }
    func prepare() -> [String: Any] {
        if let held = lock.withLock({ gate }) {
            held.wait()
            if let given = lock.withLock({ () -> [String: Any]? in defer { answer = nil }; return answer }) { return given }
        }
        return lock.withLock {
            let reused = open
            if !open { open = true; opened += 1 }
            return ["ok": true, "generation": opened, "reused": reused, "seconds": 0.0]
        }
    }
    func end() -> Bool { lock.withLock { defer { open = false }; return open } }
}

final class FakePairing: DevicePairing {
    func start(hostName: String, saveTo: URL, onEvent: @escaping @Sendable (PairingEvent) -> Void) throws {}
    func cancel() {}
}

@MainActor
final class AppModelTests: XCTestCase {
    private func model() -> (AppModel, FakeLauncher) {
        let launcher = FakeLauncher()
        let model = AppModel(launcher: launcher, pairer: FakePairing())
        return (model, launcher)
    }

    /// Poki automates the iPhone in its own process by default, and a running launcher then only means
    /// the disk image is mounted: the agent reads "running" once the in-process session is open. The
    /// tests below are about the launcher's states, so they open the session first (the Debug probe's
    /// own call); on the Poki Runner path (`-automationPath runner`) it changes nothing.
    private func sessionOpen(_ model: AppModel) { model.inProcessReadyForProbe() }

    /// The default path: a running launcher is not yet a running phone. The agent hears that the
    /// session is opening until it is open, and "running" right after.
    func testRunningLauncherWaitsForTheInProcessSession() throws {
        let (model, _) = model()
        try XCTSkipUnless(model.automationPath == .inProcess, "Poki Runner path: the launcher's state is the whole story")
        model.loopback.simulate(.working(ms: 9))
        let opening = model.coreState(of: RunnerStatus(state: "running")).describe
        XCTAssertTrue(opening.contains("opening the in-process session"), opening)
        sessionOpen(model)
        XCTAssertEqual(model.coreState(of: RunnerStatus(state: "running")).describe, "running")
    }

    /// A tunnel drop while the runner is connecting is named to the agent with the time and the fix,
    /// whatever launcher state it happens to be in; "Checking pairing" alone would say nothing.
    func testLoopbackDownIsNamedToTheAgent() {
        let (model, _) = model()
        model.loopback.simulate(.working(ms: 12))
        model.loopback.simulate(.off)
        for state in ["connecting", "pairing", "waiting_network", "standby"] {
            let text = model.coreState(of: RunnerStatus(state: state)).describe
            XCTAssertTrue(text.contains("waiting for the loopback since"), "\(state): \(text)")
            XCTAssertTrue(text.contains("proxy app"), text)
        }
        // Launching and running are past the tunnel: they stay what the launcher says.
        sessionOpen(model)
        XCTAssertEqual(model.coreState(of: RunnerStatus(state: "running")).describe, "running")
    }

    /// A tunnel that gave the phone an address but does not reflect it is told apart from no tunnel.
    func testTunnelOnButNotReflectedSaysSo() {
        let (model, _) = model()
        model.loopback.simulate(.working(ms: 12))
        model.loopback.simulate(.noAnswer)
        let text = model.coreState(of: RunnerStatus(state: "pairing")).describe
        XCTAssertTrue(text.contains("does not reflect 10.7.0.1"), text)
    }

    /// With the loopback up, the launcher's own words stand.
    func testLoopbackUpKeepsTheLauncherState() {
        let (model, _) = model()
        model.loopback.simulate(.working(ms: 9))
        XCTAssertEqual(model.coreState(of: RunnerStatus(state: "pairing")).describe, "starting (Checking pairing)")
    }

    /// A pairing refusal is kept until the phone accepts again; a disk-image refusal re-downloads.
    func testPairingRefusalThenAcceptance() {
        let (model, _) = model()
        model.runnerChanged(RunnerStatus(state: "failed", detail: "the phone refused the pairing", fix: "Pair again in Poki's setup"))
        XCTAssertNotNil(model.pairingTrouble)
        model.runnerChanged(RunnerStatus(state: "launching"))
        XCTAssertNil(model.pairingTrouble)
        XCTAssertNotNil(model.pairingVerifiedAt)
    }

    /// The agent's view of the runner follows every launcher event.
    func testHostSeesTheRunnerState() {
        let (model, _) = model()
        model.loopback.simulate(.working(ms: 9))
        sessionOpen(model)
        model.runnerChanged(RunnerStatus(state: "running"))
        XCTAssertTrue(model.host.currentRunner.isRunning)
        model.runnerChanged(RunnerStatus(state: "failed", detail: "it stopped", fix: nil))
        if case .failed(let detail, _) = model.host.currentRunner { XCTAssertEqual(detail, "it stopped") } else { XCTFail("not failed") }
    }

    /// Idle stop setting round-trips and never goes below the floor the picker offers.
    func testIdleStopSetting() {
        let (model, _) = model()
        model.idleStopSeconds = 120
        XCTAssertEqual(UserDefaults.standard.integer(forKey: AppModel.idleStopDefault), 120)
        model.idleStopSeconds = 60
    }
}

@MainActor
final class PasscodeTests: XCTestCase {
    /// After a restart iOS asks for the passcode before the first automation. The launcher says so
    /// (code "passcode"); the agent reads a plain "starting" with the reason, and the Live Activity
    /// asks the owner; the hint clears when the runner answers.
    func testPasscodeWaitIsNamedAndClears() {
        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        model.loopback.simulate(.working(ms: 9))
        model.inProcessReadyForProbe()
        model.runnerChanged(RunnerStatus(state: "launching"))
        model.runnerChanged(RunnerStatus(state: "launching", detail: "no answer for 12 s", code: "passcode"))
        XCTAssertTrue(model.passcodeHint)
        let text = model.host.currentRunner.describe
        XCTAssertTrue(text.contains("passcode"), text)
        XCTAssertTrue(text.contains("Call again"), text)
        XCTAssertTrue(text.hasPrefix("starting"), text)
        model.runnerChanged(RunnerStatus(state: "running"))
        XCTAssertFalse(model.passcodeHint)
        XCTAssertTrue(model.host.currentRunner.isRunning)
    }
}

/// The in-process session follows the work (ESP-161): opened for an agent or for the owner coming back
/// to Poki, ended after the idle time, so iOS's Automation Running banner shows only while Poki works.
@MainActor
final class InProcessIdleTests: XCTestCase {
    private var saved: (relay: String?, idle: Int, setup: SetupState)!
    private var model: AppModel!
    private var session: FakeAutomation!

    override func setUp() async throws {
        try XCTSkipUnless(AutomationPath.current == .inProcess, "Poki Runner path")
        session = FakeAutomation()
        model = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), automation: session)
        saved = (UserDefaults.standard.string(forKey: "relayAddress"), model.idleStopSeconds, SetupState.load())
        model.loopback.simulate(.working(ms: 9))
        model.setup.loopback = .proxy
        XCTAssertTrue(model.setRelay("https://relay.invalid"))
        model.idleStopSeconds = 60
        model.startSession()
        XCTAssertTrue(model.sessionOn)
    }

    override func tearDown() async throws {
        session?.answer(nil)
        guard let saved, let model else { return }
        model.stopSession()
        model.idleStopSeconds = saved.idle
        UserDefaults.standard.set(saved.relay, forKey: "relayAddress")
        saved.setup.save()
    }

    private func waitFor(_ what: String, _ condition: @escaping () -> Bool) async {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        done.expectationDescription = what
        await fulfillment(of: [done], timeout: 5)
    }

    /// An agent connects: the launcher starts and the session opens, as it did before the first look.
    private func agentConnects() async {
        model.host.warmUp()
        await waitFor("the agent's connection wakes Poki") { !self.model.runnerPaused }
        model.runnerChanged(RunnerStatus(state: "running"))
        await waitFor("the session opens") { self.session.isOpen }
    }

    func testIdleEndsTheSessionAndTheNextRequestOpensIt() async {
        await agentConnects()
        model.checkIdle(now: Date().addingTimeInterval(61))
        await waitFor("the session ends after the idle time") { !self.session.isOpen && self.model.runnerPaused }
        let waiting = model.host.runnerState().describe
        XCTAssertTrue(waiting.hasPrefix("starting"), waiting)
        await waitFor("the agent's next request opens it again") { self.session.isOpen }
        XCTAssertEqual(session.timesOpened, 2)
        XCTAssertTrue(model.host.currentRunner.isRunning, model.host.currentRunner.describe)
    }

    func testNothingButTheOwnerOrAnAgentOpensItAgain() async {
        await agentConnects()
        model.checkIdle(now: Date().addingTimeInterval(61))
        await waitFor("the session ends after the idle time") { !self.session.isOpen && self.model.runnerPaused }
        model.wentToBackground()
        model.runnerChanged(RunnerStatus(state: "running"))
        model.checkIdle(now: Date().addingTimeInterval(200))
        let stillEnded = model.coreState(of: RunnerStatus(state: "running")).describe
        XCTAssertTrue(stillEnded.contains("after it stood by"), stillEnded)
        model.becameActive()
        await waitFor("coming back to the front opens it") { self.session.isOpen }
        XCTAssertEqual(session.timesOpened, 2)
    }

    /// Remote use at any time comes first (ESP-161): an owner who never chose an idle time, or chose
    /// one before the in-process path honoured it, keeps the session open.
    func testByDefaultTheSessionIsNeverEndedForIdle() {
        for version in 1...9 { UserDefaults.standard.removeObject(forKey: "idleStopSeconds.v\(version)") }
        UserDefaults.standard.setValuesForKeys(["idleStopSeconds.v4": 60])
        let fresh = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), automation: FakeAutomation())
        XCTAssertEqual(fresh.idleStopSeconds, 0)
    }
    func testAPasscodeWaitAsksTheOwnerAndTellsTheAgentWhoMustEnterIt() async {
        session.holdNextOpen()
        model.host.warmUp()
        await waitFor("the agent's connection wakes Poki") { !self.model.runnerPaused }
        model.runnerChanged(RunnerStatus(state: "running"))
        model.checkIdle(now: Date().addingTimeInterval(6))
        XCTAssertTrue(model.passcodeHint, "Poki's home asks the owner for the passcode")
        let waiting = model.host.runnerState().describe
        XCTAssertTrue(waiting.contains("owner to enter the iPhone passcode"), waiting)
        session.answer(["ok": false, "code": "com.apple.dt.XCTest.XCTFuture 1000", "detail": "Timed out while enabling automation mode.", "seconds": 60.0])
        await waitFor("iOS gave up on the passcode") { !self.model.passcodeHint && !self.model.host.currentRunner.describe.hasPrefix("starting") }
        let failed = model.host.currentRunner.describe
        XCTAssertTrue(failed.contains("owner needs to enter the iPhone passcode"), failed)
    }
    func testColdLaunchOpensNothing() {
        model.becameActive()
        model.runnerChanged(RunnerStatus(state: "running"))
        XCTAssertTrue(model.runnerPaused, "a cold launch woke the session")
    }
}

