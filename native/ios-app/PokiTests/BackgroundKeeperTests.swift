import XCTest
@testable import Poki

@MainActor
final class BackgroundKeeperTests: XCTestCase {
    func testPausingAudioDuringRecoveryPreventsRestart() async {
        let keeper = BackgroundKeeper()
        var restarted = false
        let recovery = keeper.scheduleAudioRecovery(wait: {
            keeper.pauseAudio()
        }, recover: {
            restarted = true
        })

        await recovery.value
        XCTAssertFalse(restarted)
    }

    func testStoppingWithoutOtherHoldersCancelsRecovery() async {
        let keeper = BackgroundKeeper()
        var restarted = false
        let recovery = keeper.scheduleAudioRecovery(wait: {
            keeper.stop()
        }, recover: {
            restarted = true
        })

        await recovery.value
        XCTAssertFalse(restarted)
    }

    func testRecoveryRunsWhenAudioIsNotPaused() async {
        let keeper = BackgroundKeeper()
        var restarted = false
        let recovery = keeper.scheduleAudioRecovery(wait: {}, recover: {
            restarted = true
        })

        await recovery.value
        XCTAssertTrue(restarted)
    }
}
