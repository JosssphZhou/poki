// Adapted from diegocp01/peter_ai (PeterAI/PeterAIWatch/WatchContentView.swift, commit be6d42b6),
// MIT License, Copyright (c) 2026 Diego Cabezas.
// Poki adapts the bottom watch action bar to Paper `p-B-0` watchOS 27 floating Liquid Glass
// capsules (38pt height, specular top rim, side-by-side Mute + End, cobalt primary CTA).

import SwiftUI

enum WatchBottomActionLayout {
    case muteAndEnd
    case endOnly
    case primaryBlue(title: LocalizedStringResource, identifier: String)
    case captionPill(text: LocalizedStringResource)
    case caption(text: LocalizedStringResource, color: Color)
    case spacer
}

struct WatchVoiceControlsBar: View {
    let layout: WatchBottomActionLayout
    let disabled: Bool
    let onPrimary: () -> Void
    let onEnd: () -> Void

    var body: some View {
        switch layout {
        case .muteAndEnd:
            HStack(spacing: WatchDesignTokens.pillButtonGap) {
                Button(action: onPrimary) {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.slash.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 12, weight: .semibold))
                        Text("Mute")
                            .font(WatchDesignTokens.buttonFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: WatchDesignTokens.bottomBarHeight)
                    .background(neutralGlassFill, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0x38 / 255.0), lineWidth: 0.75)
                    }
                }
                .buttonStyle(.plain)
                .watchGlassControl(in: Capsule(), tint: .white.opacity(0.06), interactive: true)
                .disabled(disabled)
                .handGestureShortcut(.primaryAction)
                .accessibilityIdentifier("watchRemote.primary")

                endButton(iconSize: 12)
            }
            .watchGlassGroup(spacing: 4)
            .frame(height: WatchDesignTokens.bottomBarHeight)

        case .endOnly:
            endButton(iconSize: 12.5)
                .frame(height: WatchDesignTokens.bottomBarHeight)

        case .primaryBlue(let title, let identifier):
            Button(action: onPrimary) {
                Text(title)
                    .font(WatchDesignTokens.buttonFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: WatchDesignTokens.bottomBarHeight)
                    .background(blueGlassFill, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(WatchDesignTokens.glassBlueBorder, lineWidth: 0.75)
                    }
            }
            .buttonStyle(.plain)
            .watchGlassControl(in: Capsule(), tint: WatchDesignTokens.pokiBlue.opacity(0.35), interactive: true)
            .shadow(color: WatchDesignTokens.glassBlueShadow, radius: 10, y: 3)
            .disabled(disabled)
            .handGestureShortcut(.primaryAction)
            .accessibilityIdentifier(identifier)
            .frame(height: WatchDesignTokens.bottomBarHeight)

        case .captionPill(let text):
            Text(text)
                .font(WatchDesignTokens.hintFont)
                .foregroundStyle(WatchDesignTokens.hintMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0x10 / 255.0), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0x22 / 255.0), lineWidth: 0.5)
                }
                .frame(maxWidth: .infinity)

        case .caption(let text, let color):
            Text(text)
                .font(WatchDesignTokens.hintFont)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: WatchDesignTokens.bottomBarHeight)

        case .spacer:
            Color.clear
                .frame(height: WatchDesignTokens.endedBottomSpacerHeight)
        }
    }

    private var neutralGlassFill: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0x24 / 255.0), Color.white.opacity(0x10 / 255.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var redGlassFill: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xB82820, opacity: 0x5C / 255.0), Color(hex: 0x6E1410, opacity: 0x48 / 255.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var blueGlassFill: LinearGradient {
        LinearGradient(
            colors: [WatchDesignTokens.pokiBlueTop, WatchDesignTokens.pokiBlueBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func endButton(iconSize: CGFloat) -> some View {
        Button(role: .destructive, action: onEnd) {
            HStack(spacing: 4) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(WatchDesignTokens.statusRedIcon)
                Text("End")
                    .font(WatchDesignTokens.buttonFont)
                    .foregroundStyle(WatchDesignTokens.statusRedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: WatchDesignTokens.bottomBarHeight)
            .background(redGlassFill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color(hex: 0xFF766E, opacity: 0x66 / 255.0), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .watchGlassControl(in: Capsule(), tint: Color(hex: 0x8A1A14).opacity(0.28), interactive: true)
        .disabled(disabled)
        .accessibilityIdentifier("watchRemote.end")
    }
}
