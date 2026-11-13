import PhotosUI
import SwiftUI
import UIKit

/// The pictures an owner adds to a message. Each is scaled down once and kept as a JPEG beside the saved
/// sessions; a chat entry holds only the file names, so a session's file stays small.
enum ChatPictures {
    /// How many one message takes.
    static let limit = 4
    /// The long side the model gets. A larger picture costs more and reads no better.
    static let longSide: CGFloat = 1568

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base.appendingPathComponent("Poki/Pictures", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A name from a saved session never leaves the folder.
    private static func file(_ name: String) -> URL { folder.appendingPathComponent((name as NSString).lastPathComponent) }

    /// Any picture as the JPEG Poki keeps and sends: upright, no larger than `longSide`.
    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, longSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func save(_ jpeg: Data) -> String? {
        let name = UUID().uuidString.lowercased() + ".jpg"
        do { try jpeg.write(to: file(name), options: .atomic); return name } catch { return nil }
    }

    static func data(_ name: String) -> Data? { try? Data(contentsOf: file(name)) }
    static func image(_ name: String) -> UIImage? { UIImage(contentsOfFile: file(name).path) }
    static func delete(_ names: [String]) { for name in names { try? FileManager.default.removeItem(at: file(name)) } }

    /// The pictures a conversation's entries name.
    static func names(in entries: [ChatEntry]) -> [String] {
        entries.flatMap { entry -> [String] in if case .pictures(let names) = entry.kind { names } else { [] } }
    }
}

/// A picture waiting in the message field, before it is sent.
struct PictureDraft: Identifiable, Equatable {
    let id = UUID()
    var jpeg: Data
    var image: UIImage

    init?(_ data: Data) {
        guard let jpeg = ChatPictures.jpeg(from: data), let image = UIImage(data: jpeg) else { return nil }
        self.jpeg = jpeg
        self.image = image
    }

    static func == (a: PictureDraft, b: PictureDraft) -> Bool { a.id == b.id }
}

/// The pictures waiting in the message field: a row of thumbnails, each with a button that takes it out.
struct PictureDraftRow: View {
    @Binding var drafts: [PictureDraft]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(drafts) { draft in
                    Image(uiImage: draft.image).resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Paper.ink.opacity(0.1), lineWidth: 1))
                        .overlay(alignment: .topTrailing) {
                            Button { withAnimation(.snappy(duration: 0.2)) { drafts.removeAll { $0.id == draft.id } } } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(Paper.page)
                                    .frame(width: 20, height: 20).background(Paper.ink, in: Circle())
                                    .frame(width: 44, height: 44, alignment: .topTrailing).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel(Text("Remove picture"))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Picture"))
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(.top, 8).padding(.trailing, 8)
        }
        .scrollClipDisabled()
    }
}

/// The pictures of a sent message, on the owner's side of the chat. A tap opens one full size.
struct PictureBubbles: View {
    var names: [String]
    @State private var opened: Opened?

    private struct Opened: Identifiable { let id: String }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(names, id: \.self) { name in
                Button { opened = Opened(id: name) } label: {
                    Group {
                        if let image = ChatPictures.image(name) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            // The file is gone (an older backup, or the session came from another phone).
                            Paper.fill.overlay(Image(systemName: "photo").foregroundStyle(Paper.ink2))
                        }
                    }
                    .frame(width: names.count == 1 ? 180 : 96, height: names.count == 1 ? 180 : 96)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Paper.ink.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Picture"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .fullScreenCover(item: $opened) { picture in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let image = ChatPictures.image(picture.id) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button { opened = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 36, height: 36).background(.white, in: Circle())
                        .frame(width: 44, height: 44).contentShape(.rect)
                }
                .padding(.trailing, 12)
                .accessibilityLabel(Text("Close"))
            }
        }
    }
}

/// Reads what the Photos picker returned into drafts, in the order picked, up to the room left.
enum PicturePicking {
    @MainActor static func load(_ items: [PhotosPickerItem], room: Int) async -> [PictureDraft] {
        var drafts: [PictureDraft] = []
        for item in items.prefix(max(0, room)) {
            if let data = try? await item.loadTransferable(type: Data.self), let draft = PictureDraft(data) { drafts.append(draft) }
        }
        return drafts
    }

    /// The same for files picked in Files: each is read inside its security scope.
    static func load(_ urls: [URL], room: Int) -> [PictureDraft] {
        urls.prefix(max(0, room)).compactMap { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return (try? Data(contentsOf: url)).flatMap(PictureDraft.init)
        }
    }
}
