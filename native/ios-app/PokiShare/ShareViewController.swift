import UIKit
import UniformTypeIdentifiers

/// The share sheet's Poki entry. It copies every attachment into an unpublished batch in the App
/// Group container before the provider's temporary URL can go away, then publishes the batch atomically
/// and tells the owner to open Poki. The app does the preview, the task text and the submission.
final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let statusLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var batchID = UUID()
    private var staging: URL?
    private var items: [ShareInbox.Item] = []
    private var loading = false
    private var finished = false
    private var published = false

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !published, let staging { try? FileManager.default.removeItem(at: staging) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.text = "Save to Poki"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center
        summaryLabel.font = .preferredFont(forTextStyle: .subheadline)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0
        summaryLabel.textAlignment = .center
        summaryLabel.text = "Reading the shared items…"
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        saveButton.setTitle("Save to Poki", for: .normal)
        saveButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        spinner.hidesWhenStopped = true
        saveButton.isEnabled = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, summaryLabel, statusLabel, spinner, saveButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
        load()
    }

    private func load() {
        guard !loading else { return }
        loading = true
        saveButton.isEnabled = false
        summaryLabel.text = "Reading the shared items…"
        statusLabel.text = nil
        spinner.startAnimating()
        batchID = UUID()
        items = []
        Task { @MainActor in
            do {
                let folder = try ShareInbox.staging(batchID)
                staging = folder
                let extensions = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
                let providers = extensions.flatMap { $0.attachments ?? [] }
                guard !providers.isEmpty else { throw ShareInbox.InboxError.noItems }
                for provider in providers {
                    if let item = try await read(provider, into: folder) {
                        items.append(item)
                    }
                }
                try ShareInbox.writeManifest(ShareInbox.Batch(id: batchID, items: items), in: folder)
                loading = false
                spinner.stopAnimating()
                saveButton.isEnabled = !items.isEmpty
                summaryLabel.text = "\(items.count) item\(items.count == 1 ? "" : "s") shared with Poki"
                statusLabel.text = items.map(\.summary).joined(separator: "\n")
            } catch {
                loading = false
                spinner.stopAnimating()
                summaryLabel.text = "Poki could not read this share"
                statusLabel.text = error.localizedDescription
                saveButton.isEnabled = false
                if let staging { try? FileManager.default.removeItem(at: staging) }
                staging = nil
                showError(error)
            }
        }
    }

    private func read(_ provider: NSItemProvider, into folder: URL) async throws -> ShareInbox.Item? {
        let types = provider.registeredTypeIdentifiers
        if let type = types.first(where: { UTType($0)?.conforms(to: .image) == true }) {
            let data = try await loadData(provider, type)
            let ut = UTType(type)
            let stored = try ShareInbox.store(data: data, originalName: provider.suggestedName, type: ut, in: folder)
            return ShareInbox.Item(kind: .image, storedName: stored, originalName: provider.suggestedName ?? stored,
                                   typeIdentifier: type, byteCount: data.count)
        }
        if let type = types.first(where: { isMovie($0) }) {
            let url = try await loadFile(provider, type)
            let ut = UTType(type)
            let name = provider.suggestedName ?? url.lastPathComponent
            let stored = try ShareInbox.store(fileAt: url, originalName: name, type: ut, in: folder)
            return ShareInbox.Item(kind: .video, storedName: stored, originalName: name, typeIdentifier: type,
                                   byteCount: size(of: folder.appendingPathComponent(stored)))
        }
        if let type = types.first(where: { UTType($0)?.conforms(to: .url) == true || UTType($0)?.conforms(to: .text) == true }) {
            if let url = try await loadURL(provider, type), url.scheme == "http" || url.scheme == "https" {
                return ShareInbox.Item(kind: .webURL, typeIdentifier: type, url: url.absoluteString)
            }
            if let url = try await loadURL(provider, type), url.isFileURL {
                let ut = UTType(filenameExtension: url.pathExtension)
                let name = provider.suggestedName ?? url.lastPathComponent
                let kind: ShareInbox.Item.Kind = ut?.conforms(to: .image) == true ? .image : (ut?.conforms(to: .movie) == true ? .video : .file)
                let stored = try ShareInbox.store(fileAt: url, originalName: name, type: ut, in: folder)
                return ShareInbox.Item(kind: kind, storedName: stored, originalName: name, typeIdentifier: type,
                                       byteCount: size(of: folder.appendingPathComponent(stored)))
            }
            if let text = try await loadText(provider, type) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                // A file URL appears as text only when the provider has no better type; it is handled below.
                return ShareInbox.Item(kind: .text, typeIdentifier: type, text: String(trimmed.prefix(100_000)))
            }
        }
        if let type = types.first(where: { UTType($0)?.conforms(to: .item) == true }) ?? types.first {
            do {
                let url = try await loadFile(provider, type)
                let ut = UTType(type) ?? UTType(filenameExtension: url.pathExtension)
                let name = provider.suggestedName ?? url.lastPathComponent
                let kind: ShareInbox.Item.Kind = ut?.conforms(to: .image) == true ? .image : (isMovie(type) ? .video : .file)
                let stored = try ShareInbox.store(fileAt: url, originalName: name, type: ut, in: folder)
                return ShareInbox.Item(kind: kind, storedName: stored, originalName: name, typeIdentifier: type,
                                       byteCount: size(of: folder.appendingPathComponent(stored)))
            } catch {
                // A provider that cannot give a file may still give its bytes below.
            }
            do {
                let data = try await loadData(provider, type)
                let ut = UTType(type)
                let stored = try ShareInbox.store(data: data, originalName: provider.suggestedName, type: ut, in: folder)
                return ShareInbox.Item(kind: .file, storedName: stored, originalName: provider.suggestedName ?? stored,
                                       typeIdentifier: type, byteCount: data.count)
            } catch {
                // No readable representation from this provider.
            }
        }
        return nil
    }

    private func loadData(_ provider: NSItemProvider, _ type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: ShareInbox.InboxError.itemMissing(type)) }
            }
        }
    }

    private func loadFile(_ provider: NSItemProvider, _ type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: ShareInbox.InboxError.itemMissing(type)) }
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider, _ type: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                if let url = item as? URL { continuation.resume(returning: url); return }
                if let url = item as? NSURL { continuation.resume(returning: url as URL); return }
                if let text = item as? String, let url = URL(string: text), url.scheme != nil {
                    continuation.resume(returning: url); return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider, _ type: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                if let text = item as? String { continuation.resume(returning: text); return }
                if let text = item as? NSAttributedString { continuation.resume(returning: text.string); return }
                continuation.resume(returning: nil)
            }
        }
    }

    private func isMovie(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    private func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    }

    @objc private func saveTapped() {
        guard staging != nil, !items.isEmpty else { return }
        saveButton.isEnabled = false
        spinner.startAnimating()
        do {
            try ShareInbox.publish(batchID)
            published = true
            finished = true
            spinner.stopAnimating()
            let alert = UIAlertController(title: "Saved to Poki",
                                          message: "Open Poki to preview the shared items and send a task.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.complete() })
            present(alert, animated: true)
        } catch {
            spinner.stopAnimating()
            saveButton.isEnabled = true
            showError(error)
        }
    }

    @objc private func cancelTapped() {
        if let staging { try? FileManager.default.removeItem(at: staging) }
        finish(cancelled: true)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Could Not Save", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            if let staging = self?.staging { try? FileManager.default.removeItem(at: staging) }
            self?.staging = nil
            self?.load()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.cancelTapped() })
        present(alert, animated: true)
    }

    private func complete() {
        guard !finished || extensionContext != nil else { return }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func finish(cancelled: Bool) {
        guard extensionContext != nil else { return }
        extensionContext?.cancelRequest(withError: NSError(domain: "PokiShare", code: cancelled ? 1 : 0,
                                                           userInfo: [NSLocalizedDescriptionKey: "The share was cancelled."]))
    }
}
