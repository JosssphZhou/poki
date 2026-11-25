import Foundation
import Observation
import UIKit

/// Published share batches waiting for the owner. The app reads them when it comes to the front or
/// launches; a batch is claimed before it is imported, so the sheet and the submission cannot run it
/// twice, and a failure puts it back in the ready queue.
@MainActor
@Observable
final class ShareInboxStore {
    static let shared = ShareInboxStore()
    private(set) var batches: [ShareInbox.Batch] = []
    private(set) var lastError: String?

    func refresh() {
        batches = ShareInbox.readyBatches()
    }

    func remove(_ id: UUID) {
        ShareInbox.remove(id)
        refresh()
    }

    func fileURL(_ item: ShareInbox.Item, in batch: ShareInbox.Batch) -> URL? {
        guard let folder = ShareInbox.batch(batch.id)?.folder else { return nil }
        return ShareInbox.fileURL(for: item, in: folder)
    }

    /// Turn the owner's words and the shared files into one chat task. The files are copied into the
    /// app's own workspace first, then the message is sent. The claimed batch is removed only after the
    /// chat accepted the task; a refusal puts it back for another try.
    func accept(_ batch: ShareInbox.Batch, task: String, chat: ChatModel, app: AppModel) -> Bool {
        lastError = nil
        let instruction = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { lastError = AppLocalization.text(LocalizedStringResource("Write what Poki should do with these items.")); return false }
        guard !chat.running else { lastError = AppLocalization.text(LocalizedStringResource("Poki is already working on a task. Try again when it finishes.")); return false }
        guard let claimed = ShareInbox.claim(batch.id), let manifest = ShareInbox.manifest(in: claimed) else {
            lastError = AppLocalization.text(LocalizedStringResource("This share is no longer available."))
            refresh()
            return false
        }
        let destination = NativeWorkspace.sharedImports.appendingPathComponent(batch.id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            }
            var attachments: [ChatAttachment] = []
            var paths: [String] = []
            for item in manifest.items {
                guard let url = ShareInbox.fileURL(for: item, in: claimed) else { continue }
                let name = ShareInbox.safeName(item.originalName ?? item.storedName ?? "shared", type: nil)
                let copy = destination.appendingPathComponent(name)
                try FileManager.default.copyItem(at: url, to: copy)
                paths.append("\(item.summary): \(copy.path)")
                attachments.append(contentsOf: Self.attachments(for: item, at: copy, fallbackName: name))
            }
            if attachments.count > 6 {
                // The composer shows six; the rest travel as text documents with their worked paths.
                let extras = attachments.dropFirst(6)
                attachments = Array(attachments.prefix(6))
                for extra in extras {
                    var document = ChatAttachment(kind: .text(name: extra.name), thumbnail: Data(), images: [])
                    document.textContent = "Shared item: \(extra.name)"
                    attachments.append(document)
                }
            }
            if !paths.isEmpty {
                attachments.append(ChatAttachment(kind: .text(name: "Shared item paths"), thumbnail: Data(), images: [],
                                                 textContent: "The shared items are in Poki's workspace:\n" + paths.joined(separator: "\n")))
            }
            if attachments.isEmpty {
                attachments.append(ChatAttachment(kind: .text(name: "Shared items"), thumbnail: Data(), images: [],
                                                 textContent: manifest.items.map(\.summary).joined(separator: "\n")))
            }
            chat.send(instruction, attachments: attachments)
            ShareInbox.remove(batch.id)
            refresh()
            return true
        } catch {
            try? FileManager.default.removeItem(at: destination)
            ShareInbox.restore(batch.id)
            refresh()
            lastError = AppLocalization.text(LocalizedStringResource("Poki could not import this share: \(error.localizedDescription)"))
            return false
        }
    }

    private static func attachments(for item: ShareInbox.Item, at url: URL, fallbackName: String) -> [ChatAttachment] {
        switch item.kind {
        case .image:
            if let data = try? Data(contentsOf: url), let photo = try? AttachmentReader.photo(data) { return [photo] }
            return [text("Image: \(fallbackName)", "The shared image could not be read: \(url.path)")]
        case .video:
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
            let sizeText = size.map { " (\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)))" } ?? ""
            return [text("Video: \(fallbackName)", "A shared video is in the app's workspace at \(url.path)\(sizeText).")]
        case .webURL:
            var content = "A shared web page: \(item.url ?? "")"
            if let text = item.text, !text.isEmpty { content += "\n\nShared page text:\n\(text)" }
            return [text("Shared web page", content)]
        case .text:
            return [text("Shared text", item.text ?? "")]
        case .file:
            if let content = try? AttachmentReader.file(url) { return [content] }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
            let sizeText = size.map { " (\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)))" } ?? ""
            return [text(fallbackName, "A shared file is in the app's workspace at \(url.path)\(sizeText).")]
        }
    }

    private static func text(_ name: String, _ content: String) -> ChatAttachment {
        ChatAttachment(kind: .text(name: name), thumbnail: Data(), images: [], textContent: content)
    }
}

private extension ChatAttachment {
    var name: String {
        switch kind {
        case .text(let name): return name
        case .pdf(let name): return name
        case .photo: return "Photo"
        }
    }
}
