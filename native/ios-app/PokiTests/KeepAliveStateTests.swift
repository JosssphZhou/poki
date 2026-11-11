import XCTest
@testable import Poki

/// GitHub #165: an interruption stops the silent audio's engine without releasing it. Poki took the
/// engine being there for the audio playing, turned location off, and was suspended in the background.
final class KeepAliveStateTests: XCTestCase {
    private func holder(continuedRun: Bool = false, voice: Bool = false, engine: Bool, running: Bool, playing: Bool, interrupted: Bool = false) -> KeepAliveState.Holder? {
        KeepAliveState(on: true, continuedRun: continuedRun, voice: voice,
                       audio: .init(engine: engine, running: running, playerPlaying: playing, interrupted: interrupted)).holder
    }

    func testOnlyPlayingAudioHoldsPokiUp() {
        XCTAssertEqual(holder(engine: true, running: true, playing: true), .silentAudio)
        XCTAssertEqual(holder(engine: true, running: false, playing: false), .nothing, "engine stopped by an interruption or a route change")
        XCTAssertEqual(holder(engine: true, running: true, playing: false), .nothing, "engine running, player stopped")
        XCTAssertEqual(holder(engine: false, running: false, playing: false), .nothing, "audio never started")
        XCTAssertEqual(holder(continuedRun: true, engine: false, running: false, playing: false), .continuedRun)
        XCTAssertEqual(holder(voice: true, engine: false, running: false, playing: false), .voice)
        XCTAssertNil(KeepAliveState(on: false, continuedRun: false, voice: false, audio: .off).holder)
    }

    /// GitHub #165, a missed WeChat call: the interruption ended, the engine was started again in place,
    /// Poki logged the audio back and turned location off, and was suspended. After an interruption the
    /// engine's flags are no proof it plays; only a start from scratch is.
    func testInterruptedAudioHoldsNothingUntilStartedAgainFromScratch() {
        XCTAssertEqual(holder(engine: true, running: true, playing: true, interrupted: true), .nothing)
    }
}
