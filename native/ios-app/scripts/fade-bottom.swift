// Fades the bottom of a picture with a clear ground to nothing, and writes a PNG the same size.
//   swift fade-bottom.swift <in.png> <out.png> <pixels from the bottom edge>
// Only the opacity changes, and only in that last band: the picture is drawn premultiplied and then
// multiplied by the fade, so a fading edge keeps its own colour and leaves no grey rim on a dark ground.
// The fade eases in and out (smoothstep), so no line shows where it begins.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4, let band = Int(args[3]), band > 0 else {
  FileHandle.standardError.write("usage: fade-bottom.swift in.png out.png pixels\n".data(using: .utf8)!); exit(2)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  FileHandle.standardError.write("cannot read \(args[1])\n".data(using: .utf8)!); exit(1)
}
let width = image.width, height = image.height
guard band < height, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
// The context's origin is the bottom left: rows 0 ..< band are the bottom band.
let steps = 16
let alphas: [CGFloat] = (0...steps).map { i in let t = CGFloat(i) / CGFloat(steps); return t * t * (3 - 2 * t) }
let colours = alphas.map { CGColor(gray: 0, alpha: $0) } as CFArray
let locations = (0...steps).map { CGFloat($0) / CGFloat(steps) }
guard let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colours, locations: locations) else { exit(1) }
context.setBlendMode(.destinationIn)
context.clip(to: CGRect(x: 0, y: 0, width: width, height: band))
context.drawLinearGradient(fade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: band), options: [])
guard let output = context.makeImage(), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, output, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
