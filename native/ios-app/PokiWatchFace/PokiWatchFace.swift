// Adapted from semantic-craft/iOS-vibebuddy (VibeBuddyApp/WatchWidget/FollowedTaskWidget.swift,
// commit 2c2972d7), MIT License, Copyright (c) 2026 Xianwei Zhang.
// Poki adapts the WidgetKit complication families and widgetURL routing to Paper `p-B-0` W01
// watchOS 27 Liquid Glass styling with Poki's bear artwork and pokiwatch://start automatic launch.

import SwiftUI
import WidgetKit

@main
struct PokiWatchFace: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PokiWatchFace", provider: PokiWatchFaceTimeline()) { _ in
            PokiWatchFaceEntry()
                .unredacted()
                .widgetURL(URL(string: "pokiwatch://start"))
        }
        .configurationDisplayName("Poki")
        .description("Open Poki to control live voice or send a task.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

private enum WatchFacePalette {
    static let orbTop = Color(.sRGB, red: 90.0 / 255.0, green: 167.0 / 255.0, blue: 1.0, opacity: 0x73 / 255.0)
    static let orbMid = Color(.sRGB, red: 0.0, green: 119.0 / 255.0, blue: 253.0 / 255.0, opacity: 0x38 / 255.0)
    static let orbDeep = Color(.sRGB, red: 12.0 / 255.0, green: 24.0 / 255.0, blue: 48.0 / 255.0, opacity: 0xCC / 255.0)
    static let circularRing = Color(.sRGB, red: 112.0 / 255.0, green: 184.0 / 255.0, blue: 1.0, opacity: 0xE6 / 255.0)
    static let skyBlue = Color(.sRGB, red: 90.0 / 255.0, green: 167.0 / 255.0, blue: 1.0, opacity: 1.0)
    static let skyBlueLight = Color(.sRGB, red: 138.0 / 255.0, green: 196.0 / 255.0, blue: 1.0, opacity: 0xBF / 255.0)
    static let inlineTint = Color(.sRGB, red: 215.0 / 255.0, green: 235.0 / 255.0, blue: 1.0, opacity: 1.0)
    static let cornerFill = Color(.sRGB, red: 90.0 / 255.0, green: 167.0 / 255.0, blue: 1.0, opacity: 0x38 / 255.0)
    static let cardTop = Color(.sRGB, red: 44.0 / 255.0, green: 58.0 / 255.0, blue: 86.0 / 255.0, opacity: 0xAD / 255.0)
    static let cardBottom = Color(.sRGB, red: 22.0 / 255.0, green: 27.0 / 255.0, blue: 39.0 / 255.0, opacity: 0xE0 / 255.0)
    static let subtitle = Color(.sRGB, red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 245.0 / 255.0, opacity: 0xB8 / 255.0)
}

private struct PokiWatchFaceEntry: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularComplication
                .containerBackground(.black, for: .widget)
                .accessibilityLabel("Open Poki")

        case .accessoryCorner:
            cornerComplication
                .containerBackground(.black, for: .widget)
                .accessibilityLabel("Open Poki")

        case .accessoryRectangular:
            rectangularComplication
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [WatchFacePalette.cardTop, WatchFacePalette.cardBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .accessibilityLabel("Open Poki")

        case .accessoryInline:
            Label("Poki Voice", systemImage: "waveform")
                .foregroundStyle(WatchFacePalette.inlineTint)
                .containerBackground(.black, for: .widget)
                .accessibilityLabel("Open Poki")

        default:
            circularComplication
                .containerBackground(.black, for: .widget)
                .accessibilityLabel("Open Poki")
        }
    }

    private var circularComplication: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let bearSize = side * (90.0 / 104.0)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [WatchFacePalette.orbTop, WatchFacePalette.orbMid, WatchFacePalette.orbDeep],
                            center: UnitPoint(x: 0.30, y: 0.25),
                            startRadius: 1,
                            endRadius: side * 0.65
                        )
                    )
                    .overlay(alignment: .bottom) {
                        Image("WatchBear-ready")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: bearSize, height: bearSize)
                            .offset(x: side * (1.0 / 104.0), y: side * (1.0 / 104.0))
                    }
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
                            .padding(1)
                    }
                    .clipShape(Circle())

                Circle()
                    .strokeBorder(WatchFacePalette.circularRing, lineWidth: max(1.5, side * (2.5 / 104.0)))
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var cornerComplication: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let bearSize = side * (70.0 / 78.0)
            Circle()
                .fill(WatchFacePalette.cornerFill)
                .overlay(alignment: .bottom) {
                    Image("WatchBear-ready")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: bearSize, height: bearSize)
                        .offset(x: side * (1.0 / 78.0), y: side * (1.0 / 78.0))
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                }
                .clipShape(Circle())
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .widgetLabel {
            Gauge(value: 0.65) {
                Text("Poki")
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(WatchFacePalette.skyBlue)
        }
    }

    private var rectangularComplication: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [WatchFacePalette.orbTop, WatchFacePalette.orbMid],
                            center: UnitPoint(x: 0.30, y: 0.25),
                            startRadius: 1,
                            endRadius: 28
                        )
                    )
                    .overlay(alignment: .bottom) {
                        Image("WatchBear-ready")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .offset(x: 0.5, y: 0.5)
                    }
                    .clipShape(Circle())

                Circle()
                    .strokeBorder(WatchFacePalette.skyBlueLight, lineWidth: 1.25)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Poki Voice")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Tap or Double Tap")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(WatchFacePalette.subtitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle()
                    .fill(.white.opacity(0.14))
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PokiWatchFaceTimeline: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}
