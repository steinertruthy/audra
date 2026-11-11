// Converts PNG screenshots into web-ready AVIF (1x/2x) and JPEG fallbacks.
//
//   swift scripts/screenshots/optimize.swift <input-dir> <output-dir>
//
// For every name.png it writes name-1440.avif, name-2880.avif and name-1440.jpg.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func resized(_ image: CGImage, width: Int) -> CGImage {
    guard image.width > width else { return image }
    let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

func flattened(_ image: CGImage, background: CGColor) -> CGImage {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL, type: UTType, quality: Double) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }
for file in files.sorted(by: { $0.path < $1.path }) {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    let name = file.deletingPathExtension().lastPathComponent
    // Rounded window corners are transparent; flatten onto the site background for JPEG.
    let canvas = CGColor(srgbRed: 0.027, green: 0.024, blue: 0.035, alpha: 1)
    let small = resized(image, width: min(1440, image.width))
    write(small, to: output.appendingPathComponent("\(name)-1440.avif"), type: UTType("public.avif")!, quality: 0.62)
    write(resized(image, width: min(2880, image.width)), to: output.appendingPathComponent("\(name)-2880.avif"), type: UTType("public.avif")!, quality: 0.55)
    write(flattened(small, background: canvas), to: output.appendingPathComponent("\(name)-1440.jpg"), type: .jpeg, quality: 0.82)
    print("✓ \(name) (\(image.width)×\(image.height))")
}
