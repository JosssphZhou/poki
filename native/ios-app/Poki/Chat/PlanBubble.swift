import SwiftUI

/// The steps of a task in one Poki bubble: done steps ticked, the step under way typing its words.
struct PlanBubble: View {
    var steps: [PlanStep]
    var tail: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(steps) { step in
                PlanRow(step: step).transition(PlanMotion.stepTransition)
            }
        }
        .animation(PlanMotion.enter, value: steps)
        .padding(.vertical, 10)
        .padding(.leading, 14).padding(.trailing, 12)
        .background(ChatColor.incoming, in: UnevenRoundedRectangle(topLeadingRadius: .cornerRadius, bottomLeadingRadius: tail ? .tailRadius : .cornerRadius,
                                                                    bottomTrailingRadius: .cornerRadius, topTrailingRadius: .cornerRadius, style: .continuous))
        .frame(maxWidth: ChatLayout.maximumMessageWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PlanRow: View {
    var step: PlanStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ZStack {
                switch step.state {
                case .done:
                    DrawingCheck(color: ChatColor.green).frame(width: 12, height: 12).transition(PlanMotion.swapTransition)
                case .failed:
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(.systemRed)).transition(PlanMotion.swapTransition)
                case .current, .waiting:
                    Circle().strokeBorder(ChatColor.secondary.opacity(0.6), lineWidth: 1).frame(width: 10, height: 10).transition(PlanMotion.swapTransition)
                }
            }
            .frame(width: 12)
            // Match the first line's cap-height centre, including when the label wraps.
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[VerticalAlignment.center] + UIFont.systemFont(ofSize: 15).capHeight / 2
            }
            .animation(PlanMotion.swap, value: step.state)
            Group {
                switch step.state {
                case .current, .waiting:
                    TypewriterText(text: step.state == .waiting ? String(localized: "\(step.text), waiting for you") : step.text,
                                   font: .system(size: 15), color: ChatColor.pending)
                case .done, .failed:
                    Text(step.text).font(.system(size: 15)).foregroundStyle(Color(.label))
                        .transition(PlanMotion.swapTransition.animation(PlanMotion.swap.delay(PlanMotion.stagger)))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .animation(PlanMotion.complete, value: step.state)
        }
        .lineLimit(2)
    }
}

