import SwiftUI

/// Poki's window: a sky that falls from deep colour to a warm light at the ground, with Poki sitting on
/// the ground. The pools of colour drift slowly, so the window breathes by colour and not by brightness.
/// It draws at any size, from the page's window down to Poki's place on the New chat button.
struct SkyWindow: View {
    var pose: String = "rest"
    /// The bear's width as a share of the window's.
    var bear: CGFloat = 0.36
    var radius: CGFloat = 44
    @AppStorage(PokiLight.key) private var light = PokiLight.firstLight.rawValue
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let colors = (PokiLight(rawValue: light) ?? .firstLight).palette
        TimelineView(.animation(minimumInterval: 1 / 20, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(stops: [.init(color: colors.deep, location: 0), .init(color: colors.sky, location: 0.2),
                                           .init(color: colors.skyLight, location: 0.42), .init(color: colors.mid, location: 0.6),
                                           .init(color: colors.low, location: 0.78), .init(color: colors.warm, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    // The cool pool, low on the left; the warm light, low on the right.
                    Ellipse().fill(RadialGradient(colors: [colors.low, colors.low.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.4))
                        .frame(width: w * 0.8, height: h * 0.56)
                        .position(x: w * (0.2 + 0.03 * sin(t / 11 * 2 * .pi)), y: h * (0.66 + 0.02 * cos(t / 11 * 2 * .pi)))
                        .blur(radius: min(30, w * 0.09))
                    Ellipse().fill(RadialGradient(stops: [.init(color: colors.warmLight, location: 0.08), .init(color: colors.warm, location: 0.52),
                                                          .init(color: colors.warm.opacity(0), location: 1)],
                                                  center: .center, startRadius: 0, endRadius: w * 0.35))
                        .frame(width: w * 0.7, height: h * 0.58)
                        .position(x: w * (0.75 + 0.025 * cos(t / 9 * 2 * .pi)), y: h * (0.79 + 0.02 * sin(t / 9 * 2 * .pi)))
                        .blur(radius: min(30, w * 0.09))
                    // The ground: always dark, in light and dark mode, so Poki has something to sit on.
                    LinearGradient(colors: [Self.ground, Self.ground.opacity(0)], startPoint: .bottom, endPoint: UnitPoint(x: 0.5, y: 0.82))
                    Ellipse().fill(Self.ground).frame(width: w * 2.1, height: h * 0.58)
                        .position(x: w / 2, y: h * 1.15).blur(radius: min(13, w * 0.04))
                    // A new pose rises into place; the old one fades under it.
                    PokiBear(pose: pose).frame(width: w * bear, height: w * bear)
                        .position(x: w / 2, y: h - w * bear * 0.47)
                        .id(pose)
                        .transition(.asymmetric(insertion: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity), removal: .opacity))
                }
                .animation(still ? nil : .spring(duration: 0.4, bounce: 0.3), value: pose)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(Text("Poki"))
    }

    static let ground = Color(red: 0.04, green: 0.04, blue: 0.05)
}
