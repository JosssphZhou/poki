// Writes the launch screen's ground: the app icon's own ground as a picture to stretch over the whole screen.
//   swift launch-ground.swift <icon.png> <out.png>
// The icon's ground is one colour across each row and changes only from top to bottom, night blue down to sky
// blue. The bear never reaches the icon's right-hand edge, so each row's colour is read there: the mean of the
// last 24 columns, then of 9 rows, which takes out the one-step jitter that stretching would show as lines.
// The picture is 16 pixels wide and as tall as the icon. Nothing changes across it, so stretching it to any
// screen shows the whole ground from top to bottom and nothing else. Prints the colours at five heights.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String, _ code: Int32 = 1) -> Never {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!); exit(code)
}
let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: launch-ground.swift icon.png out.png", 2) }
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil), let icon = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fail("cannot read \(args[1])")
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let width = icon.width, height = icon.height, strip = 24, outWidth = 16
guard width > strip, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let pixels = { context.draw(icon, in: CGRect(x: 0, y: 0, width: width, height: height)); return context.data?.assumingMemoryBound(to: UInt8.self) }() else { fail("cannot draw \(args[1])") }

// The bitmap's first row is the picture's top row.
var rows = [[Double]](repeating: [0, 0, 0], count: height)
for y in 0..<height {
  for channel in 0..<3 {
    var sum = 0, low = 255, high = 0
    for x in (width - strip)..<width {
      let value = Int(pixels[(y * width + x) * 4 + channel])
      sum += value; low = min(low, value); high = max(high, value)
    }
    // A new icon whose picture reaches the right-hand edge would put its colours into the ground.
    guard high - low <= 6 else { fail("\(args[1]): row \(y) is not plain ground at the right-hand edge, so the launch ground cannot be read from it") }
    rows[y][channel] = Double(sum) / Double(strip)
  }
}
let reach = 4
let ground: [[UInt8]] = (0..<height).map { y in
  let window = max(0, y - reach)...min(height - 1, y + reach)
  return (0..<3).map { channel in UInt8((window.reduce(0) { $0 + rows[$1][channel] } / Double(window.count)).rounded()) }
}

guard let output = CGContext(data: nil, width: outWidth, height: height, bitsPerComponent: 8, bytesPerRow: outWidth * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let out = output.data?.assumingMemoryBound(to: UInt8.self) else { fail("cannot make the picture") }
for y in 0..<height {
  for x in 0..<outWidth {
    let at = (y * outWidth + x) * 4
    out[at] = ground[y][0]; out[at + 1] = ground[y][1]; out[at + 2] = ground[y][2]; out[at + 3] = 255
  }
}
guard let image = output.makeImage(), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("cannot write \(args[2])") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(args[2])") }
let stops = [0, 25, 50, 75, 100].map { share -> String in
  let colour = ground[min(height - 1, height * share / 100)]
  return String(format: "%d%% #%02X%02X%02X", share, colour[0], colour[1], colour[2])
}
print("launch ground, top to bottom: " + stops.joined(separator: ", "))
