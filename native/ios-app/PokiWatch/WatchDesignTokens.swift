import SwiftUI

/// Exact visual tokens extracted from Paper `p-B-0` artboards W00-W18
/// (46mm watchOS 27 native viewport 416x496 px = 208x248 pt, pure black OLED + Liquid Glass).
enum WatchDesignTokens {
    // MARK: - Core OLED & Brand Colors

    static let screenBackground = Color.black
    static let pokiBlue = Color(hex: 0x0077FD)
    static let pokiBlueTop = Color(hex: 0x218BFF)
    static let pokiBlueBottom = Color(hex: 0x0066E6)
    static let skyBlue = Color(hex: 0x5AA7FF)
    static let skyBlueLight = Color(hex: 0x8AC4FF)
    static let skyBlueGlow = Color(hex: 0x70B8FF)
    static let skyBlueRim = Color(hex: 0x9ACFFF)

    // MARK: - Status & Accent Colors

    static let statusGreen = Color(hex: 0x30D158)
    static let statusGreenLight = Color(hex: 0x5CE07E)
    static let statusGreenCheck = Color(hex: 0x67E589)
    static let statusGreenPillFill = Color(hex: 0x30D158, opacity: 0x2E / 255.0)
    static let statusGreenPillBorder = Color(hex: 0x30D158, opacity: 0x73 / 255.0)
    static let statusGreenBadgeFill = Color(hex: 0x30D158, opacity: 0x33 / 255.0)
    static let statusGreenBadgeBorder = Color(hex: 0x30D158, opacity: 0x80 / 255.0)

    static let statusOrange = Color(hex: 0xFF9F0A)
    static let statusAmberLight = Color(hex: 0xFFB340)
    static let statusAmberDeep = Color(hex: 0xE08200)
    static let statusOrangePillFill = Color(hex: 0xFF9F0A, opacity: 0x29 / 255.0)
    static let statusOrangePillBorder = Color(hex: 0xFF9F0A, opacity: 0x6B / 255.0)

    static let statusRed = Color(hex: 0xFF453A)
    static let statusRedBright = Color(hex: 0xFF5A50)
    static let statusRedDeep = Color(hex: 0xD92B20)
    static let statusRedIcon = Color(hex: 0xFF7369)
    static let statusRedText = Color(hex: 0xFF8880)
    static let statusRedTitle = Color(hex: 0xFF7B72)
    static let statusRedPillFill = Color(hex: 0xFF453A, opacity: 0x2E / 255.0)
    static let statusRedPillBorder = Color(hex: 0xFF453A, opacity: 0x73 / 255.0)

    static let statusPokiLabel = Color.white.opacity(0xF0 / 255.0)

    // MARK: - Text Colors

    static let titleWhite = Color.white
    static let titleRed = Color(hex: 0xFF7B72)
    static let titleMuted = Color(hex: 0xE5E7EB)

    static let subtitleDefault = Color(hex: 0xEBEBF5, opacity: 0xBF / 255.0)
    static let subtitleIdle = Color(hex: 0xEBEBF5, opacity: 0xC7 / 255.0)
    static let subtitleActing = Color(hex: 0xEBEBF5, opacity: 0xC7 / 255.0)
    static let hintMuted = Color(hex: 0xEBEBF5, opacity: 0xB8 / 255.0)
    static let hintSecondary = Color(hex: 0xEBEBF5, opacity: 0x94 / 255.0)
    static let cardBodyText = Color(hex: 0xEBEBF5, opacity: 0xDB / 255.0)
    static let historyLinkBlue = Color(hex: 0x8AC4FF, opacity: 0xDB / 255.0)

    // MARK: - Glass Surfaces

    static let topPillNeutralFill = Color.white.opacity(0x1A / 255.0)
    static let topPillNeutralBorder = Color.white.opacity(0x33 / 255.0)
    static let captionPillFill = Color.white.opacity(0x14 / 255.0)
    static let captionPillBorder = Color.white.opacity(0x2E / 255.0)

    static let glassNeutralTop = Color.white.opacity(0x38 / 255.0)
    static let glassNeutralBottom = Color.white.opacity(0x1A / 255.0)
    static let glassNeutralBorder = Color.white.opacity(0x57 / 255.0)
    static let glassNeutralSpecular = Color.white.opacity(0x6B / 255.0)

    static let glassRedTop = Color(hex: 0xFF4F44, opacity: 0x61 / 255.0)
    static let glassRedBottom = Color(hex: 0xB4201A, opacity: 0x42 / 255.0)
    static let glassRedBorder = Color(hex: 0xFF766E, opacity: 0x85 / 255.0)
    static let glassRedSpecular = Color(hex: 0xFFBEB9, opacity: 0x6B / 255.0)

    static let glassBlueBorder = Color(hex: 0x9ACFFF, opacity: 0xA6 / 255.0)
    static let glassBlueShadow = Color(hex: 0x0077FD, opacity: 0x73 / 255.0)

    static let stepPillFill = Color(hex: 0x5AA7FF, opacity: 0x33 / 255.0)
    static let stepPillBorder = Color(hex: 0x8AC4FF, opacity: 0x8C / 255.0)

    static let resultCardTop = Color(hex: 0x2C3242, opacity: 0x9E / 255.0)
    static let resultCardBottom = Color(hex: 0x161922, opacity: 0xE0 / 255.0)
    static let resultCardBorder = Color.white.opacity(0x38 / 255.0)

    static let hubLatestTop = Color(hex: 0x2C364A, opacity: 0x9E / 255.0)
    static let hubLatestBottom = Color(hex: 0x161A24, opacity: 0xE6 / 255.0)
    static let hubRowTop = Color.white.opacity(0x24 / 255.0)
    static let hubRowBottom = Color.white.opacity(0x0F / 255.0)
    static let hubBlueRowTop = Color(hex: 0x0077FD, opacity: 0x47 / 255.0)
    static let hubBlueRowBottom = Color(hex: 0x0052BE, opacity: 0x29 / 255.0)
    static let hubBlueRowBorder = Color(hex: 0x70B8FF, opacity: 0x73 / 255.0)

    static let badgeMutedTop = Color(hex: 0x40444E, opacity: 0xF5 / 255.0)
    static let badgeMutedBottom = Color(hex: 0x24262C, opacity: 0xFA / 255.0)

    // MARK: - Dimensions (46mm watchOS 27: 208x248 pt = 416x496 px / 2)

    static let screenHorizontalPadding: CGFloat = 14
    static let screenTopPadding: CGFloat = 11
    static let screenBottomPadding: CGFloat = 16
    static let statusDotSize: CGFloat = 5
    static let statusDotGap: CGFloat = 4
    static let badgeSize: CGFloat = 26
    static let badgeBorderWidth: CGFloat = 2.5
    static let badgeOffset: CGFloat = 0
    static let indicatorHeight: CGFloat = 18
    static let bottomBarHeight: CGFloat = 38
    static let secondaryBottomBarHeight: CGFloat = 35
    static let pillButtonGap: CGFloat = 7
    static let resultCardCornerRadius: CGFloat = 16
    static let hubCardCornerRadius: CGFloat = 15
    static let resultCardPaddingH: CGFloat = 11
    static let resultCardPaddingV: CGFloat = 10
    static let endedBottomSpacerHeight: CGFloat = 14

    // MARK: - Typography (calibrated for 46mm OLED readability)

    static let topBarFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let resultTopBarFont = Font.system(size: 10.5, weight: .semibold)
    static let idleTitleFont = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let titleFont = Font.system(size: 17, weight: .semibold)
    static let compactTitleFont = Font.system(size: 16, weight: .semibold)
    static let lockedTitleFont = Font.system(size: 15, weight: .semibold)
    static let subtitleFont = Font.system(size: 11.5, weight: .regular)
    static let compactSubtitleFont = Font.system(size: 11, weight: .regular)
    static let hintFont = Font.system(size: 11, weight: .medium)
    static let buttonFont = Font.system(size: 13, weight: .semibold)
    static let secondaryButtonFont = Font.system(size: 12, weight: .semibold)
    static let stepBadgeFont = Font.system(size: 11.5, weight: .bold, design: .monospaced)
    static let resultHeadlineFont = Font.system(size: 15.5, weight: .semibold)
    static let resultBodyFont = Font.system(size: 12, weight: .regular)
    static let resultFooterFont = Font.system(size: 10.5, weight: .regular)
    static let hubCardTitleFont = Font.system(size: 12.5, weight: .semibold)
    static let hubCardPreviewFont = Font.system(size: 11.5, weight: .medium)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - watchOS 27 Native Liquid Glass Helpers

extension View {
    /// Applies native watchOS 26/27 clear Liquid Glass on interactive OLED controls so dark
    /// smoky translucency and specular rims stay true to pure-black OLED without chalky gray backing.
    /// Put on a Button (not inside its label) when `interactive` is true so system glass never intercepts touches.
    @ViewBuilder
    func watchGlassControl<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(watchOS 26.0, *) {
            self.glassEffect(Glass.clear.tint(tint).interactive(interactive), in: shape)
        } else {
            self
        }
    }

    @ViewBuilder
    func watchGlassGroup(spacing: CGFloat? = nil) -> some View {
        if #available(watchOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// Pure black OLED backdrop with a subtle state-matched radial ambient aura that fades to `#000000`
/// well before screen edges so watchOS OLED bezels stay seamlessly pure black.
struct WatchOLEDBackground: View {
    let center: UnitPoint
    let innerColor: Color
    let midColor: Color?
    let endRadiusFraction: CGFloat
    var pulseBoost: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let maxSide = max(proxy.size.width, proxy.size.height)
            ZStack {
                Color.black
                RadialGradient(
                    stops: stops,
                    center: center,
                    startRadius: 2,
                    endRadius: maxSide * endRadiusFraction
                )
                .opacity(1.0 + pulseBoost * 0.25)
            }
        }
        .ignoresSafeArea()
    }

    private var stops: [Gradient.Stop] {
        if let midColor {
            return [
                .init(color: innerColor, location: 0.0),
                .init(color: midColor, location: 0.40),
                .init(color: .black, location: 1.0)
            ]
        }
        return [
            .init(color: innerColor, location: 0.0),
            .init(color: .black, location: 1.0)
        ]
    }
}

struct WatchAmbientSpec: Equatable {
    let center: UnitPoint
    let inner: Color
    let mid: Color?
    let endFraction: CGFloat
}

enum WatchTopStatusKind: Equatable {
    case connected
    case attention
    case disconnected
}

enum WatchCornerBadgeKind: Equatable {
    case error
    case setup
    case muted
    case locked
}

enum WatchDynamicIndicatorKind: Equatable {
    case connectingDots
    case thinkingDots
    case listeningWave
    case speakingWave
    case stepBadge(String)
    case endedCheckmark
}

struct WatchBearArtSpec: Equatable {
    let assetName: String
    let orbSize: CGFloat
    let imageSize: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let opacity: Double
    let gradientStops: [Color]
    let ringColor: Color
    let ringWidth: CGFloat
    let specularOpacity: Double
    let glowColor: Color?
    let glowRadius: CGFloat
    let badge: WatchCornerBadgeKind?
}

/// Maps live WatchVoiceModel state to Paper `p-B-0` artboards W02-W16 without altering the wire protocol.
enum WatchScreenMode: Equatable {
    case unavailable       // W02 / W16 disconnected
    case needsSetup        // W03
    case idle              // W04
    case connecting        // W05
    case listening         // W06
    case thinking          // W07
    case acting(step: String, badge: String?) // W08
    case speaking          // W09
    case muted             // W10
    case ending            // W12 (transitional ending)
    case ended             // W12 (local 3s ended state)
    case waking            // W05/W14 (waking phone on start)
    case locked            // W15 (requiresForeground)
    case failed            // W16 (failed / phone Poki not running)

    static func resolve(
        state: WatchVoiceCallState,
        isMuted: Bool,
        currentStep: String?,
        requiresForeground: Bool,
        isStartingCall: Bool,
        showingEndedScreen: Bool,
        hasTransportError: Bool
    ) -> WatchScreenMode {
        if state == .ending {
            return .ending
        }
        if state.isActiveCall {
            if isMuted || state == .muted {
                return .muted
            }
            if state == .connecting {
                return .connecting
            }
            if state == .speaking {
                return .speaking
            }
            if let step = currentStep?.trimmingCharacters(in: .whitespacesAndNewlines), !step.isEmpty {
                let parsed = parseStep(step)
                return .acting(step: parsed.subtitle, badge: parsed.badge)
            }
            if state == .thinking {
                return .thinking
            }
            return .listening
        }
        if isStartingCall {
            return .waking
        }
        if requiresForeground {
            return .locked
        }
        if state == .needsSetup {
            return .needsSetup
        }
        if state == .failed {
            return .failed
        }
        if state == .unavailable {
            return hasTransportError ? .failed : .unavailable
        }
        if showingEndedScreen {
            return .ended
        }
        return .idle
    }

    /// Extracts an optional numeric step ratio like "3/4" ONLY when the incoming step text contains one.
    static func parseStep(_ raw: String) -> (badge: String?, subtitle: String) {
        let pattern = #"(?:^|\s)(\d{1,2}/\d{1,2})(?:\s|[:：-]|$)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let badgeRange = Range(match.range(at: 1), in: raw) {
            let badge = String(raw[badgeRange])
            let stripped = raw.replacingCharacters(in: badgeRange, with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            return (badge, stripped.isEmpty ? raw : stripped)
        }
        return (nil, raw)
    }

    var topStatus: WatchTopStatusKind {
        switch self {
        case .unavailable, .failed:
            .disconnected
        case .needsSetup, .locked:
            .attention
        case .idle, .connecting, .listening, .thinking, .acting, .speaking, .muted, .ending, .ended, .waking:
            .connected
        }
    }

    var ambientGlow: WatchAmbientSpec {
        switch self {
        case .idle:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color(hex: 0x0077FD, opacity: 0x3D / 255.0),
                mid: Color(hex: 0x0044AA, opacity: 0x14 / 255.0),
                endFraction: 0.72
            )
        case .connecting, .waking:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color(hex: 0x5AA7FF, opacity: 0x29 / 255.0),
                mid: nil,
                endFraction: 0.68
            )
        case .listening:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color(hex: 0x5AA7FF, opacity: 0x42 / 255.0),
                mid: Color(hex: 0x143A78, opacity: 0x14 / 255.0),
                endFraction: 0.72
            )
        case .thinking:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color.white.opacity(0x24 / 255.0),
                mid: Color(hex: 0xA0B4DC, opacity: 0x0D / 255.0),
                endFraction: 0.72
            )
        case .acting:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.32),
                inner: Color(hex: 0x5AA7FF, opacity: 0x38 / 255.0),
                mid: Color(hex: 0x10285C, opacity: 0x14 / 255.0),
                endFraction: 0.72
            )
        case .speaking:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color(hex: 0x0077FD, opacity: 0x57 / 255.0),
                mid: Color(hex: 0x004AB4, opacity: 0x1F / 255.0),
                endFraction: 0.72
            )
        case .muted:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color(hex: 0xA0A8B9, opacity: 0x1F / 255.0),
                mid: nil,
                endFraction: 0.68
            )
        case .ending, .ended:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color(hex: 0x30D158, opacity: 0x24 / 255.0),
                mid: nil,
                endFraction: 0.68
            )
        case .locked:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color(hex: 0xFF9F0A, opacity: 0x2E / 255.0),
                mid: nil,
                endFraction: 0.68
            )
        case .needsSetup:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color(hex: 0xFF9F0A, opacity: 0x29 / 255.0),
                mid: nil,
                endFraction: 0.68
            )
        case .unavailable, .failed:
            WatchAmbientSpec(
                center: UnitPoint(x: 0.5, y: 0.34),
                inner: Color(hex: 0xFF453A, opacity: 0x45 / 255.0),
                mid: Color(hex: 0x8A1C16, opacity: 0x1A / 255.0),
                endFraction: 0.72
            )
        }
    }

    var bearArt: WatchBearArtSpec {
        switch self {
        case .unavailable, .failed:
            WatchBearArtSpec(
                assetName: "WatchBear-tripped",
                orbSize: 90,
                imageSize: 83,
                offsetX: 4,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color(hex: 0xFF453A, opacity: 0x40 / 255.0),
                    Color(hex: 0x161922, opacity: 0xE6 / 255.0)
                ],
                ringColor: Color(hex: 0xFF453A, opacity: 0x8F / 255.0),
                ringWidth: 1.5,
                specularOpacity: 0.30,
                glowColor: Color(hex: 0xFF453A, opacity: 0x45 / 255.0),
                glowRadius: 16,
                badge: .error
            )
        case .needsSetup:
            WatchBearArtSpec(
                assetName: "WatchBear-needs",
                orbSize: 90,
                imageSize: 83,
                offsetX: 2.5,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color(hex: 0xFFB340, opacity: 0x38 / 255.0),
                    Color(hex: 0x161922, opacity: 0xE6 / 255.0)
                ],
                ringColor: Color(hex: 0xFF9F0A, opacity: 0x8F / 255.0),
                ringWidth: 1.5,
                specularOpacity: 0.30,
                glowColor: Color(hex: 0xFF9F0A, opacity: 0x32 / 255.0),
                glowRadius: 14,
                badge: .setup
            )
        case .idle:
            WatchBearArtSpec(
                assetName: "WatchBear-ready",
                orbSize: 94,
                imageSize: 84,
                offsetX: 1,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color(hex: 0x70B8FF, opacity: 0x70 / 255.0),
                    Color(hex: 0x0077FD, opacity: 0x38 / 255.0),
                    Color(hex: 0x061026, opacity: 0xD9 / 255.0)
                ],
                ringColor: Color(hex: 0x8AC4FF, opacity: 0xB8 / 255.0),
                ringWidth: 1.5,
                specularOpacity: 0.55,
                glowColor: Color(hex: 0x0077FD, opacity: 0x78 / 255.0),
                glowRadius: 20,
                badge: nil
            )
        case .connecting, .waking:
            WatchBearArtSpec(
                assetName: "WatchBear-needs",
                orbSize: 86,
                imageSize: 79,
                offsetX: 2.5,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color(hex: 0x8AC4FF, opacity: 0x3D / 255.0),
                    Color(hex: 0x161922, opacity: 0xE6 / 255.0)
                ],
                ringColor: Color(hex: 0x8AC4FF, opacity: 0x85 / 255.0),
                ringWidth: 1.5,
                specularOpacity: 0.35,
                glowColor: Color(hex: 0x5AA7FF, opacity: 0x30 / 255.0),
                glowRadius: 12,
                badge: nil
            )
        case .listening:
            WatchBearArtSpec(
                assetName: "WatchBear-listening",
                orbSize: 86,
                imageSize: 77,
                offsetX: 1.5,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color(hex: 0x8AC4FF, opacity: 0x6B / 255.0),
                    Color(hex: 0x5AA7FF, opacity: 0x2E / 255.0),
                    Color(hex: 0x0A1426, opacity: 0xD9 / 255.0)
                ],
                ringColor: Color(hex: 0x80C0FF, opacity: 0xE6 / 255.0),
                ringWidth: 1.5,
                specularOpacity: 0.55,
                glowColor: Color(hex: 0x5AA7FF, opacity: 0x6B / 255.0),
                glowRadius: 16,
                badge: nil
            )
        case .thinking:
            WatchBearArtSpec(
                assetName: "WatchBear-thinking",
                orbSize: 86,
                imageSize: 77,
                offsetX: 1,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color.white.opacity(0x3D / 255.0),
                    Color.white.opacity(0x14 / 255.0),
                    Color(hex: 0x12141C, opacity: 0xD9 / 255.0)
                ],
                ringColor: Color.white.opacity(0xAD / 255.0),
                ringWidth: 1.5,
                specularOpacity: 0.60,
                glowColor: Color.white.opacity(0x38 / 255.0),
                glowRadius: 14,
                badge: nil
            )
        case .acting:
            WatchBearArtSpec(
                assetName: "WatchBear-phone",
                orbSize: 79,
                imageSize: 71,
                offsetX: 1.5,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color(hex: 0x8AC4FF, opacity: 0x61 / 255.0),
                    Color(hex: 0x5AA7FF, opacity: 0x29 / 255.0),
                    Color(hex: 0x0A1426, opacity: 0xD9 / 255.0)
                ],
                ringColor: Color(hex: 0x70B8FF, opacity: 0xDB / 255.0),
                ringWidth: 1.5,
                specularOpacity: 0.50,
                glowColor: Color(hex: 0x5AA7FF, opacity: 0x59 / 255.0),
                glowRadius: 14,
                badge: nil
            )
        case .speaking:
            WatchBearArtSpec(
                assetName: "WatchBear-speaking",
                orbSize: 86,
                imageSize: 77,
                offsetX: 0,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color(hex: 0x50A4FF, opacity: 0x7A / 255.0),
                    Color(hex: 0x0077FD, opacity: 0x47 / 255.0),
                    Color(hex: 0x061026, opacity: 0xD9 / 255.0)
                ],
                ringColor: Color(hex: 0x3C98FF),
                ringWidth: 1.75,
                specularOpacity: 0.55,
                glowColor: Color(hex: 0x0077FD, opacity: 0x94 / 255.0),
                glowRadius: 20,
                badge: nil
            )
        case .muted:
            WatchBearArtSpec(
                assetName: "WatchBear-ready",
                orbSize: 90,
                imageSize: 82,
                offsetX: 1,
                offsetY: 1,
                opacity: 0.68,
                gradientStops: [
                    Color(hex: 0xB8B8C0, opacity: 0x26 / 255.0),
                    Color(hex: 0x161922, opacity: 0xCC / 255.0)
                ],
                ringColor: Color(hex: 0xB8B8C0, opacity: 0x66 / 255.0),
                ringWidth: 1.5,
                specularOpacity: 0.28,
                glowColor: Color(hex: 0xA0A8B9, opacity: 0x22 / 255.0),
                glowRadius: 12,
                badge: .muted
            )
        case .ending, .ended:
            WatchBearArtSpec(
                assetName: "WatchBear-done",
                orbSize: 88,
                imageSize: 81,
                offsetX: 2.5,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color.white.opacity(0x24 / 255.0),
                    Color(hex: 0x161922, opacity: 0xE6 / 255.0)
                ],
                ringColor: Color.white.opacity(0x57 / 255.0),
                ringWidth: 1.25,
                specularOpacity: 0.30,
                glowColor: Color(hex: 0x30D158, opacity: 0x24 / 255.0),
                glowRadius: 12,
                badge: nil
            )
        case .locked:
            WatchBearArtSpec(
                assetName: "WatchBear-needs",
                orbSize: 90,
                imageSize: 83,
                offsetX: 2.5,
                offsetY: 1,
                opacity: 1.0,
                gradientStops: [
                    Color(hex: 0xFFB340, opacity: 0x3C / 255.0),
                    Color(hex: 0x161922, opacity: 0xE6 / 255.0)
                ],
                ringColor: Color(hex: 0xFF9F0A, opacity: 0x99 / 255.0),
                ringWidth: 1.5,
                specularOpacity: 0.35,
                glowColor: Color(hex: 0xFF9F0A, opacity: 0x3C / 255.0),
                glowRadius: 16,
                badge: .locked
            )
        }
    }

    var indicator: WatchDynamicIndicatorKind? {
        switch self {
        case .connecting, .waking, .ending:
            .connectingDots
        case .listening:
            .listeningWave
        case .thinking:
            .thinkingDots
        case .acting(_, let badge):
            badge.map { .stepBadge($0) }
        case .speaking:
            .speakingWave
        case .ended:
            .endedCheckmark
        case .unavailable, .needsSetup, .idle, .muted, .locked, .failed:
            nil
        }
    }

    var titleFont: Font {
        switch self {
        case .idle:
            WatchDesignTokens.idleTitleFont
        case .locked:
            WatchDesignTokens.lockedTitleFont
        case .acting, .connecting, .waking:
            WatchDesignTokens.compactTitleFont
        default:
            WatchDesignTokens.titleFont
        }
    }

    var titleColor: Color {
        switch self {
        case .unavailable, .failed:
            WatchDesignTokens.titleRed
        case .muted:
            WatchDesignTokens.titleMuted
        default:
            WatchDesignTokens.titleWhite
        }
    }

    var subtitleFont: Font {
        switch self {
        case .connecting, .waking, .ended, .locked, .needsSetup, .failed, .unavailable:
            WatchDesignTokens.compactSubtitleFont
        default:
            WatchDesignTokens.subtitleFont
        }
    }

    var subtitleColor: Color {
        switch self {
        case .idle:
            WatchDesignTokens.subtitleIdle
        case .acting:
            WatchDesignTokens.subtitleActing
        default:
            WatchDesignTokens.subtitleDefault
        }
    }
}
