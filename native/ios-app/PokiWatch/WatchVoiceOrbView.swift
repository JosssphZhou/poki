// Adapted from khooeee/watchamacallit (Watchamacallit/ContentView.swift, commit df86d982),
// MIT License, Copyright (c) 2026 Chris Khoo; status badge styling adapted from
// semantic-craft/iOS-vibebuddy (VibeBuddyApp/Watch/WatchAlertCard.swift, commit 2c2972d7),
// MIT License, Copyright (c) 2026 Xianwei Zhang.
// Poki replaces the SF Symbol orb with Poki's bear artwork, watchOS 27 Liquid Glass specular
// ring/glow, 3D status badges, and Paper `p-B-0` dynamic indicators.

import SwiftUI

struct WatchVoiceOrbView: View {
    let mode: WatchScreenMode
    let meterLevel: UInt8
    let title: LocalizedStringResource
    let subtitle: String?
    let isInteractive: Bool
    let isDisabled: Bool
    let accessibilityIdentifier: String?
    let onTap: () -> Void
    let onLongPress: (() -> Void)?

    @State private var suppressedNextTap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let art = mode.bearArt
        let indicator = mode.indicator

        VStack(spacing: isActing ? 5 : 6) {
            avatarControl(art: art)

            if let indicator {
                WatchDynamicIndicatorView(
                    kind: indicator,
                    meterLevel: meterLevel,
                    reduceMotion: reduceMotion
                )
                .frame(minHeight: WatchDesignTokens.indicatorHeight)
                .accessibilityIdentifier(indicator == .listeningWave || indicator == .speakingWave ? "watchRemote.meter" : "")
            }

            VStack(spacing: indicator == nil ? 3 : 2) {
                Text(title)
                    .font(mode.titleFont)
                    .foregroundStyle(mode.titleColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("watchRemote.status")

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(mode.subtitleFont)
                        .foregroundStyle(mode.subtitleColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(isActing ? "watchRemote.step" : "watchRemote.subtitle")
                }
            }
            .padding(.top, indicator == nil ? 3 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var isActing: Bool {
        if case .acting = mode { return true }
        return false
    }

    private var meterPulse: CGFloat {
        guard !reduceMotion, mode == .speaking || mode == .listening else { return 0 }
        return CGFloat(meterLevel) / 255.0
    }

    @ViewBuilder
    private func avatarControl(art: WatchBearArtSpec) -> some View {
        let glowRadius = art.glowRadius + (mode == .speaking ? meterPulse * 6 : meterPulse * 3)
        let circle = ZStack {
            if let glowColor = art.glowColor, glowRadius > 0 {
                Circle()
                    .fill(glowColor.opacity(0.45 + Double(meterPulse) * 0.25))
                    .frame(width: art.orbSize * 0.92, height: art.orbSize * 0.92)
                    .blur(radius: glowRadius * 0.72)
                    .allowsHitTesting(false)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: art.gradientStops,
                        center: UnitPoint(x: 0.32, y: 0.24),
                        startRadius: 2,
                        endRadius: art.orbSize * 0.65
                    )
                )
                .frame(width: art.orbSize, height: art.orbSize)
                .overlay(alignment: .bottom) {
                    Image(art.assetName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: art.imageSize, height: art.imageSize)
                        .offset(x: art.offsetX, y: art.offsetY)
                        .opacity(art.opacity)
                }
                .overlay {
                    // Subtle top-arc specular reflection matching watchOS 27 Liquid Glass orb.
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(art.specularOpacity),
                                    .white.opacity(0.06),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .padding(1)
                }
                .clipShape(Circle())

            Circle()
                .strokeBorder(art.ringColor, lineWidth: art.ringWidth)
                .frame(width: art.orbSize, height: art.orbSize)
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge = art.badge {
                WatchCornerBadgeView(kind: badge)
                    .offset(x: WatchDesignTokens.badgeOffset, y: WatchDesignTokens.badgeOffset)
            }
        }
        .frame(width: art.orbSize, height: art.orbSize)
        .contentShape(Circle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: meterLevel)

        if isInteractive {
            let button = Button {
                if suppressedNextTap {
                    suppressedNextTap = false
                    return
                }
                onTap()
            } label: {
                circle
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .handGestureShortcut(.primaryAction)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier ?? "watchRemote.primary")

            if let onLongPress {
                button.simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .onEnded { _ in
                            suppressedNextTap = true
                            onLongPress()
                        }
                )
            } else {
                button
            }
        } else {
            circle
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: LocalizedStringResource {
        switch mode {
        case .muted: "Unmute"
        default: "Start"
        }
    }
}

private struct WatchCornerBadgeView: View {
    let kind: WatchCornerBadgeKind

    var body: some View {
        let innerSize = WatchDesignTokens.badgeSize - WatchDesignTokens.badgeBorderWidth * 2
        ZStack {
            Circle()
                .fill(WatchDesignTokens.screenBackground)
                .frame(width: WatchDesignTokens.badgeSize, height: WatchDesignTokens.badgeSize)
            Circle()
                .fill(
                    LinearGradient(
                        colors: fillGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.45), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                }
                .frame(width: innerSize, height: innerSize)
            Image(systemName: symbolName)
                .font(.system(size: symbolSize, weight: .bold))
                .foregroundStyle(iconColor)
        }
        .frame(width: WatchDesignTokens.badgeSize, height: WatchDesignTokens.badgeSize)
        .accessibilityHidden(true)
    }

    private var fillGradient: [Color] {
        switch kind {
        case .error: [WatchDesignTokens.statusRedBright, WatchDesignTokens.statusRedDeep]
        case .setup, .locked: [WatchDesignTokens.statusAmberLight, WatchDesignTokens.statusAmberDeep]
        case .muted: [WatchDesignTokens.badgeMutedTop, WatchDesignTokens.badgeMutedBottom]
        }
    }

    private var iconColor: Color {
        switch kind {
        case .error, .muted: .white
        case .setup, .locked: .black
        }
    }

    private var symbolName: String {
        switch kind {
        case .error: "exclamationmark"
        case .setup: "gearshape.fill"
        case .muted: "mic.slash.fill"
        case .locked: "lock.fill"
        }
    }

    private var symbolSize: CGFloat {
        switch kind {
        case .error: 12
        case .setup: 11.5
        case .locked: 11
        case .muted: 10.5
        }
    }
}

private struct WatchDynamicIndicatorView: View {
    let kind: WatchDynamicIndicatorKind
    let meterLevel: UInt8
    let reduceMotion: Bool

    private static let listeningHeights: [CGFloat] = [6, 12, 17, 11, 6]
    private static let listeningColors: [Color] = [
        Color(hex: 0x7CC0FF),
        Color(hex: 0x5AA7FF),
        Color(hex: 0xA2D4FF),
        Color(hex: 0x5AA7FF),
        Color(hex: 0x7CC0FF)
    ]

    private static let speakingHeights: [CGFloat] = [7, 17, 12, 8, 5]
    private static let speakingColors: [Color] = [
        Color(hex: 0x2D8CFF),
        Color(hex: 0x6DB8FF),
        Color(hex: 0x2D8CFF),
        Color(hex: 0x0077FD),
        Color(hex: 0x0077FD)
    ]

    var body: some View {
        switch kind {
        case .connectingDots:
            pulsingDots(
                count: 5,
                size: 4,
                spacing: 4,
                color: WatchDesignTokens.skyBlueLight,
                opacities: [1.0, 0.82, 0.62, 0.42, 0.24],
                glowActive: false
            )
        case .thinkingDots:
            pulsingDots(
                count: 3,
                size: 6,
                spacing: 6,
                color: .white,
                opacities: [1.0, 0.65, 0.35],
                glowActive: true
            )
        case .listeningWave:
            waveBars(
                baseHeights: Self.listeningHeights,
                colors: Self.listeningColors,
                peakIndex: 2,
                glowColor: WatchDesignTokens.skyBlue
            )
        case .speakingWave:
            waveBars(
                baseHeights: Self.speakingHeights,
                colors: Self.speakingColors,
                peakIndex: 1,
                glowColor: WatchDesignTokens.pokiBlue
            )
        case .stepBadge(let text):
            Text(text)
                .font(WatchDesignTokens.stepBadgeFont)
                .foregroundStyle(WatchDesignTokens.skyBlueLight)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(Color(hex: 0x5AA7FF, opacity: 0x24 / 255.0), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(hex: 0x8AC4FF, opacity: 0x55 / 255.0), lineWidth: 0.75)
                }
                .accessibilityIdentifier("watchRemote.stepBadge")
        case .endedCheckmark:
            ZStack {
                Circle()
                    .fill(WatchDesignTokens.statusGreenBadgeFill)
                Circle()
                    .strokeBorder(WatchDesignTokens.statusGreenBadgeBorder, lineWidth: 0.75)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WatchDesignTokens.statusGreenCheck)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func pulsingDots(
        count: Int,
        size: CGFloat,
        spacing: CGFloat,
        color: Color,
        opacities: [Double],
        glowActive: Bool
    ) -> some View {
        if reduceMotion {
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .opacity(opacities[index % opacities.count])
                }
            }
            .accessibilityHidden(true)
        } else {
            TimelineView(.periodic(from: .now, by: 0.32)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.32) % count
                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { index in
                        let distance = (index - step + count) % count
                        let alpha = opacities[distance % opacities.count]
                        Circle()
                            .fill(color)
                            .frame(width: size, height: size)
                            .opacity(alpha)
                            .shadow(color: glowActive && distance == 0 ? color.opacity(0.8) : .clear, radius: 4)
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func waveBars(
        baseHeights: [CGFloat],
        colors: [Color],
        peakIndex: Int,
        glowColor: Color
    ) -> some View {
        let scale: Double = meterLevel == 0 ? 1.0 : (0.72 + 0.32 * (Double(meterLevel) / 255.0))
        return HStack(spacing: 3.5) {
            ForEach(baseHeights.indices, id: \.self) { index in
                let height = max(4, min(17, baseHeights[index] * scale))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(colors[index])
                    .frame(width: 4, height: height)
                    .shadow(color: index == peakIndex ? glowColor.opacity(0.8) : .clear, radius: 5)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: meterLevel)
        .accessibilityHidden(true)
    }
}
