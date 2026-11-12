// MessageBubble is from Mackarous/ConversationUI (commit e77c69e,
// Sources/ConversationUI/MessageBubble.swift), Copyright (c) 2024 Andrew Mackarous, MIT License. See
// THIRD_PARTY_NOTICES.md. Changed: Poki's message kinds, the ESP-171 board's colours, 17 pt text, the
// tail corner on the last bubble of a run, and 60 pt kept free on the far side (280 pt at most).
import SwiftUI

struct MessageBubble: View {
    enum Direction { case incoming, outgoing }
    var direction: Direction
    var text: String
    /// The last bubble of its run has the small corner on its side.
    var tail: Bool

    var body: some View {
        HStack {
            if direction == .outgoing {
                Spacer(minLength: .messageInsetPadding)
            }
            // Yours is a quiet bubble on the right; Poki's is plain words on the page.
            if direction == .outgoing {
                Text(rendered)
                    .font(.system(size: 17))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Paper.ink)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 16)
                    .background(Paper.fill, in: shape)
                    .contentShape(.contextMenuPreview, shape)
                    .contextMenu { copyButton { UIPasteboard.general.string = text } }
                    .frame(maxWidth: 280, alignment: .trailing)
            } else {
                Text(rendered)
                    .font(.system(size: 17)).lineSpacing(3)
                    .tint(Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Paper.ink)
                    .padding(.vertical, 4)
                    .contextMenu { copyButton { UIPasteboard.general.string = text } }
                    .frame(maxWidth: 330, alignment: .leading)
            }
            if direction == .incoming {
                Spacer(minLength: .messageInsetPadding)
            }
        }
    }

    /// Poki's words as Markdown (bold, italics, code, links), as models write them; the owner's as typed.
    private var rendered: AttributedString {
        guard direction == .incoming, text.contains(where: { "*_`[".contains($0) }),
              let markdown = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(text)
        }
        return markdown
    }

    private var shape: UnevenRoundedRectangle {
        let small: CGFloat = tail ? .tailRadius : .cornerRadius
        return UnevenRoundedRectangle(topLeadingRadius: .cornerRadius,
                                      bottomLeadingRadius: direction == .incoming ? small : .cornerRadius,
                                      bottomTrailingRadius: direction == .outgoing ? small : .cornerRadius,
                                      topTrailingRadius: .cornerRadius, style: .continuous)
    }

    private func copyButton(copy: @escaping () -> Void) -> some View {
        Button(action: copy) {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }
}

extension CGFloat {
    static let cornerRadius: CGFloat = 22
    static let tailRadius: CGFloat = 6
    static let messageInsetPadding: CGFloat = 60
    static let messageVerticalPadding: CGFloat = 9
}

/// The chat's greys. What the conversation itself draws takes the front's paper and ink (`Paper`); the
/// system colours are left for the older pages that still read them.
enum ChatColor {
    /// #E9E9EB on the board (iMessage's incoming bubble): systemGray5, #E5E5EA.
    static let incoming = Paper.fill
    /// Times, the grey notes, an agent's own steps.
    static let secondary = Paper.ink2
    /// #34C759.
    static let green = Color(.systemGreen)
    /// #D1D1D6: the message field's edge.
    static let fieldEdge = Color(.systemGray4)
    /// The bear's own pale blue, as a tint for the message field's glass.
    static let bearBlue = Color(red: 0.72, green: 0.77, blue: 0.98).opacity(0.5)
    /// #C6C6C8: the header's bottom line and the rows' separators.
    static let separator = Color(.opaqueSeparator)
}
