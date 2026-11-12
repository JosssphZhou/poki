import Foundation
import PokiCore
import XCTest
@testable import Poki

/// Poki opens its own automation session before an agent needs it (ESP-152). When that fails (the
/// owner cancelled the passcode, testmanagerd did not answer within 3 s), an agent's call hears why at
/// once and asks for another try, instead of every call waiting out "opening the session".
final class InProcessSessionTests: XCTestCase {
    func testAFailedOpenIsAnsweredWithItsReasonAndTheCallTriesAgain() {
        let host = AppCoreHost()
        let tries = Tries()
        host.onRetry { tries.add() }
        host.update(runner: InProcessSession.failed(code: "session_timeout", detail: "").agentState)

        let state = host.runnerState()

        guard case .failed(let detail, let fix) = state else { return XCTFail("the agent reads \(state.describe)") }
        XCTAssertTrue(detail.contains("session_timeout"), detail)
        XCTAssertNotNil(fix)
        XCTAssertEqual(tries.count, 1, "the call asks Poki to open the session again")
    }

    /// Issue 208: the developer disk image's XCTest library would not load, with the image's services
    /// answering. Once Poki's own tries are used up, the agent hears iOS's loader error and what
    /// happened, and the owner is asked for the log: not "enter the passcode", which iOS never asked
    /// for, nor "the image is not mounted", which the services answering disproves.
    func testAFrameworkThatWouldNotLoadIsAnsweredWithWhatHappenedAndAnAskForTheLog() {
        let loader = "dlopen(/System/Developer/usr/lib/lib_TestingInterop.dylib, 0x000A): the loader's reason"
        let state = InProcessSession.failed(code: "developer_framework_unavailable", detail: "developer_framework_unavailable (\(loader))").agentState

        guard case .failed(let detail, let fix) = state else { return XCTFail("the agent reads \(state.describe)") }
        XCTAssertTrue(detail.contains(loader), detail)
        XCTAssertFalse(detail.contains("not mounted"), detail)
        XCTAssertFalse((fix ?? "").contains("passcode"), fix ?? "")
        XCTAssertTrue((fix ?? "").contains("Share Log"), fix ?? "")
    }

    /// Seen on the phone: the banner up and the session open, while every look answered "still
    /// starting", because nothing asked for another open. A call that finds it opening asks too.
    func testACallThatFindsTheSessionStillOpeningAsksForAnOpen() {
        let host = AppCoreHost()
        let tries = Tries()
        host.onRetry { tries.add() }
        host.update(runner: InProcessSession.opening.agentState)

        let state = host.runnerState()

        guard case .starting = state else { return XCTFail("the agent reads \(state.describe)") }
        XCTAssertEqual(tries.count, 1, "the call asks Poki to open the session")
    }
}

private final class Tries: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func add() { lock.withLock { value += 1 } }
}
