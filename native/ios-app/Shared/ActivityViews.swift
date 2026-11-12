// The Live Activity's views. The structure (one card per surface drawn from one presentation, the
// expanded island's content under the camera, the approval buttons, the compact status) is ported
// from AgentLiveActivityWidget.swift in Clarklevis1995/dsh-mobile (commit ebe19764,
// AgentLiveActivityWidget/AgentLiveActivityWidget.swift), MIT License, Copyright (c) 2026 Chaofan Li.
// The approval countdown, counted by the system with `Text(timerInterval:countsDown:)`, follows
// ios/AgentActivity/AgentActivityWidget.swift in onehumanbeing/esp32-iphone-agent (commit cc966294),
// MIT License, Copyright (c) 2026 Henry Yuan. Interpolated text, the phase spring and margins kept
// concentric with the island's corners are from leepokai/Codync (commit 848070d,
// apps/ios/Widgets/CodyncWidgets.swift), Copyright 2026 Po Kai Lee, Apache License 2.0. Poki adds the
// step line, the pairing code, the setup steps, the thumbnail and the bear avatar from ESP-139's
// board 02, with ESP-162's shorter words. See THIRD_PARTY_NOTICES.md.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Sizes (HIG, iPhone): the Lock Screen presentation and the expanded island are 84 to 160 points tall
/// and 371 or 408 wide. Every view here draws one `ActivityFace`, so the four presentations say the
/// same thing in the same order: Poki in the state's pose, the status word, then the content line.
///
/// The look is the app's: black, white words, and Poki. Poki's pose carries the state (on the phone,
/// asking, hiding its eyes, pleased, worried), so no state needs a colour of its own. What you can
/// press is white on the black, as it is black on the app's white pages.
enum ActivityMetrics {
    /// The Lock Screen's margins: 16 at the sides so Poki and the buttons stay clear of the rounded
    /// corners, and room at the bottom for Poki's light.
    static let lockInsets = EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16)
    /// The card's corner as iOS draws it (the in-app preview's frame).
    static let lockCorner: CGFloat = 24
    /// The expanded island's margins inside its 44 point corners: content never runs to the edge.
    static let islandInsets = EdgeInsets(top: 8, leading: 22, bottom: 22, trailing: 22)
    static let islandCorner: CGFloat = 44
    /// The row beside the camera sits a little further from the island's rounded sides.
    static let islandRowInset: CGFloat = 4
    /// Poki on the content line, in the compact island, and in the minimal one.
    static let pose: CGFloat = 40
    static let compactPose: CGFloat = 24
    /// Stop's circle; its touch area is 44 points.
    static let stop: CGFloat = 32
    /// The buttons under the content line.
    static let button: CGFloat = 44
}

// MARK: Lock Screen

/// The Lock Screen (and banner) presentation: the same card as the expanded island, on black.
struct LockScreenCard: View {
    var face: ActivityFace
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        ActivityCard(face: face)
            .padding(ActivityMetrics.lockInsets)
            .background(alignment: .bottom) { LightGlow().opacity(dimmed ? 0 : 1) }
            .environment(\.colorScheme, .dark)
            // No animation in Always On (HIG).
            .animation(dimmed ? nil : ActivityMotion.phase, value: face)
            .accessibilityElement(children: .contain)
    }
}

/// What both large presentations draw. One line while Poki works or has finished: Poki, the action in
/// hand in the app's own words, and Stop. A heading with a quiet line under it, and one row of buttons,
/// when Poki needs the owner or could not go on.
private struct ActivityCard: View {
    var face: ActivityFace
    private let theme = ActivityTheme.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                PoseMark(pose: face.pose, size: ActivityMetrics.pose)
                if let detail = face.detail {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(face.status)
                            .font(face.contentIsCode ? theme.heading.monospacedDigit().weight(.bold) : theme.heading)
                            .foregroundStyle(theme.text).lineLimit(1).minimumScaleFactor(0.8)
                            .contentTransition(face.contentIsCode ? .numericText() : .interpolate)
                        Text(detail).font(theme.detail).foregroundStyle(theme.quiet).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    line.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let caller = face.caller { CallerBadge(name: caller, size: 20) }
                if face.talking { TalkButton().transition(.scale.combined(with: .opacity)) }
                accessory
            }
            ActionRow(face: face)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one line. While Poki works, the action's first word is quiet and its object is not: "Scroll"
    /// to “Checkout”.
    private var line: some View {
        let words = face.content.split(separator: " ", maxSplits: 1).map(String.init)
        let lead = face.bottom == .stop && words.count == 2
        return (lead ? Text(words[0] + " ").foregroundStyle(theme.quiet) + Text(words[1]).foregroundStyle(theme.text)
                     : Text(face.content).foregroundStyle(face.stale ? theme.quiet : theme.text))
            .font(theme.content)
            .lineLimit(1).minimumScaleFactor(0.8)
            .contentTransition(.interpolate)
    }

    /// At the right of the row: Stop while working, the approval's time running down, a tick when done.
    @ViewBuilder private var accessory: some View {
        if face.bottom == .stop {
            StopButton().transition(.opacity)
        } else if let range = face.timer {
            ProgressView(timerInterval: range, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.circular).tint(theme.text)
                .frame(width: 24, height: 24)
        } else if case .glyph(let symbol) = face.compact, symbol != "mic.fill" {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(theme.text)
                .frame(width: 24, height: 24).transition(.scale.combined(with: .opacity))
        } else if case .elapsed(let since) = face.meta {
            ElapsedText(since: since, width: 48)
        }
    }
}

/// Under the row: the approval's decision, Done for a handoff, Open Poki, or setup's progress bar.
private struct ActionRow: View {
    var face: ActivityFace
    private let theme = ActivityTheme.current
    var body: some View {
        switch face.bottom {
        case .none, .stop:
            EmptyView()
        case .approval(let id):
            ApprovalButtons(approvalID: id).transition(.activityRow)
        case .handoff(let id):
            HandoffDoneButton(handoffID: id).transition(.activityRow)
        case .open:
            Link(destination: face.link) { ActionLabel(title: String(activity: "Open Poki"), main: true) }
                .transition(.activityRow)
        case .progress(let fraction):
            ProgressView(value: min(1, max(0, fraction)))
                .tint(theme.text)
                .transition(.activityRow)
        }
    }
}

/// Poki's light, low in the island: a soft band of the owner's colours along the bottom edge. It is the
/// one colour here, as it is in the app.
struct LightGlow: View {
    var body: some View {
        let colors = PokiLight.chosen.palette
        LinearGradient(stops: [.init(color: .clear, location: 0.03), .init(color: colors.low, location: 0.2), .init(color: colors.skyLight, location: 0.4),
                               .init(color: colors.warm, location: 0.62), .init(color: colors.warmLight, location: 0.8), .init(color: .clear, location: 0.97)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 26)
            .blur(radius: 12)
            .offset(y: 14)
            .opacity(0.9)
            .accessibilityHidden(true)
    }
}

// MARK: Dynamic Island, expanded

/// Under the camera: the card, with Poki's light along the bottom edge.
struct IslandBottom: View {
    var face: ActivityFace
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        ActivityCard(face: face)
            .padding(.bottom, ActivityMetrics.islandInsets.bottom)
            .background(alignment: .bottom) { LightGlow() }
            .environment(\.colorScheme, .dark)
            .animation(dimmed ? nil : ActivityMotion.phase, value: face)
    }
}

// MARK: Dynamic Island, compact and minimal

/// Poki in the state's pose: the same Poki as in the other presentations, so the compact island reads
/// as the same activity at a glance.
struct CompactLeading: View {
    var face: ActivityFace
    var body: some View {
        HStack(spacing: 3) {
            PoseMark(pose: face.pose, size: ActivityMetrics.compactPose)
            // The microphone is open: said in the small island too.
            if face.talking, face.compact != .glyph("mic.fill") {
                Image(systemName: "mic.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(ActivityTheme.current.text)
            }
        }
        .padding(.leading, 2).environment(\.colorScheme, .dark)
    }
}

/// A glyph or a short value rather than a sentence, so it never truncates.
struct CompactTrailing: View {
    var face: ActivityFace
    private let theme = ActivityTheme.current
    var body: some View {
        Group {
            switch face.compact {
            case .dot:
                // One beat as each action comes in: the island's update animates the dot's content.
                Circle().fill(theme.text).frame(width: 8, height: 8).padding(.trailing, 4)
                    .id(face.content).transition(.scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityLabel(Text(face.content))
            case .glyph(let symbol):
                Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(Text(face.content))
            case .text(let text, let quiet):
                Text(text).font(theme.compact).foregroundStyle(quiet ? theme.quiet : theme.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            case .code(let code):
                Text(code).font(theme.compactCode).foregroundStyle(theme.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
            case .countdown(let until):
                CountdownText(until: until, width: 44)
            case .elapsed(let since):
                ElapsedText(since: since, width: 44)
            }
        }
        .frame(maxWidth: 64, alignment: .trailing)
        .padding(.trailing, 2)
        .environment(\.colorScheme, .dark)
    }
}

/// Another activity shares the island: Poki alone, in the state's pose. While an approval waits, its
/// time runs down in a ring around Poki (counted by the system).
struct MinimalView: View {
    var face: ActivityFace
    var body: some View {
        ZStack {
            if let range = face.timer {
                ProgressView(timerInterval: range, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.circular)
                    .tint(ActivityTheme.current.text)
            }
            PoseMark(pose: face.pose, size: face.timer == nil ? ActivityMetrics.compactPose : 15)
        }
        .frame(width: ActivityMetrics.compactPose, height: ActivityMetrics.compactPose)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: Pieces

/// Poki in one pose. The pictures are the app's (Poki/BearPoses), made small for the widget extension by
/// scripts/make-assets.sh.
struct PoseMark: View {
    var pose: String
    var size: CGFloat
    var body: some View {
        Image("Pose-\(pose)").resizable().scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A button under the content line: a capsule, white for the one that goes on and a quiet fill for the
/// one that does not.
private struct ActionLabel: View {
    var title: String
    var main: Bool
    private let theme = ActivityTheme.current
    var body: some View {
        Text(title).lineLimit(1).minimumScaleFactor(0.85)
        .font(theme.button)
        .foregroundStyle(main ? Color.black : theme.text)
        .frame(maxWidth: .infinity).frame(height: ActivityMetrics.button)
        .background(main ? theme.text : theme.fill, in: Capsule())
        .contentShape(.capsule)
    }
}

/// Don’t allow and Allow: one decision. Allow asks for Face ID first (see ApproveActionIntent).
struct ApprovalButtons: View {
    var approvalID: String

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: DenyActionIntent(approvalID: approvalID)) {
                ActionLabel(title: String(activity: "Don’t allow"), main: false)
            }
            Button(intent: ApproveActionIntent(approvalID: approvalID)) {
                ActionLabel(title: String(activity: "Allow"), main: true)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The one button on the "Your turn" card: the person finished what the agent could not do, and the
/// agent carries on (HandoffDoneIntent).
struct HandoffDoneButton: View {
    var handoffID: String

    var body: some View {
        Button(intent: HandoffDoneIntent(handoffID: handoffID)) {
            ActionLabel(title: String(activity: "Done, carry on"), main: true)
        }
        .buttonStyle(.plain)
    }
}

/// The open microphone of a talk with Poki, which stays open while Poki works in another app. A tap ends
/// the talk and closes it.
struct TalkButton: View {
    var body: some View {
        Button(intent: EndTalkIntent()) {
            Image(systemName: "mic.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(ActivityTheme.current.text)
                .frame(width: ActivityMetrics.stop, height: ActivityMetrics.stop)
                .background(ActivityTheme.current.fill, in: Circle())
                .frame(width: 40, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(activity: "End talk"))
    }
}

/// Stop runner: stops the runner, and with it iOS's automation banner, until the agent's next request.
/// A white square in a quiet circle, no word; VoiceOver reads "Stop".
struct StopButton: View {
    var body: some View {
        Button(intent: StopRunnerIntent()) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(ActivityTheme.current.text)
                .frame(width: 10, height: 10)
                .frame(width: ActivityMetrics.stop, height: ActivityMetrics.stop)
                .background(ActivityTheme.current.fill, in: Circle())
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(activity: "Stop"))
    }
}

/// An approval's time left, counted down by the system between updates.
private struct CountdownText: View {
    var until: Date
    var width: CGFloat
    var body: some View {
        // No fixedSize on timer text: it blanks the whole card on iOS 26.
        Text(timerInterval: Countdown.range(until), countsDown: true)
            .font(ActivityTheme.current.countdown).foregroundStyle(ActivityTheme.current.text)
            .multilineTextAlignment(.trailing)
            .frame(width: width, alignment: .trailing)
    }
}

/// How long the agent has waited for the person, counted up by the system.
private struct ElapsedText: View {
    var since: Date
    var width: CGFloat
    var body: some View {
        Text(timerInterval: since...since.addingTimeInterval(12 * 3600), countsDown: false)
            .font(ActivityTheme.current.countdown).foregroundStyle(ActivityTheme.current.text)
            .multilineTextAlignment(.trailing)
            .frame(width: width, alignment: .trailing)
    }
}

enum Countdown {
    /// Counting down to `until`. The start is fixed just under an hour before it (not "now", which the
    /// system may take at another moment than it draws), so the remaining time is always `until - now`.
    static func range(_ until: Date) -> ClosedRange<Date> { until.addingTimeInterval(-3599)...until }
}

/// The bear, round, like the website's avatar (the app's own screens; the Live Activity uses
/// `PoseMark`).
struct BearMark: View {
    var size: CGFloat
    var body: some View {
        Image("Bear").resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.circle)
            .accessibilityHidden(true)
    }
}

/// The latest screenshot, read from the App Group container (the app's own previews).
struct Thumbnail: View {
    /// The app's own previews draw this when there is no file.
    @MainActor static var previewImage: UIImage?
    var size: CGSize
    var corner: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Group {
            if let image = (SharedContainer.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) }) ?? Self.previewImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(.tertiarySystemFill)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
    }
}
