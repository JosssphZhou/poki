import Foundation
import UniformTypeIdentifiers

/// The Share Extension's hand-off to Poki. A share writes files and a manifest into an unpublished
/// staging folder inside the App Group container, then renames the whole folder into `ready` only
/// after every item is there. The app sees nothing before that rename; it claims a batch atomically
/// before importing it, so a crash or a retry cannot submit the same share twice.
///
/// Paths are always relative to a batch folder and are resolved with the batch folder as the root;
/// a `..` or a symlink that leaves it is refused.
enum ShareInbox {
    static let manifestName = "manifest.json"

    struct Item: Codable, Hashable, Identifiable {
        enum Kind: String, Codable, Hashable {
            case webURL, text, image, video, file
        }
        var id: UUID = UUID()
        var kind: Kind
        /// The name inside the batch folder; nil for a link or a piece of text.
        var storedName: String?
        var originalName: String?
        var typeIdentifier: String?
        var url: String?
        var text: String?
        var byteCount: Int?

        var summary: String {
            switch kind {
            case .webURL: return url ?? "A web link"
            case .text: return text?.split(whereSeparator: \.isWhitespace).first.map(String.init).map { "“\($0)…”" } ?? "Text"
            case .image: return originalName ?? "An image"
            case .video: return originalName ?? "A video"
            case .file: return originalName ?? "A file"
            }
        }
    }

    struct Batch: Codable, Hashable, Identifiable {
        var version: Int = 1
        var id: UUID
        var createdAt: Date = Date()
        var items: [Item]
    }

    enum InboxError: LocalizedError {
        case appGroupUnavailable
        case noItems
        case missingManifest
        case itemMissing(String)
        case unsafePath
        case alreadyPublished
        case notReady

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable: return "Poki's shared container is not available; the share was not saved."
            case .noItems: return "There is nothing to share."
            case .missingManifest: return "The share's manifest is missing; the share was not published."
            case .itemMissing(let name): return "“\(name)” did not finish copying; the share was not published."
            case .unsafePath: return "The share's file name would leave the shared folder; the share was not published."
            case .alreadyPublished: return "This share was already published."
            case .notReady: return "This share is not ready."
            }
        }
    }

    static func container() -> URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PokiAppGroup") as? String,
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return url.appendingPathComponent("ShareInbox", isDirectory: true)
    }

    static func readyFolder(_ root: URL? = nil) -> URL? {
        (root ?? container())?.appendingPathComponent("ready", isDirectory: true)
    }

    static func stagingFolder(_ root: URL? = nil) -> URL? {
        (root ?? container())?.appendingPathComponent("staging", isDirectory: true)
    }

    static func claimedFolder(_ root: URL? = nil) -> URL? {
        (root ?? container())?.appendingPathComponent("claimed", isDirectory: true)
    }

    /// A new, unpublished folder for one share. The extension copies files here and writes the
    /// manifest; `publish` makes it visible to the app.
    static func staging(_ id: UUID, root: URL? = nil) throws -> URL {
        guard let root = root ?? container() else { throw InboxError.appGroupUnavailable }
        let folder = root.appendingPathComponent("staging/\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func writeManifest(_ batch: Batch, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(batch)
        try data.write(to: folder.appendingPathComponent(manifestName), options: .atomic)
    }

    /// Publish all at once: every referenced file must exist and stay inside the folder, then the
    /// staging folder is renamed into `ready`. A failed check removes the staging folder.
    static func publish(_ id: UUID, root: URL? = nil) throws {
        guard let root = root ?? container() else { throw InboxError.appGroupUnavailable }
        let staging = root.appendingPathComponent("staging/\(id.uuidString)", isDirectory: true)
        guard let data = try? Data(contentsOf: staging.appendingPathComponent(manifestName)),
              let batch = try? decode(data) else { throw InboxError.missingManifest }
        for item in batch.items where item.storedName != nil {
            guard let url = fileURL(for: item, in: staging), FileManager.default.fileExists(atPath: url.path) else {
                try? FileManager.default.removeItem(at: staging)
                throw InboxError.itemMissing(item.originalName ?? item.storedName ?? "a shared file")
            }
        }
        let ready = root.appendingPathComponent("ready/\(id.uuidString)", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: ready.path) else { throw InboxError.alreadyPublished }
        try FileManager.default.createDirectory(at: ready.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try FileManager.default.moveItem(at: staging, to: ready)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// A claimed batch left by a crash before import becomes ready again. A live import holds the
    /// batch only for the synchronous store call, so a refresh cannot race one.
    static func recoverClaimed(root: URL? = nil) {
        guard let root = root ?? container() else { return }
        let claimed = root.appendingPathComponent("claimed", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: claimed.path)) ?? []
        for name in names {
            let from = claimed.appendingPathComponent(name, isDirectory: true)
            let to = root.appendingPathComponent("ready/\(name)", isDirectory: true)
            guard FileManager.default.fileExists(atPath: from.path),
                  !FileManager.default.fileExists(atPath: to.path) else { continue }
            try? FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: from, to: to)
        }
    }

    /// Every published batch, oldest first. Only folders with a decodable manifest are returned.
    static func readyBatches(root: URL? = nil) -> [Batch] {
        recoverClaimed(root: root)
        guard let folder = readyFolder(root) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let batches = names.compactMap { name -> Batch? in
            let file = folder.appendingPathComponent(name).appendingPathComponent(manifestName)
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? decode(data)
        }
        return batches.sorted { $0.createdAt < $1.createdAt }
    }

    /// Decode the manifest inside a batch folder (ready, claimed or staging).
    static func manifest(in folder: URL) -> Batch? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(manifestName)) else { return nil }
        return try? decode(data)
    }

    static func batch(_ id: UUID, root: URL? = nil) -> (batch: Batch, folder: URL)? {
        guard let folder = readyFolder(root)?.appendingPathComponent(id.uuidString, isDirectory: true),
              let data = try? Data(contentsOf: folder.appendingPathComponent(manifestName)),
              let batch = try? decode(data) else { return nil }
        return (batch, folder)
    }

    /// Claim a published batch before importing it. The rename is the claim: a second claim finds
    /// nothing, and a crash after the rename leaves the batch in `claimed` for a later retry.
    static func claim(_ id: UUID, root: URL? = nil) -> URL? {
        guard let root = root ?? container() else { return nil }
        let ready = root.appendingPathComponent("ready/\(id.uuidString)", isDirectory: true)
        guard FileManager.default.fileExists(atPath: ready.path) else { return nil }
        let claimed = root.appendingPathComponent("claimed/\(id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: claimed.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try FileManager.default.moveItem(at: ready, to: claimed)
            return claimed
        } catch {
            return nil
        }
    }

    /// Put a claimed batch back when the import could not start, so the owner can try again.
    static func restore(_ id: UUID, root: URL? = nil) {
        guard let root = root ?? container() else { return }
        let claimed = root.appendingPathComponent("claimed/\(id.uuidString)", isDirectory: true)
        let ready = root.appendingPathComponent("ready/\(id.uuidString)", isDirectory: true)
        guard FileManager.default.fileExists(atPath: claimed.path), !FileManager.default.fileExists(atPath: ready.path) else { return }
        try? FileManager.default.moveItem(at: claimed, to: ready)
    }

    static func remove(_ id: UUID, root: URL? = nil) {
        guard let root = root ?? container() else { return }
        for name in ["ready", "claimed", "staging"] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("\(name)/\(id.uuidString)", isDirectory: true))
        }
    }

    static func fileURL(for item: Item, in folder: URL) -> URL? {
        guard let name = item.storedName else { return nil }
        return contained(name, in: folder)
    }

    /// A safe, unique file name inside a batch folder. The original extension is kept when there is
    /// one; path separators and control characters are removed.
    static func store(data: Data, originalName: String?, type: UTType?, in folder: URL) throws -> String {
        let fallback = "shared-\(UUID().uuidString.prefix(8))"
        let name = safeName(originalName ?? fallback, type: type)
        let url = try unique(name, in: folder)
        try data.write(to: url, options: .atomic)
        return url.lastPathComponent
    }

    /// Copy a provider's temporary file before its callback returns. A security-scoped URL is opened
    /// only for the copy and closed afterwards.
    static func store(fileAt source: URL, originalName: String?, type: UTType?, in folder: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let name = safeName(originalName ?? source.lastPathComponent, type: type ?? UTType(filenameExtension: source.pathExtension))
        let url = try unique(name, in: folder)
        try FileManager.default.copyItem(at: source, to: url)
        return url.lastPathComponent
    }

    static func safeName(_ original: String, type: UTType? = nil) -> String {
        let base = (original as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-()[]"))
        var name = String(base.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "shared" }
        if (name as NSString).pathExtension.isEmpty, let ext = type?.preferredFilenameExtension, !ext.isEmpty {
            name += ".\(ext)"
        }
        return name.count > 180 ? String(name.suffix(180)) : name
    }

    private static func unique(_ name: String, in folder: URL) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 1...999 {
            let candidate = index == 1 ? name : (ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)")
            let url = folder.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return folder.appendingPathComponent("\(base)-\(UUID().uuidString).\(ext)")
    }

    /// Resolve a relative name inside `folder`, following symlinks, and refuse anything outside it.
    static func contained(_ name: String, in folder: URL) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { return nil }
        let base = folder.resolvingSymlinksInPath().standardizedFileURL
        let url = folder.appendingPathComponent(name).resolvingSymlinksInPath().standardizedFileURL
        let root = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return url.path == base.path || url.path.hasPrefix(root) ? url : nil
    }

    private static func decode(_ data: Data) throws -> Batch {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Batch.self, from: data)
    }
}
