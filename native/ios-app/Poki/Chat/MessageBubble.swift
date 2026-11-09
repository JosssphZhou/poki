// MessageBubble is from Mackarous/ConversationUI (commit e77c69e,
// Sources/ConversationUI/MessageBubble.swift), Copyright (c) 2024 Andrew Mackarous, MIT License. See
// THIRD_PARTY_NOTICES.md. Changed: Poki's message kinds, colours, typography and tail corners.
// Assistant reports use a readable document layout; outgoing messages keep the compact bubble.
import SwiftUI
import MarkdownUI

enum ChatLayout {
    /// All message kinds share the transcript's available width, capped on wider screens.
    static let maximumMessageWidth: CGFloat = 640
}

struct MessageBubble: View {
    enum Direction { case incoming, outgoing }
    var direction: Direction
    var text: String
    /// The last bubble of its run has the small corner on its side.
    var tail: Bool

    @ViewBuilder
    var body: some View {
        if direction == .incoming {
            AssistantMarkdown(text: text).equatable()
                .tint(Site.blue)
                .frame(maxWidth: ChatLayout.maximumMessageWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .contextMenu { copyButton { UIPasteboard.general.string = text } }
        } else {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(verbatim: text)
                    .font(.system(size: 16))
                    .tint(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .padding(.vertical, .messageVerticalPadding)
                    .padding(.horizontal, 14)
                    .background(Site.blue, in: shape)
                    .contentShape(.contextMenuPreview, shape)
                    .contextMenu { copyButton { UIPasteboard.general.string = text } }
            }
            .frame(maxWidth: ChatLayout.maximumMessageWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
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

/// Native block rendering, including tables, lists and fenced code. A wide table scrolls inside its
/// bubble instead of stretching the transcript off screen. Unchanged replies skip reparsing when
/// the app publishes tool progress or the waiting indicator updates.
struct AssistantMarkdown: View, Equatable {
    let text: String
    var content: MarkdownContent { MarkdownContent(text) }

    var body: some View {
        Markdown(content)
            .markdownTheme(Self.theme)
            .textSelection(.enabled)
    }

    /// Chat typography is deliberately smaller than a document's default 2-em headings. Relative
    /// sizes retain Dynamic Type, while bounded table cells wrap long merchant and item names.
    private static let theme = Theme.basic
        .text {
            FontSize(15)
            ForegroundColor(Color(.label))
        }
        .strong { FontWeight(.semibold) }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(.em(1.27)); FontWeight(.semibold) }
                .markdownMargin(top: 20, bottom: 10)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(.em(1.2)); FontWeight(.semibold) }
                .markdownMargin(top: 18, bottom: 8)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(.em(1.07)); FontWeight(.semibold) }
                .markdownMargin(top: 16, bottom: 8)
        }
        .heading4 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(.em(1)); FontWeight(.semibold) }
                .markdownMargin(top: 14, bottom: 6)
        }
        .heading5 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(.em(1)); FontWeight(.semibold) }
                .markdownMargin(top: 14, bottom: 6)
        }
        .heading6 { configuration in
            configuration.label
                .markdownTextStyle { FontSize(.em(1)); FontWeight(.semibold); ForegroundColor(.secondary) }
                .markdownMargin(top: 14, bottom: 6)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 10)
        }
        .listItem { configuration in
            configuration.label.markdownMargin(top: 3, bottom: 3)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(.em(0.87)) }
                    .padding(12)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .markdownMargin(top: 4, bottom: 12)
        }
        .table { configuration in
            ChatMarkdownTable {
                configuration.label
                    .fixedSize(horizontal: true, vertical: false)
                    .markdownTableBorderStyle(.init(.insideHorizontalBorders, color: Color(.separator).opacity(0.3), width: 0.5))
                    .markdownTableBackgroundStyle(.alternatingRows(
                        Color(.systemBackground), Color(.secondarySystemBackground).opacity(0.45),
                        header: Color(.secondarySystemBackground)))
            }
            .markdownMargin(top: 4, bottom: 14)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(.em(configuration.row == 0 ? 0.8 : 0.87))
                    FontWeight(configuration.row == 0 ? .semibold : .regular)
                    ForegroundColor(configuration.row == 0 ? Color(.secondaryLabel) : Color(.label))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 180, alignment: .leading)
                .relativeLineSpacing(.em(0.2))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
}

/// Wide tables keep their rows together and announce the extra columns. Geometry changes only
/// update the overflow hint; neither the table nor its scroll position gets replaced.
private struct ChatMarkdownTable<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                content()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
            if contentWidth > viewportWidth + 1 {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.and.right")
                    Text("Swipe to see all columns")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color(.secondarySystemBackground).opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.3), lineWidth: 0.5) }
        .transaction { $0.animation = nil }
    }
}

extension CGFloat {
    static let cornerRadius: CGFloat = 20
    static let tailRadius: CGFloat = 6
    static let messageInsetPadding: CGFloat = 60
    static let messageVerticalPadding: CGFloat = 9
}

/// The chat's greys. The boards draw iMessage's light colours, which are iOS's own system colours, so
/// these follow them (and dark mode) instead of fixed values.
enum ChatColor {
    /// #E9E9EB on the board (iMessage's incoming bubble): systemGray5, #E5E5EA.
    static let incoming = Color(.systemGray5)
    /// #8E8E93: times, "Delivered", the grey notes, values.
    static let secondary = Color(.systemGray)
    /// #6B6B70: a step not done yet (Site.text2 on the board).
    static let pending = Color(.secondaryLabel)
    /// #34C759.
    static let green = Color(.systemGreen)
    /// #D1D1D6: the message field's edge.
    static let fieldEdge = Color(.systemGray4)
    /// #A1A1A6: the placeholder.
    static let placeholder = Color(.placeholderText)
    /// #C6C6C8: the header's bottom line and the rows' separators.
    static let separator = Color(.opaqueSeparator)
}
