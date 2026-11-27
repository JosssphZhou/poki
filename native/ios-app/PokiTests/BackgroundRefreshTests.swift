import XCTest
@testable import Poki

@MainActor
final class BackgroundRefreshTests: XCTestCase {
    func testDeliveredRefreshAfterStopDoesNotWakeOrReschedule() {
        let handled = BackgroundRefresh.handleWake(shouldContinue: false, scheduleNext: {
            XCTFail("An idle refresh must not schedule another request")
        }, onWake: {
            XCTFail("An idle refresh must not wake the keeper")
        })
        XCTAssertFalse(handled)
    }

    func testEnabledRefreshWakesAndSchedulesNextRequest() {
        var scheduled = false
        var woke = false
        let handled = BackgroundRefresh.handleWake(shouldContinue: true, scheduleNext: {
            scheduled = true
        }, onWake: {
            woke = true
        })
        XCTAssertTrue(handled)
        XCTAssertTrue(scheduled)
        XCTAssertTrue(woke)
    }
}
