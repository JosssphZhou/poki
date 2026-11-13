import SwiftUI

/// Poki's light: the one colour in the app, behind Poki in its window. Five hue sets, each worked out in
/// OKLCH at the same lightness and the same share of the chroma a screen can show, so changing the set
/// changes the colour and never the brightness. The numbers are the prototype's
/// (`design/app-prototype/js/hue.js`).
enum PokiLight: Int, CaseIterable, Identifiable {
    case firstLight, dusk, lagoon, sorbet, firefly

    static let key = "pokiLight"

    /// The owner's light. The app keeps a copy in the App Group, where the Live Activity reads it.
    static var chosen: PokiLight {
        PokiLight(rawValue: SharedContainer.defaults.integer(forKey: key)) ?? .firstLight
    }
    /// Where Settings › Appearance keeps light or dark ("" follows the iPhone).
    static let schemeKey = "pokiScheme"
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .firstLight: String(localized: "First light")
        case .dusk: String(localized: "Dusk")
        case .lagoon: String(localized: "Lagoon")
        case .sorbet: String(localized: "Sorbet")
        case .firefly: String(localized: "Firefly")
        }
    }

    /// The sky's three hues, from the top down, and the warm light's two.
    private var hues: (sky: [Double], warm: [Double]) {
        switch self {
        case .firstLight: ([262, 250, 235], [35, 60])
        case .dusk: ([266, 290, 320], [350, 35])
        case .lagoon: ([258, 222, 192], [168, 125])
        case .sorbet: ([305, 335, 355], [20, 48])
        case .firefly: ([245, 232, 215], [62, 84])
        }
    }

    struct Palette {
        /// The sky from the top: deep, full, light, then the two lower hues.
        var deep, sky, skyLight, mid, low: Color
        /// The light at the ground, and its bright centre.
        var warm, warmLight: Color
    }

    var palette: Palette {
        let h = hues, share = 0.72
        return Palette(deep: OKLCH.color(0.30, h.sky[0], share: share * 0.85), sky: OKLCH.color(0.50, h.sky[0], share: share),
                       skyLight: OKLCH.color(0.66, h.sky[0], share: share), mid: OKLCH.color(0.72, h.sky[1], share: share),
                       low: OKLCH.color(0.70, h.sky[2], share: share), warm: OKLCH.color(0.72, h.warm[0], share: share),
                       warmLight: OKLCH.color(0.80, h.warm[1], share: share))
    }
}

/// OKLCH to sRGB, and the most chroma sRGB can show at a lightness and hue (Björn Ottosson's OKLab matrices).
enum OKLCH {
    /// The colour at this lightness and hue with `share` of the chroma sRGB can show there.
    static func color(_ lightness: Double, _ hue: Double, share: Double) -> Color {
        let rgb = linear(lightness, maxChroma(lightness, hue) * share, hue)
        return Color(.sRGB, red: gamma(rgb.0), green: gamma(rgb.1), blue: gamma(rgb.2))
    }

    private static func linear(_ L: Double, _ C: Double, _ H: Double) -> (Double, Double, Double) {
        let h = H * .pi / 180, a = C * cos(h), b = C * sin(h)
        let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    private static func maxChroma(_ L: Double, _ H: Double) -> Double {
        var low = 0.0, high = 0.4
        for _ in 0..<20 {
            let middle = (low + high) / 2, rgb = linear(L, middle, H)
            let fits = [rgb.0, rgb.1, rgb.2].allSatisfy { $0 >= -0.0001 && $0 <= 1.0001 }
            if fits { low = middle } else { high = middle }
        }
        return low
    }

    private static func gamma(_ x: Double) -> Double {
        let v = min(1, max(0, x))
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}
