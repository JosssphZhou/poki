import XCTest
@testable import PokiCore

/// A stopped call: the app's chat cancels the tool call under way when the owner taps Stop, and the
/// relay cancels a call its caller gave up on. Wherever the cancel lands, nothing more is sent to
/// the phone, and what the call had borrowed from the owner goes back.
final class CancelTests: XCTestCase {
    private let presses: JSON = ["actions": [["button": "home"], ["button": "home"], ["button": "home"]]]
    private func homePresses(_ wda: FakeWDA) -> Int { wda.sent.filter { $0 == "POST /wda/homescreen" }.count }

    /// Stop while the call still waits for the runner to start (the first call after a stand-by):
    /// the call answers at once, and the runner coming up afterwards must not set its actions off.
    func testADoStoppedWhileTheRunnerStartsSendsNothingOnceTheRunnerIsUp() async {
        let (core, wda, host) = makeCore { $0.runnerWait = 8 }
        _ = await core.call("look", [:])
        host.state.value = .starting("opening the automation session")
        let started = LockedBox(false)
        let listen = Task { for await event in core.events { if case .toolStarted(let a) = event, a.name == "do" { started.value = true } } }
        defer { listen.cancel() }
        let call = Task { await core.call("do", self.presses) }
        let began = await eventually(3) { started.value }
        XCTAssertTrue(began)
        call.cancel()
        _ = await call.value
        XCTAssertEqual(homePresses(wda), 0)
        host.state.value = .running
        // The stopped call is not there to wait for: only time shows that it stays quiet.
        let pressed = await eventually(1.5) { self.homePresses(wda) > 0 }
        XCTAssertFalse(pressed, "the stopped call's actions were sent once the runner was up: \(wda.sent)")
    }

    /// Stop while a check before the actions is with the runner (is the phone locked?).
    func testADoStoppedDuringTheChecksBeforeItsActionsSendsNothing() async {
        let (core, wda, _) = makeCore()
        _ = await core.call("look", [:])
        let checksBefore = wda.sent.filter { $0 == "GET /wda/locked" }.count
        wda.set("GET /wda/locked") { _ in try await Task.sleep(nanoseconds: 2_000_000_000); return (200, ["value": false]) }
        let call = Task { await core.call("do", ["actions": [["tap": [100, 120]]]]) }
        let checking = await eventually(3) { wda.sent.filter { $0 == "GET /wda/locked" }.count > checksBefore }
        XCTAssertTrue(checking)
        call.cancel()
        _ = await call.value
        let tapped = await eventually(1.5) { !wda.bodies("POST /wda/tap").isEmpty }
        XCTAssertFalse(tapped, "the stopped call's tap was sent: \(wda.sent)")
    }

    /// A call made by a task that is already cancelled (Stop landed between two steps).
    func testACallMadeAfterItsTaskWasStoppedSendsNothing() async {
        let (core, wda, _) = makeCore()
        _ = await core.call("look", [:])
        let go = LockedBox(false)
        let call = Task { () -> ToolResult in
            while !go.value { await Task.yield() }
            return await core.call("do", self.presses)
        }
        call.cancel()
        go.value = true
        let result = await call.value
        XCTAssertTrue(result.isError, result.text)
        XCTAssertEqual(homePresses(wda), 0, "\(wda.sent)")
    }

    /// A do stopped after an action went out has not read the screen since. The element numbers of
    /// the read before are dropped, so the next call cannot tap where an element was.
    func testElementNumbersAreDroppedAfterAStoppedDoThatSentSomething() async throws {
        let (core, wda, _) = makeCore()
        _ = await core.call("look", [:])
        wda.set("POST /wda/tap") { _ in try await Task.sleep(nanoseconds: 2_000_000_000); return (200, ["value": .null]) }
        let call = Task { await core.call("do", ["actions": [["tap": 1]]]) }
        let tapping = await eventually(3) { !wda.bodies("POST /wda/tap").isEmpty }
        XCTAssertTrue(tapping)
        call.cancel()
        _ = await call.value
        wda.set("POST /wda/tap") { _ in (200, ["value": .null]) }
        // The stopped call ends out of sight, just after its caller was answered.
        try await Task.sleep(nanoseconds: 300_000_000)
        let next = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(next.text.contains("is not in the latest read; nothing was sent"), next.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, 1, "\(wda.sent)")
    }

    /// A paste stopped part way: nothing more is sent, but the owner's clipboard still goes back.
    func testAPasteStoppedPartWayPutsTheOwnersClipboardBack() async {
        let (core, wda, _) = makeCore()
        let field = FaultTests.Field()
        field.install(wda)
        // The long press that opens the field's menu is still with the runner when Stop lands.
        wda.set("POST /wda/touchAndHold") { _ in try await Task.sleep(nanoseconds: 2_000_000_000); return (200, ["value": .null]) }
        _ = await core.call("look", [:])
        let call = Task { await core.call("do", ["actions": [["type": "密码不是这个", "via": "paste"]]]) }
        let holding = await eventually(3) { !wda.bodies("POST /wda/touchAndHold").isEmpty }
        XCTAssertTrue(holding)
        XCTAssertEqual(field.clipboard.value, "密码不是这个")
        call.cancel()
        _ = await call.value
        let restored = await eventually(3) { field.clipboard.value == "owner's clipboard" }
        XCTAssertTrue(restored, "the owner's clipboard was left holding the pasted text")
        XCTAssertEqual(field.value.value, "", "the paste went on after the stop")
    }
}
