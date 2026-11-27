import XCTest
@testable import Poki

@MainActor
final class LoopbackRecoveryTests: XCTestCase {
    @MainActor
    private final class Fixture {
        var active = true
        var configured = true
        var working = false
        var probeResponds = true
        var checkedAt: Date?
        var launches = 0
        var failures = 0
        var interrupted: [LoopbackRecovery.Demand] = []
        var allowed: Set<LoopbackRecovery.Demand> = [.screenHistory, .automation, .pairing, .automaticSigning, .signing]
        var needed: Set<LoopbackRecovery.Demand> = [.screenHistory, .automation, .pairing, .automaticSigning, .signing]
        var onLaunch: () -> Void = {}
        var cooldown = Duration.zero

        lazy var recovery = LoopbackRecovery(
            confirmation: .milliseconds(15), timeout: .milliseconds(35),
            cooldown: cooldown, interval: .milliseconds(2),
            active: { [unowned self] in active }, canRun: { [unowned self] in configured },
            canInterrupt: { [unowned self] in
                interrupted.append($0)
                return allowed.contains($0)
            },
            stillNeeded: { [unowned self] in needed.contains($0) },
            status: { [unowned self] in (working, checkedAt) },
            check: { [unowned self] in if probeResponds { checkedAt = Date() } },
            launch: { [unowned self] in launches += 1; onLaunch() },
            onFailure: { [unowned self] in failures += 1 }
        )

        func answer(_ connected: Bool) {
            working = connected
            checkedAt = Date()
        }

        func returnConnected() {
            answer(true)
            recovery.returnedFromShortcut()
        }
    }

    func testEachBlockedOperationCanRestoreTheConnection() async {
        for demand in [LoopbackRecovery.Demand.screenHistory, .automation, .pairing, .automaticSigning, .signing] {
            let f = Fixture()
            f.onLaunch = { [unowned f] in f.returnConnected() }
            let connected = await f.recovery.restore(for: demand)
            XCTAssertTrue(connected, "\(demand) must resume when its new probe answers")
            XCTAssertEqual(f.launches, 1)
            XCTAssertEqual(f.failures, 0)
        }
    }

    func testConcurrentWaitersShareOneAttemptAndTimeout() async {
        let f = Fixture()
        async let history = f.recovery.restore(for: .screenHistory)
        async let signing = f.recovery.restore(for: .signing)
        let (historyRestored, signingRestored) = await (history, signing)
        XCTAssertFalse(historyRestored)
        XCTAssertFalse(signingRestored)
        XCTAssertEqual(f.launches, 1)
        XCTAssertEqual(f.failures, 1)
        XCTAssertTrue(f.recovery.failurePending)

        f.recovery.dismissFailure()
        let retried = await f.recovery.restore(for: .automation)
        XCTAssertFalse(retried)
        XCTAssertEqual(f.launches, 1, "Foreground and runner retries must not reopen Shortcuts during the same outage")
        XCTAssertFalse(f.recovery.failurePending)
    }

    func testDoesNotOpenInBackgroundOrWhenOnlyUnrelatedWorkIsActive() async {
        let f = Fixture()
        f.active = false
        let background = await f.recovery.restore(for: .automation)
        f.active = true
        f.allowed = [.automation]
        let history = await f.recovery.restore(for: .screenHistory)
        let preparation = await f.recovery.restore(for: .automaticSigning)
        XCTAssertFalse(background)
        XCTAssertFalse(history)
        XCTAssertFalse(preparation)
        XCTAssertEqual(f.launches, 0)
        XCTAssertEqual(f.failures, 0)

        f.onLaunch = { [unowned f] in f.returnConnected() }
        let foreground = await f.recovery.restore(for: .automation)
        XCTAssertTrue(foreground)
        XCTAssertEqual(f.launches, 1)
    }

    func testNoShortcutIfProbeHasNotAnsweredOrShortcutIsNotConfigured() async {
        let f = Fixture()
        f.probeResponds = false
        f.answer(false)
        let unconfirmed = await f.recovery.restore(for: .screenHistory)
        f.probeResponds = true
        f.configured = false
        let unconfigured = await f.recovery.restore(for: .screenHistory)
        XCTAssertFalse(unconfirmed)
        XCTAssertFalse(unconfigured)
        XCTAssertEqual(f.launches, 0)
        XCTAssertEqual(f.failures, 0)
    }

    func testSigningDoesNotUseAWorkingProbeFromBeforePreflight() async {
        let f = Fixture()
        f.answer(true)
        f.probeResponds = false
        let connected = await f.recovery.restore(for: .signing)
        XCTAssertFalse(connected, "A previous good probe does not authorize an install")
        XCTAssertEqual(f.launches, 0, "An unanswered check is not a confirmed outage")
    }

    func testWaitsForForegroundBeforeResumingSigning() async {
        let f = Fixture()
        f.onLaunch = { [unowned f] in
            f.active = false
            f.returnConnected()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(8))
                f.active = true
            }
        }
        let connected = await f.recovery.restore(for: .signing)
        XCTAssertTrue(connected)
        XCTAssertTrue(f.active)
        XCTAssertEqual(f.failures, 0)
    }

    func testDoesNotResumeSigningWhileShortcutHasNotReturned() async {
        let f = Fixture()
        f.onLaunch = { [unowned f] in f.answer(true) }
        let connected = await f.recovery.restore(for: .signing)
        XCTAssertFalse(connected)
        XCTAssertEqual(f.failures, 1, "Working mid-shortcut is not a finished handoff")
    }

    func testConfirmedRestorationRearmsOnlyAfterCooldown() async {
        let f = Fixture()
        f.cooldown = .seconds(60)
        f.onLaunch = { [unowned f] in f.returnConnected() }
        let first = await f.recovery.restore(for: .screenHistory)
        XCTAssertTrue(first)
        f.recovery.connectionRestored()
        f.answer(false)
        let flap = await f.recovery.restore(for: .automation)
        XCTAssertFalse(flap)
        XCTAssertEqual(f.launches, 1)
        XCTAssertEqual(f.failures, 0)

        let g = Fixture()
        _ = await g.recovery.restore(for: .screenHistory)
        g.recovery.connectionRestored()
        g.onLaunch = { [unowned g] in g.returnConnected() }
        let nextOutage = await g.recovery.restore(for: .signing)
        XCTAssertTrue(nextOutage)
        XCTAssertEqual(g.launches, 2)
    }

    func testHistoryCanResumeOnItsRetainedTunnelWithoutGivingSigningAFalseSuccess() async {
        let f = Fixture()
        f.onLaunch = { [unowned f] in f.needed.remove(.screenHistory) }
        let restored = await f.recovery.restore(for: .screenHistory)
        XCTAssertFalse(restored, "A working Screen History tunnel does not prove a new connection can open")
        XCTAssertEqual(f.launches, 1)
        XCTAssertEqual(f.failures, 0, "The recorder no longer waits for loopback")
    }

    func testAnEnabledRecorderRequestsRecoveryWhenItsOwnTunnelStops() async throws {
        let enabled = UserDefaults.standard.object(forKey: HistoryCapture.enabledKey)
        let capture = HistoryCapture()
        let original = capture.enabled
        defer {
            capture.enabled = original
            UserDefaults.standard.set(enabled, forKey: HistoryCapture.enabledKey)
        }
        capture.enabled = true
        let storage = try IsolatedTestStorage()
        defer { try? storage.tearDown() }
        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: storage.storage)
        model.loopback.simulate(.off)
        let f = Fixture()
        model.loopbackRecovery = f.recovery
        let opened = expectation(description: "an actual recorder tunnel loss requested the shortcut")
        f.onLaunch = { [unowned f] in
            capture.observeLoopback(connected: true, model: model)
            f.needed.remove(.screenHistory)
            opened.fulfill()
        }
        capture.observeLoopback(connected: true, model: model)
        XCTAssertFalse(capture.needsLoopbackRecovery)
        capture.observeLoopback(connected: false, model: model)
        XCTAssertTrue(capture.needsLoopbackRecovery)
        await fulfillment(of: [opened], timeout: 1)
        XCTAssertFalse(capture.needsLoopbackRecovery)
        XCTAssertEqual(f.launches, 1)
    }

    func testForegroundResumesRunnerWaitingToRemountItsImage() async throws {
        let storage = try IsolatedTestStorage()
        defer { try? storage.tearDown() }
        let launcher = FakeLauncher()
        let model = AppModel(launcher: launcher, pairer: FakePairing(), automation: FakeAutomation(),
                             imageMounted: { false }, storage: storage.storage)
        defer { model.stopSession(); model.loopback.pause() }
        model.setup.loopback = .proxy
        XCTAssertTrue(model.setRelay("https://relay.invalid"))
        model.startSession()
        model.prepareForTask()
        XCTAssertFalse(model.runnerPaused)
        model.wentToBackground()
        model.loopback.simulate(.off)

        let f = Fixture()
        model.loopbackRecovery = f.recovery
        let opened = expectation(description: "foreground retried the blocked disk image mount")
        f.onLaunch = { [unowned f] in
            model.loopback.simulate(.working(ms: 10))
            f.returnConnected()
            opened.fulfill()
        }
        model.runnerChanged(RunnerStatus(state: "waiting_network", code: "loopback"))
        XCTAssertEqual(f.launches, 0)
        model.becameActive()
        await fulfillment(of: [opened], timeout: 2)
        XCTAssertEqual(f.interrupted, [.automation, .automation])
        XCTAssertEqual(launcher.restarts, 1)
    }

    func testShortcutURLReturnsToPokiRegardlessOfOutcome() throws {
        let components = try XCTUnwrap(URLComponents(url: LoopbackShortcut.recoveryRun, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "shortcuts")
        XCTAssertEqual(components.host, "x-callback-url")
        XCTAssertEqual(components.path, "/run-shortcut")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["name"] ?? nil, "Poki Loopback")
        for key in ["x-success", "x-cancel", "x-error"] {
            XCTAssertEqual(items[key] ?? nil, LoopbackShortcut.recoveryReturn.absoluteString)
        }
    }
}
