import SwiftUI

/// Poki, one picture per pose (Poki/BearPoses), with the small motion that keeps it alive: it breathes, it
/// blinks, and each pose has its own habit (a tilt while thinking, a bob while it uses the phone). The
/// motion is a function of the time alone, so every Poki on screen moves together and nothing has to be
/// started or stopped. Reduce Motion holds it still.
struct PokiBear: View {
    var pose: String
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            let move = Move(pose: pose, at: t)
            Image("Pose-\(pose)").resizable().scaledToFit()
                .overlay {
                    if !still, Self.blinks(at: t), let eyes = Self.eyes[pose] {
                        GeometryReader { geo in
                            ForEach(eyes.indices, id: \.self) { i in Lid(eye: eyes[i], size: geo.size) }
                        }
                    }
                }
                .visualEffect { content, proxy in
                    content
                        .scaleEffect(x: move.wide, y: move.tall, anchor: .bottom)
                        .rotationEffect(.degrees(move.tilt), anchor: .bottom)
                        .offset(y: -proxy.size.height * move.lift)
                }
        }
        .accessibilityHidden(true)
    }

    /// Where the pose's weight goes at a moment: all small, and all about the feet.
    struct Move {
        var wide = 1.0, tall = 1.0, tilt = 0.0, lift = 0.0

        init(pose: String, at t: Double) {
            func wave(_ seconds: Double) -> Double { sin(t / seconds * 2 * .pi) }
            // Breathing: taller as it breathes in, a little narrower.
            let breath = wave(pose == "sleep" ? 5.6 : 4.2)
            tall = 1 + (pose == "sleep" ? 0.02 : 0.012) * breath
            wide = 1 - 0.004 * breath
            switch pose {
            case "think", "search": tilt = 1.8 * wave(3)
            case "listen": tilt = 1.4 * wave(2.4)
            case "wave": tilt = 2.6 * wave(0.9)
            case "phone": lift = 0.012 * pow(max(0, wave(1.1)), 2)
            case "happy": lift = 0.022 * abs(wave(1.4))
            case "speak": tall += 0.012 * wave(0.45)
            default: break
            }
        }
    }

    /// Two rhythms that do not divide each other, so the blinks never feel timed.
    static func blinks(at t: Double) -> Bool {
        t.truncatingRemainder(dividingBy: 4.6) < 0.13 || (t + 1.9).truncatingRemainder(dividingBy: 11.3) < 0.13
    }

    /// One eye: its box as shares of the picture, and the fur's colour just above and below it. Measured
    /// from the pictures by the prototype (`design/app-prototype/js/bear-art.js`).
    struct Eye {
        var x, y, w, h: Double
        var top, bottom: Color
        init(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ top: (Double, Double, Double), _ bottom: (Double, Double, Double)) {
            self.x = x / 100; self.y = y / 100; self.w = w / 100; self.h = h / 100
            self.top = Color(red: top.0 / 255, green: top.1 / 255, blue: top.2 / 255)
            self.bottom = Color(red: bottom.0 / 255, green: bottom.1 / 255, blue: bottom.2 / 255)
        }
    }

    /// The poses that blink. Poki hides its eyes, smiles them shut or sleeps in the others.
    static let eyes: [String: [Eye]] = [
        "rest": [Eye(27.84, 39.35, 18.41, 19.46, (248, 249, 253), (237, 238, 251)), Eye(53.2, 39.33, 18.72, 19.77, (250, 250, 253), (238, 240, 250))],
        "think": [Eye(31.12, 30.59, 15.77, 17.61, (211, 216, 243), (243, 245, 251)), Eye(62.53, 39.49, 15.51, 17.61, (204, 211, 240), (247, 248, 251))],
        "phone": [Eye(30.76, 45.68, 15.45, 14.92, (251, 251, 251), (209, 219, 250)), Eye(53.82, 48.06, 15.14, 15.14, (250, 250, 252), (211, 219, 249))],
        "ask": [Eye(25.12, 42.4, 15.99, 17.3, (248, 247, 251), (233, 235, 250)), Eye(47.37, 42.92, 15.99, 17.3, (250, 250, 251), (232, 236, 249))],
        "worry": [Eye(32.62, 46.75, 15.14, 15.14, (252, 252, 252), (225, 230, 249)), Eye(58.51, 50.13, 15.18, 15.45, (228, 231, 247), (216, 224, 249))],
        "listen": [Eye(24.91, 35.12, 15.37, 16.68, (237, 240, 249), (224, 228, 249)), Eye(51.27, 42.9, 15.77, 17.61, (238, 239, 249), (227, 231, 248))],
        "speak": [Eye(27.36, 37.83, 17.53, 18.84, (243, 244, 251), (237, 239, 251)), Eye(54.61, 38.64, 16.44, 18.53, (249, 250, 253), (242, 243, 253))],
        "wave": [Eye(24.81, 40.52, 16.87, 17.92, (248, 250, 251), (240, 242, 252)), Eye(48.66, 38.71, 16.82, 17.61, (252, 252, 253), (240, 241, 251))],
    ]

    /// A closed eye: the fur's colour over the eye, and the line the lashes make.
    private struct Lid: View {
        var eye: Eye
        var size: CGSize
        var body: some View {
            let w = eye.w * size.width, h = eye.h * size.height
            ZStack {
                Ellipse().fill(LinearGradient(colors: [eye.top, eye.bottom], startPoint: .top, endPoint: .bottom))
                Capsule().fill(Color(red: 0.24, green: 0.17, blue: 0.17)).frame(width: w * 0.62, height: max(1, h * 0.1)).offset(y: h * 0.1)
            }
            .frame(width: w, height: h)
            .position(x: (eye.x + eye.w / 2) * size.width, y: (eye.y + eye.h / 2) * size.height)
        }
    }
}
