import PokiCore
import XCTest
@testable import Poki

final class AutomaticTaskApprovalsTests: XCTestCase {
    func testAutomaticFloorCannotDisableAskingOrWeakenAStrongerLevel() {
        let policy = AutomaticTaskApprovals()
        let token = policy.begin()
        defer { policy.end(token) }
        XCTAssertEqual(policy.effective((.off, .permissive)).mode, .confirm)
        XCTAssertEqual(policy.effective((.off, .permissive)).level, .balanced)
        for mode in [ApprovalMode.confirm, .reply] {
            for level in ApprovalLevel.allCases {
                let value = policy.effective((mode, level))
                XCTAssertEqual(value.mode, mode)
                XCTAssertEqual(value.level, level == .permissive ? .balanced : level)
            }
        }
    }

    func testEndingAnOlderRunCannotDropANewerRunsFloor() {
        let policy = AutomaticTaskApprovals()
        let first = policy.begin(), next = policy.begin()
        policy.end(first)
        XCTAssertEqual(policy.effective((.off, .permissive)).mode, .confirm)
        policy.end(next)
        XCTAssertEqual(policy.effective((.off, .permissive)).mode, .off)
        XCTAssertEqual(policy.effective((.off, .permissive)).level, .permissive)
    }
}
