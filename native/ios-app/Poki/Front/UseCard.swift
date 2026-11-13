import SwiftUI

/// What a chat keeps of a phone use, once it has ended: the apps and the time, the steps Poki named, and
/// every action on request. It only shows what the app really has: a plan of named steps for Poki's own
/// tasks (`report_plan`), and for every action its words, its app and whether it went through (the
/// Activity Log). There is never a total to count towards.
struct UseCard: View {
    var steps: [PlanStep]
    /// The actions of this use, oldest first.
    var actions: [ActionLog.Entry]
    @State private var open = false

    private var apps: [String] {
        var seen: [String] = []
        for app in actions.compactMap(\.app) where !seen.contains(app) { seen.append(app) }
        return seen
    }

    /// How long the use took, from its first action to its last: "48 sec".
    private var time: String {
        guard let first = actions.first?.at, let last = actions.last?.at, last.timeIntervalSince(first) >= 1 else { return "" }
        return Duration.seconds(last.timeIntervalSince(first).rounded()).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }

    /// "Messages, Wallet · 48 sec", or whichever half there is.
    private var detail: String { [apps.prefix(3).joined(separator: ", "), time].filter { !$0.isEmpty }.joined(separator: " · ") }

    private var count: String {
        let missed = actions.filter { !$0.ok }.count
        let all = actions.count == 1 ? String(localized: "1 action") : String(localized: "\(actions.count) actions")
        return missed == 0 ? all : String(localized: "\(all), \(missed) didn’t go through")
    }

    /// The actions in order, in runs by the app they happened in.
    private var runs: [(app: String, actions: [ActionLog.Entry])] {
        var out: [(app: String, actions: [ActionLog.Entry])] = []
        for action in actions {
            let app = action.app ?? ""
            if let last = out.indices.last, out[last].app == app { out[last].actions.append(action) } else { out.append((app, [action])) }
        }
        return out
    }

    /// "Calendar · 2 actions · 6 s" for a use with no named steps, where the whole card is one line.
    private var oneLine: String { [apps.prefix(3).joined(separator: ", "), count, time].filter { !$0.isEmpty }.joined(separator: " · ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "iphone").font(.system(size: 16, weight: .medium)).foregroundStyle(Paper.ink)
                    .frame(width: 36, height: 36).background(Paper.fill, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text("Used your iPhone").font(.system(size: 16, weight: .semibold)).foregroundStyle(Paper.ink)
                    let line = steps.isEmpty ? oneLine : detail
                    if !line.isEmpty {
                        Text(verbatim: line).font(Paper.note).monospacedDigit().foregroundStyle(Paper.ink2).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                // With no steps to list, the header itself opens the actions.
                if steps.isEmpty, !actions.isEmpty { chevron }
            }
            .frame(minHeight: 36).padding(.bottom, steps.isEmpty && !open ? 0 : 12)
            .contentShape(.rect)
            .onTapGesture { if steps.isEmpty, !actions.isEmpty { withAnimation(.snappy(duration: 0.2)) { open.toggle() } } }
            ForEach(steps) { step in
                Rectangle().fill(Paper.line).frame(height: 1)
                HStack(alignment: .center, spacing: 12) {
                    mark(step.state)
                    Text(verbatim: step.text).font(.system(size: 16, weight: .medium)).foregroundStyle(Paper.ink)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 46)
                .accessibilityElement(children: .combine)
            }
            if !actions.isEmpty, !steps.isEmpty {
                Rectangle().fill(Paper.line).frame(height: 1)
                Button { withAnimation(.snappy(duration: 0.2)) { open.toggle() } } label: {
                    HStack {
                        Text(verbatim: count).font(.system(size: 17)).monospacedDigit().foregroundStyle(Paper.ink)
                        Spacer()
                        chevron
                    }
                    .frame(minHeight: 48).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(open ? "Hides every action" : "Shows every action"))
            }
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                        if !run.app.isEmpty {
                            Text(verbatim: run.app).font(.system(size: 12, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                                .foregroundStyle(Paper.ink2).padding(.top, 12).padding(.bottom, 4)
                        }
                        ForEach(run.actions) { action in
                            HStack(spacing: 10) {
                                Image(systemName: action.ok ? "checkmark" : "xmark").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Paper.ink2).frame(width: 14)
                                Text(verbatim: ActivityWords.label(action.text)).font(.system(size: 15))
                                    .foregroundStyle(action.ok ? Paper.ink : Paper.ink2)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 30)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Paper.line, lineWidth: 1.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Paper.ink2)
            .rotationEffect(.degrees(open ? 90 : 0))
    }

    @ViewBuilder private func mark(_ state: PlanStep.State) -> some View {
        switch state {
        case .done: PaperMark(kind: .done, size: 22).accessibilityLabel(Text("Done"))
        case .failed: PaperMark(kind: .failed, size: 22).accessibilityLabel(Text("Didn’t go through"))
        // A step that waited for the owner: theirs to do, or to allow.
        case .waiting: PaperMark(kind: .yours, size: 22).accessibilityLabel(Text("Yours"))
        case .current: PaperMark(kind: .number(0), size: 22).opacity(0.5).accessibilityLabel(Text("Not finished"))
        }
    }
}
