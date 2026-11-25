import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The preview for one published share batch: what was shared, a field for the owner's task, Send,
/// Later and Remove. A task is accepted only when the owner writes one; the batch is claimed before
/// its files are imported, so another try cannot submit it twice.
struct SharedInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChatModel.self) private var chat
    @Environment(AppModel.self) private var app
    @State private var task = ""
    @State private var error: String?
    @State private var busy = false

    private var store: ShareInboxStore { .shared }

    var body: some View {
        NavigationStack {
            Group {
                if let batch = store.batches.first {
                    content(batch)
                } else {
                    ContentUnavailableView("No Shared Items", systemImage: "tray",
                                           description: Text("Share a link, photo or file to Poki from Safari, Photos or Files."))
                }
            }
            .navigationTitle("Shared with Poki")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Could Not Send", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .onChange(of: store.batches.count) { _, count in
            if count == 0 { dismiss() }
        }
    }

    private func content(_ batch: ShareInbox.Batch) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(batch.items.count) item\(batch.items.count == 1 ? "" : "s") · \(batch.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(batch.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    preview(item, batch: batch)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.originalName ?? item.summary)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        if item.kind == .webURL, let url = item.url, let link = URL(string: url) {
                            Text(link.host(percentEncoded: false) ?? url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if let bytes = item.byteCount {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            TextField("What should Poki do with these?", text: $task, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 0)
            Button {
                send(batch)
            } label: {
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Text(busy ? "Sending…" : "Send Task")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.running)
            HStack {
                Button("Later") { dismiss() }
                Spacer()
                Button("Remove", role: .destructive) {
                    store.remove(batch.id)
                    dismiss()
                }
            }
            .font(.subheadline)
            if store.batches.count > 1 {
                Text("\(store.batches.count - 1) more share\(store.batches.count == 2 ? "" : "s") waiting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder private func preview(_ item: ShareInbox.Item, batch: ShareInbox.Batch) -> some View {
        if item.kind == .image, let url = store.fileURL(item, in: batch), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: symbol(item.kind))
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.secondary)
        }
    }

    private func symbol(_ kind: ShareInbox.Item.Kind) -> String {
        switch kind {
        case .webURL: return "link"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .video: return "video"
        case .file: return "doc"
        }
    }

    private func send(_ batch: ShareInbox.Batch) {
        busy = true
        let ok = store.accept(batch, task: task, chat: chat, app: app)
        busy = false
        if ok {
            task = ""
            if store.batches.isEmpty { dismiss() }
        } else {
            error = store.lastError ?? AppLocalization.text(LocalizedStringResource("Poki could not take this share."))
        }
    }
}
