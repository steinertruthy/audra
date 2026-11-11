// Renders the 1200×630 social sharing image from a screenshot and the app icon.
//
//   swift scripts/screenshots/make-og.swift <screenshot.png> <icon.png> <out.jpg>
import AppKit
import UniformTypeIdentifiers

let args = CommandLine.arguments
let shot = NSImage(contentsOfFile: args[1])!
let icon = NSImage(contentsOfFile: args[2])!
let out = URL(fileURLWithPath: args[3])

let w = 1200, h = 630, scale = 2
let ctx = CGContext(data: nil, width: w * scale, height: h * scale, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

NSColor(srgbRed: 0.027, green: 0.024, blue: 0.035, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: w, height: h).fill()
let glow = NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.27, blue: 0.85, alpha: 0.55), NSColor(srgbRed: 0.42, green: 0.27, blue: 0.85, alpha: 0)])!
glow.draw(fromCenter: NSPoint(x: 820, y: 520), radius: 0, toCenter: NSPoint(x: 820, y: 520), radius: 620, options: [])

// Screenshot, bleeding off the right edge.
let shotRect = NSRect(x: 600, y: -30, width: 900, height: 900 * shot.size.height / shot.size.width)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.7); shadow.set()
let clip = NSBezierPath(roundedRect: shotRect, xRadius: 14, yRadius: 14)
NSColor.black.setFill(); clip.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
clip.addClip()
shot.draw(in: shotRect)
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.1).setStroke()
clip.lineWidth = 1; clip.stroke()

// Copy.
icon.draw(in: NSRect(x: 64, y: 448, width: 84, height: 84))
func line(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, x: CGFloat, y: CGFloat, kern: CGFloat = 0) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                               .foregroundColor: NSColor(white: 1, alpha: alpha), .kern: kern]).draw(at: NSPoint(x: x, y: y))
}
line("Audra", size: 30, weight: .semibold, alpha: 0.95, x: 166, y: 476)
line("Do vídeo ao texto.", size: 54, weight: .bold, alpha: 0.97, x: 62, y: 330, kern: -1.8)
line("Do texto ao corte.", size: 54, weight: .bold, alpha: 0.97, x: 62, y: 264, kern: -1.8)
line("Transcrição, resumos com IA e", size: 22, weight: .regular, alpha: 0.62, x: 64, y: 196)
line("edição de vídeo no seu Mac.", size: 22, weight: .regular, alpha: 0.62, x: 64, y: 166)
line("Gratuito · macOS 26 · Apple Silicon", size: 17, weight: .medium, alpha: 0.42, x: 64, y: 84)
NSGraphicsContext.current = nil

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
let small = NSBitmapImageRep(cgImage: image)
_ = small
CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.86, kCGImageDestinationImageMaxPixelSize: 1200] as CFDictionary)
CGImageDestinationFinalize(dest)
print("✓ \(out.path)")
