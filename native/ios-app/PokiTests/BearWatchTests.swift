import XCTest
@testable import Poki

/// The bear watching you type: it looks down at the caret, now and then looks away to its own small
/// things, and goes into and out of the look without a jump.
final class BearWatchTests: XCTestCase {
    /// The spring never overshoots and settles, at the slow rate the bear is drawn while it only breathes.
    func testTheFollowSettlesWithoutOvershoot() {
        var follow = BearFollow()
        for _ in 0..<40 {
            follow.step(to: 1, dt: 0.1, response: 0.6)
            XCTAssertLessThanOrEqual(follow.value, 1.0001)
        }
        XCTAssertTrue(follow.settled(at: 1))
    }

    /// Without a caret there is no look.
    func testNoTypingNoLook() {
        var watch = BearWatch()
        for frame in 0..<300 { _ = watch.update(at: Double(frame) / 30, dt: 1.0 / 30, calm: false, glancing: false) }
        XCTAssertEqual(watch.pose, BearIdle.Pose())
    }

    /// Thirty seconds of typing to the bear's right: it looks down and to that side, looks away at
    /// least once and comes back, and from one frame to the next the head moves only a little.
    func testItWatchesTheCaretOnAndOff() {
        var idle = BearIdle(now: 0)
        idle.watch.caret = SIMD2(120, 500)
        var last = idle.pose(at: 0)
        var looks = 0, looking = false, mostDown: Float = 0, mostTurned: Float = 0
        for frame in 1...900 {
            let pose = idle.pose(at: Double(frame) / 30)
            XCTAssertLessThan(abs(pose.headPitch - last.headPitch), 0.04, "frame \(frame)")
            XCTAssertLessThan(abs(pose.headYaw - last.headYaw), 0.06, "frame \(frame)")
            mostDown = max(mostDown, pose.headPitch)
            mostTurned = max(mostTurned, pose.headYaw)
            let down = pose.headPitch > 0.1
            if down, !looking { looks += 1 }
            looking = down
            last = pose
        }
        XCTAssertGreaterThan(mostDown, 0.12, "it looks down at the field")
        XCTAssertGreaterThan(mostTurned, 0.1, "toward the caret's side")
        XCTAssertGreaterThanOrEqual(looks, 2, "it looks away and comes back")
    }

    /// The typing stops: the look goes away, softly.
    func testTheLookFadesWhenTypingStops() {
        var idle = BearIdle(now: 0)
        idle.watch.caret = SIMD2(0, 500)
        for frame in 1...30 { _ = idle.pose(at: Double(frame) / 30) }
        XCTAssertTrue(idle.watch.following)
        idle.watch.caret = nil
        for frame in 31...120 { _ = idle.pose(at: Double(frame) / 30) }
        XCTAssertFalse(idle.watch.following)
        XCTAssertLessThan(idle.watch.pose.headPitch, 0.01)
    }

    /// At work or talking the bear keeps its own stance.
    func testACalmBearDoesNotWatch() {
        var idle = BearIdle(now: 0)
        idle.calm = true
        idle.watch.caret = SIMD2(0, 500)
        for frame in 1...90 { _ = idle.pose(at: Double(frame) / 30) }
        XCTAssertFalse(idle.watch.following)
    }
}
