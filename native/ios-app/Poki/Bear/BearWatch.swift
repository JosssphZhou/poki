import CoreGraphics
import Foundation
import QuartzCore
import simd

/// Where the message field's caret is while someone types in it, in window points, for the bear to
/// look at (`BearWatch`). The field notes the caret on every edit and every move of the caret, and
/// lets go when it loses the keyboard. Only typing wakes the bear's interest: a caret that sits still
/// with no new letters for `quiet` seconds is not watched.
@MainActor
final class CaretWatch {
    static let shared = CaretWatch()

    /// Seconds without a keystroke after which the bear stops watching.
    static let quiet: TimeInterval = 5

    private var point: CGPoint?
    private var typed: TimeInterval = -.infinity

    /// The caret moved: tapped elsewhere, or the message scrolled.
    func moved(to point: CGPoint?) {
        guard self.point != nil else { return }
        self.point = point
    }

    /// A letter typed or taken away, with the caret where it is now.
    func typed(at point: CGPoint?) {
        self.point = point
        typed = CACurrentMediaTime()
    }

    /// The field lost the keyboard.
    func clear() {
        point = nil
        typed = -.infinity
    }

    /// The caret, while someone is typing.
    func caret(at now: TimeInterval) -> CGPoint? {
        guard let point, now - typed < Self.quiet else { return nil }
        return point
    }
}

/// A value that follows its target as a critically damped spring: it sets off gently, never
/// overshoots and settles without a jump, whatever the frame rate. Solved exactly for each step, so a
/// slow frame (the bear is drawn ten times a second while it only breathes) does not throw it.
struct BearFollow: Equatable {
    var value: Float = 0
    var speed: Float = 0

    mutating func step(to target: Float, dt: Float, response: Float) {
        guard dt > 0 else { return }
        let w = 2 * Float.pi / response, e = value - target, k = speed + w * e, d = exp(-w * dt)
        value = target + (e + k * dt) * d
        speed = (speed - w * k * dt) * d
    }

    func settled(at target: Float) -> Bool { abs(value - target) < 0.004 && abs(speed) < 0.02 }
}

/// The bear watching you type (the owner, 2026-11-15): once you start typing it looks down at the
/// message field, its head a little after the caret and its eyes right on it, and every few seconds
/// it looks away and goes back to its own small things, then comes back to the caret. Into the watch
/// and out of it, the head and the eyes go on springs that start and stop softly, and a small thing
/// it was doing when typing began fades out as the look comes in, so nothing jumps. It watches only
/// while it stands ready (not at work, talking or asking), and stops once the typing pauses.
struct BearWatch {
    /// The caret, from the bear's middle, in points: across (right is positive) and down. Nil while
    /// no one types.
    var caret: SIMD2<Float>?

    /// Looking at the caret now, rather than in a pause between looks.
    private(set) var following = false
    /// Typing was going on at the last frame.
    private var engaged = false
    /// When this look, or this pause, ends.
    private var phaseEnd: TimeInterval = 0
    /// How much of the look shows, 0 to 1.
    private var attention = BearFollow()
    /// Where the head and the eyes point across, -1 to 1: the head slower, the eyes quick.
    private var head = BearFollow(), eyes = BearFollow()
    private var aim: Float = 0

    /// How long a look at the caret lasts, and a pause between two.
    static let look: ClosedRange<TimeInterval> = 2.5...5
    static let pause: ClosedRange<TimeInterval> = 1.8...3.5
    /// How far the head nods down to the field, and turns at the most, in radians; how far the pupils
    /// go across and down, as `BearIdle.Pose.gaze` has them.
    static let nod: Float = 0.14
    static let turn: Float = 0.22
    static let gaze = SIMD2<Float>(0.008, -0.006)

    enum Change { case none, began, ended }

    /// One frame on: `calm` while the bear plays a state of its own, and `glancing` while one of its
    /// small things is under way. Says whether a look began (the small thing gives way to it at the
    /// first look only; later ones wait for it to end) or ended.
    mutating func update(at t: TimeInterval, dt: TimeInterval, calm: Bool, glancing: Bool) -> Change {
        var change = Change.none
        if let caret, !calm {
            // Toward the caret from where the head is: seen from the bear's middle, how far across it
            // is for how far down, as a share of the farthest turn.
            aim = min(max(atan2(caret.x, max(caret.y, 60)) / 0.3, -1), 1)
            if !engaged {
                engaged = true
                following = true
                phaseEnd = t + .random(in: Self.look)
                change = .began
            } else if t >= phaseEnd {
                if following {
                    following = false
                    phaseEnd = t + .random(in: Self.pause)
                    change = .ended
                } else if !glancing {
                    following = true
                    phaseEnd = t + .random(in: Self.look)
                    change = .began
                }
            }
        } else if engaged {
            engaged = false
            if following { change = .ended }
            following = false
        }
        let step = Float(min(max(dt, 0), 0.25))
        attention.step(to: following ? 1 : 0, dt: step, response: following ? 0.6 : 0.8)
        head.step(to: aim, dt: step, response: 0.7)
        eyes.step(to: aim, dt: step, response: 0.25)
        return change
    }

    /// A tap's hi: the look gives way to it, and comes back after a pause.
    mutating func pause(at t: TimeInterval) {
        guard following else { return }
        following = false
        phaseEnd = t + .random(in: Self.pause)
    }

    /// Still on the way into a look or out of it, or following a caret that moved: worth drawing at the
    /// full rate.
    var moving: Bool {
        !attention.settled(at: following ? 1 : 0) || (attention.value > 0.01 && (!head.settled(at: aim) || !eyes.settled(at: aim)))
    }

    /// The look, laid on top of the rest. The head is lowered toward the field and turned toward the
    /// caret, the body a little with it; the resting paws turn down a little, out of the way of the
    /// lowered head, the one on the side it turns to more.
    var pose: BearIdle.Pose {
        let w = min(max(attention.value, 0), 1)
        var p = BearIdle.Pose()
        guard w > 0.0005 else { return p }
        let across = min(max(head.value, -1), 1), look = min(max(eyes.value, -1), 1)
        p.headPitch = Self.nod * w
        p.headYaw = Self.turn * across * w
        p.bodyYaw = 0.04 * across * w
        p.gaze = SIMD2(Self.gaze.x * look, Self.gaze.y) * w
        p.lower = SIMD2(0.05 + 0.1 * max(across, 0), 0.05 + 0.1 * max(-across, 0)) * w
        return p
    }
}
