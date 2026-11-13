// The Live Activity's colours, type and motion in one place. `ActivityMotion.phase` and the row
// transition are taken from leepokai/Codync (commit 848070d, apps/ios/Kit/Sources/CodyncKit/Design/
// Motion.swift and ActivityCards.swift), Copyright 2026 Po Kai Lee, Apache License 2.0. See
// THIRD_PARTY_NOTICES.md.
import SwiftUI

/// The website's colours (poki-site, ESP-139's token table and its final boards 01 to 05): the one
/// table the app's screens and the Live Activity both draw with.
enum Site {
    #if POKI_APP
    /// The system's blue in the app's screens.
    static let blue = Color(.systemBlue)
    #else
    static let blue = Color(hex: 0x0077FD)
    #endif
    static let sky = Color(hex: 0x5AA7FF)
    /// The page in dark mode (the docs site's blue); the boards draw light mode only.
    static let night = Color(hex: 0x0A2F6B)
    #if POKI_APP
    // The app's screens use the system's own colours, light and dark (grouped backgrounds, labels,
    // separators); only the Live Activity keeps the website's palette below.
    static let ink = Color.accentColor
    static let ok = Color(.systemGreen)
    static let bad = Color(.systemRed)
    static let c3 = Color(.secondaryLabel)
    static let c4 = Color(.secondaryLabel)
    static let glass = Color(.secondarySystemGroupedBackground)
    static let glass2 = Color(.tertiarySystemGroupedBackground)
    static let edge = Color(.separator)
    static let edgeTop = Color(.separator)
    static let text = Color(.label)
    static let text2 = Color(.secondaryLabel)
    static let text3 = Color(.tertiaryLabel)
    static let hair = Color(.separator)
    static let tint = Color(.systemFill)
    static let okInk = Color(.systemGreen)
    static let danger = Color(.systemRed)
    #else
    /// Blue text on white: the text of a white capsule button.
    static let ink = Color(hex: 0x0060D8)
    static let ok = Color(hex: 0x5BE37A)
    static let bad = Color(hex: 0xFF5F57)
    /// White text on blue, second and third level (--site-c3, --site-c4).
    static let c3 = Color.white.opacity(0.84)
    static let c4 = Color.white.opacity(0.72)
    /// Glass on blue: the card, the capsule and badge fill, the edge (with a brighter top line).
    static let glass = Color.white.opacity(0.08)
    static let glass2 = Color.white.opacity(0.16)
    static let edge = Color.white.opacity(0.28)
    static let edgeTop = Color.white.opacity(0.55)
    /// Inside the white cards: text, secondary text, placeholder and values, dividers.
    static let text = Color(hex: 0x111111)
    static let text2 = Color(hex: 0x6B6B70)
    static let text3 = Color(hex: 0x8A8A8E)
    static let hair = Color(hex: 0xE0E1E9)
    /// Light blue: tags, secondary buttons and the countdown on white.
    static let tint = Color(hex: 0xE5F1FF)
    /// Green and red text on white.
    static let okInk = Color(hex: 0x12A150)
    static let danger = Color(hex: 0xD93A32)
    #endif
}

/// Every colour, font and size the Live Activity draws with. Black, white words and Poki, on the Lock
/// Screen and in the island alike: the app's own look, with what you can press in white. Poki's pose
/// says the state, so no state has a colour.
struct ActivityTheme {
    /// The words, the main button's fill, Stop's square.
    var text = Color.white
    /// Second-level words: the status word, the meta value.
    var quiet = Color.white.opacity(0.64)
    /// The fill of what you can press that is not the main button: Stop, Deny.
    var fill = Color.white.opacity(0.17)
    /// The Lock Screen card, black like the island.
    var lockBackground = Color.black
    /// The island's outline while the person is needed.
    var approvalOutline = Color.white

    // Text styles, medium weight or heavier (HIG): the content line large, everything else one size.
    var button = Font.system(.callout, weight: .semibold)
    var compact = Font.system(.subheadline, weight: .semibold).monospacedDigit()
    var compactCode = Font.system(.subheadline, weight: .bold).monospacedDigit()
    var countdown = Font.system(.subheadline, weight: .semibold).monospacedDigit()
    /// The one line (18 semibold in the prototype), a card's heading, and the quiet line under it. The
    /// system's own face, as on the app's pages.
    var content = Font.system(size: 18, weight: .semibold)
    var heading = Font.system(size: 20, weight: .semibold)
    var detail = Font.system(size: 14)

    static let current = ActivityTheme()
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum ActivityMotion {
    /// A phase change (working, needs you, done): a soft spring that finishes well inside the 2 s iOS
    /// gives Live Activity updates.
    static let phase = Animation.spring(duration: 0.6, bounce: 0.3)
}

extension AnyTransition {
    /// Rows a new phase brings (the buttons, the step line): rise and fade in.
    static var activityRow: AnyTransition {
        .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)
    }
}
