// Writes the launch screen's pictures from the icon picture it shows in the middle (the Bear image).
//   swift launch-ground.swift <bear.png> <out directory> <feather, pixels>
// The launch screen is that square picture in the middle of a ground that meets it on every side, so the square
// does not show. The icon's ground is one colour across each row and changes only from top to bottom, and the
// bear never reaches the picture's right-hand edge, so each row's colour is the pixel at that edge, as it is.
//   band.png    those colours, one row for each row of the picture: laid across the screen behind the picture
//   top.png     the top row's colour, for everything above the picture
//   bottom.png  the bottom row's colour, for everything below it
//   bear.png    the picture itself. The bear is cut off by the picture's left and bottom edges. With a feather
//               of more than 0, the picture fades into its own ground over that many pixels at those two edges.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String, _ code: Int32 = 1) -> Never {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!); exit(code)
}
let args = CommandLine.arguments
guard args.count == 4, let feather = Int(args[3]), feather >= 0 else { fail("usage: launch-ground.swift bear.png out-directory feather-pixels", 2) }
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil), let icon = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fail("cannot read \(args[1])")
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let width = icon.width, height = icon.height, strip = 8, fill = 12
func bitmap(_ width: Int, _ height: Int) -> (CGContext, UnsafeMutablePointer<UInt8>) {
  guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
        let data = context.data?.assumingMemoryBound(to: UInt8.self) else { fail("cannot make a \(width) by \(height) picture") }
  return (context, data)
}
func write(_ context: CGContext, _ name: String) {
  let path = args[2] + "/" + name
  guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("cannot write \(path)") }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fail("cannot write \(path)") }
}
guard width > strip, feather < min(width, height) else { fail("\(args[1]) is too small") }
let (picture, pixels) = bitmap(width, height)
picture.draw(icon, in: CGRect(x: 0, y: 0, width: width, height: height))

// The bitmap's first row is the picture's top row.
let ground: [[UInt8]] = (0..<height).map { y in
  (0..<3).map { channel in
    let edge = pixels[(y * width + width - 1) * 4 + channel]
    // A new icon whose picture reaches the right-hand edge would put its colours into the ground.
    for x in (width - strip)..<width where abs(Int(pixels[(y * width + x) * 4 + channel]) - Int(edge)) > 3 {
      fail("\(args[1]): row \(y) is not plain ground at the right-hand edge, so the launch ground cannot be read from it")
    }
    return edge
  }
}
func plain(_ width: Int, _ height: Int, _ name: String, _ colour: (Int) -> [UInt8]) {
  let (context, out) = bitmap(width, height)
  for y in 0..<height {
    let row = colour(y)
    for x in 0..<width {
      let at = (y * width + x) * 4
      out[at] = row[0]; out[at + 1] = row[1]; out[at + 2] = row[2]; out[at + 3] = 255
    }
  }
  write(context, name)
}
plain(fill, height, "band.png") { ground[$0] }
plain(fill, fill, "top.png") { _ in ground[0] }
plain(fill, fill, "bottom.png") { _ in ground[height - 1] }

if feather > 0 {
  for y in 0..<height {
    for x in 0..<width {
      let inside = Double(min(x, height - 1 - y)) / Double(feather)
      guard inside < 1 else { continue }
      let keep = inside * inside * (3 - 2 * inside)
      for channel in 0..<3 {
        let at = (y * width + x) * 4 + channel
        pixels[at] = UInt8((Double(ground[y][channel]) * (1 - keep) + Double(pixels[at]) * keep).rounded())
      }
    }
  }
}
write(picture, "bear.png")
let stops = [0, 25, 50, 75, 100].map { share -> String in
  let colour = ground[min(height - 1, height * share / 100)]
  return String(format: "%d%% #%02X%02X%02X", share, colour[0], colour[1], colour[2])
}
print("launch ground beside the picture, top to bottom: " + stops.joined(separator: ", "))
