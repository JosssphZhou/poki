import Foundation
import UIKit
import PokiCore

/// The clipboard is read only when the owner asks a question in the chat. iOS may show its own paste
/// prompt; a refusal leaves the clipboard unread, and an empty clipboard is reported as empty.
enum ClipboardTools {
    static let specs: [ToolSpec] = [
        .make("clipboard_read",
              "Read the text the owner copied, as text. iOS may ask the owner to allow the paste; a refusal means nothing was read. Images or other non-text items are not returned.",
              [:], []),
    ]

    @MainActor static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else {
            return NativeToolAnswer.empty("the clipboard has no text\(pasteboard.hasImages ? " (it has an image; images are not read by this tool)" : "").")
        }
        guard let text = pasteboard.string, !text.isEmpty else {
            return NativeToolAnswer.empty("the clipboard has no text.")
        }
        let value = text.count > 200_000 ? String(text.prefix(200_000)) : text
        let suffix = text.count > value.count ? "\n(the clipboard text was cut to its first \(value.count) characters)" : ""
        return NativeToolAnswer.ok("clipboard:\n" + value + suffix)
    }
}
