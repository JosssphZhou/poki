import PokiCore
import UIKit
import UniformTypeIdentifiers

@MainActor
enum ScreenshotClipboard {
    static func copy(_ read: PokiCore.ToolAnswer) -> PokiCore.ToolAnswer {
        guard !read.isError, !read.text.contains("screenshot is the one of the read before"),
              let data = read.jpeg, let image = UIImage(data: data), let png = image.pngData() else {
            return PokiCore.ToolAnswer(text: "Screenshot not copied: a fresh readable screen is required. The clipboard is unchanged.\n" + read.text,
                                       jpeg: nil, isError: true)
        }
        UIPasteboard.general.setItems([[UTType.png.identifier: png]], options: [.localOnly: true])
        return PokiCore.ToolAnswer(text: "The current screenshot was copied as an image to this iPhone's clipboard. Nothing has been sent. Open the destination conversation and use its Paste UI, then verify the image attachment and recipient before sending.\n" + read.text,
                                   jpeg: read.jpeg, isError: false)
    }
}
