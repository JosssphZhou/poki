import SwiftUI

// The interaction is the earlier Poki iPhone app's question item (a bubble and a column of options,
// and words typed into the message field also answer; MIT License, Copyright (c) 2026 Joseph Zhou and
// contributors). The look is this app's: Poki's bubble and its blues, never an approval card's
// glass, amber, countdown or Hold to Allow, since the model wrote the question and its options.

/// A question from the chat's model (ask_user): Poki's bubble, and while it waits, its options under
/// it, the suggested one first and solid blue, then Other Answer when the owner may type their own.
/// Answered or stopped, only the bubble stays; the answer is the owner's message under it.
struct QuestionCard: View {
    var question: ChatQuestion
    @Environment(\.dynamicTypeSize) private var size
    /// The options can be tapped: the question waits, for this task or for a task that has ended.
    var open: Bool
    var tail: Bool
    var answer: (String) -> Void
    /// Other Answer: the message field takes the owner's own words.
    var other: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MessageBubble(direction: .incoming, text: question.text, tail: tail)
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                        OptionButton(option: option, suggested: question.suggested && i == 0) { answer(option.label) }
                    }
                    if question.other {
                        Button(action: other) {
                            Label("Other answer", systemImage: "pencil")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(.secondaryLabel))
                                .padding(.horizontal, 18).frame(minHeight: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Type your own answer in the message field"))
                    }
                }
                // At the accessibility sizes the options take the row, so their words wrap instead of
                // being cut.
                .frame(maxWidth: size.isAccessibilitySize ? .infinity : 290, alignment: .leading)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.25), value: open)
    }
}

/// One option: the app's icon or the model's emoji in front when there is one, then its words. The
/// suggested option is Poki's solid blue with Suggested at its end; the others are soft blue.
private struct OptionButton: View {
    var option: ChatQuestion.Option
    var suggested: Bool
    var tap: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var size
    /// The icon grows with the words, from 26 points at the default size.
    @ScaledMetric(relativeTo: .callout) private var side: CGFloat = 26

    /// The app the option is to use: the one the model named, else the one app its words name.
    private var app: String? {
        if let named = option.app, let id = AppIconStore.bundleID(named) { return id }
        let named = AppIconStore.bundleIDs(namedIn: option.label)
        return named.count == 1 ? named[0] : nil
    }

    var body: some View {
        // The home page's and the message field's way to an app's icon; with none, nothing stands in
        // front (no placeholder tile).
        let icon = app.flatMap { AppIconStore.shared.icon($0, dark: scheme == .dark) }
        let lead = icon != nil || option.emoji != nil
        let large = size.isAccessibilitySize
        let side = min(self.side, 44)
        Button(action: tap) {
            HStack(spacing: 10) {
                if let icon {
                    let shape = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    Image(uiImage: icon).resizable().interpolation(.high).scaledToFill()
                        .frame(width: side, height: side).clipShape(shape)
                        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                } else if let emoji = option.emoji {
                    Text(emoji).font(.system(size: side * 0.77)).frame(width: side, height: side)
                }
                // At the accessibility sizes the words wrap as far as they need and Suggested goes
                // under them; otherwise two lines at most, Suggested at the end.
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.label)
                        .font(.callout.weight(.semibold))
                        .lineLimit(large ? nil : 2).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: large)
                    if suggested, large { tag }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, large ? 10 : 0)
                if suggested, !large { tag }
            }
            .foregroundStyle(suggested ? .white : Tint.blueText)
            .padding(.leading, lead ? 10 : 18).padding(.trailing, suggested && !large ? 8 : 18)
            .frame(minHeight: 46)
            // A capsule at its 46 points; taller, with wrapped words, the same corners on a rounded block.
            .background(suggested ? Tint.blue : Tint.blueSoft, in: Self.shape)
            // A blue block as the task card draws one: a hairline in dark, a soft blue shadow in light.
            .overlay { Self.shape.strokeBorder(suggested ? Tint.ring : Tint.blueLine, lineWidth: 1) }
            .shadow(color: suggested ? Tint.blueShadow : .clear, radius: 9, y: 6)
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(option.label))
        .accessibilityValue(suggested ? Text("Suggested") : Text(verbatim: ""))
        .accessibilityAddTraits(.isButton)
        .task(id: app) { if let app, icon == nil { await AppIconStore.shared.load(app) } }
    }

    private static let shape = RoundedRectangle(cornerRadius: 23, style: .continuous)

    private var tag: some View {
        Text("Suggested")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9).frame(minHeight: 24)
            .background(.white.opacity(0.2), in: .capsule)
    }
}
