import Foundation
import PokiCore
import XCTest
@testable import Poki

/// Poki opens its own automation session when a call needs it (ESP-152). The call that waited on an
/// open that failed hears why and ends; the next call asks for a new open and waits for it, instead
/// of hearing the old failure again while an open nobody waits for starts behind it.
final class InProcessSessionTests: XCTestCase {
    func testCompanionSparseContentNeedsOneDistinctiveLabelOnTheTargetSide() {
        let left: Set<String> = ["fullscreenpreviews"]
        let chat: Set<String> = ["opencapturesettings"]
        let target: Set<String> = ["settings", "fullscreenpreviews"]
        XCTAssertTrue(PKCompanionContentMatches([left, chat], target, "settings", false))
        XCTAssertFalse(PKCompanionContentMatches([left, chat], target, "settings", true))
        XCTAssertFalse(PKCompanionContentMatches([left, left], target, "settings", false))
        XCTAssertFalse(PKCompanionContentMatches([["averylongappname"], []], ["averylongappname"], "averylongappname", false))
    }

    func testCalculatorRequiresAKeypadOnlyOnTheSelectedSide() {
        XCTAssertTrue(PKCalculatorKeypadMatches(0, 4, true))
        XCTAssertTrue(PKCalculatorKeypadMatches(4, 1, false))
        XCTAssertFalse(PKCalculatorKeypadMatches(4, 0, true))
        XCTAssertFalse(PKCalculatorKeypadMatches(4, 4, true))
        XCTAssertFalse(PKCalculatorKeypadMatches(0, 3, true))
    }

    func testWorkspaceLauncherIgnoresDuplicateSystemEntriesAndTheMatchingWidgetLabel() {
        let icon = NSValue(cgRect: CGRect(x: 100, y: 250, width: 86, height: 86))
        let offPage = NSValue(cgRect: CGRect(x: 490, y: 720, width: 160, height: 162))
        let title = NSValue(cgPoint: CGPoint(x: 587, y: 323))
        let widget = NSValue(cgPoint: CGPoint(x: 120, y: 550))
        let point = PKWorkspaceLauncherPoint(["备忘录": [offPage, icon, icon]], ["备忘录": [widget, title]], false, .identity)
        XCTAssertEqual(point, CGPoint(x: 587, y: 287))
    }

    func testWorkspaceLauncherRefusesTwoVisibleIconsWithTheSameName() {
        let icon = NSValue(cgRect: CGRect(x: 100, y: 250, width: 86, height: 86))
        let labels = [NSValue(cgPoint: CGPoint(x: 587, y: 323)), NSValue(cgPoint: CGPoint(x: 690, y: 323))]
        XCTAssertTrue(PKWorkspaceLauncherPoint(["备忘录": [icon]], ["备忘录": labels], false, .identity).x.isNaN)
    }

    func testWorkspaceLauncherMatchesFixedPortraitFramesToLandscapeLabels() {
        let icon = NSValue(cgRect: CGRect(x: 52, y: 822, width: 86, height: 68))
        let title = NSValue(cgPoint: CGPoint(x: 95, y: 126))
        let toFixed = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 951)
        let point = PKWorkspaceLauncherPoint(["Settings": [icon, icon]], ["Settings": [title]], false, toFixed.inverted())
        XCTAssertEqual(point, CGPoint(x: 95, y: 89))
    }

    func testACallThatBeginsOnAFailedOpenAsksForANewOneAndWaits() {
        let host = AppCoreHost()
        let tries = Tries()
        host.onRetry { tries.add() }
        host.update(runner: InProcessSession.failed(code: "session_timeout", detail: "").agentState)

        let state = host.runnerState()

        guard case .starting = state else { return XCTFail("the agent reads \(state.describe)") }
        XCTAssertEqual(tries.count, 1, "the call asks Poki to open the session again")
        let noRetry = AppCoreHost()
        noRetry.update(runner: InProcessSession.failed(code: "session_timeout", detail: "").agentState)
        guard case .failed(let detail, let fix) = noRetry.runnerState() else { return XCTFail("without a retry the failure is answered as it is") }
        XCTAssertTrue(detail.contains("session_timeout"), detail)
        XCTAssertNotNil(fix)
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
