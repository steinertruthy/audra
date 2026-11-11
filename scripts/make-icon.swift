// Renders the app icon (1024 px master + iconset) with AppKit. Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let inset = 100 * s
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = 24 * s; shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.set()
    NSColor(calibratedRed: 0.10, green: 0.07, blue: 0.16, alpha: 1).setFill(); shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.33, alpha: 1),
                        NSColor(calibratedRed: 0.07, green: 0.05, blue: 0.11, alpha: 1)])!.draw(in: shape, angle: -90)

    // Waveform bars turning into text lines.
    let heights: [CGFloat] = [120, 230, 340, 200, 400, 260, 150]
    let barWidth = 46 * s, gap = 30 * s
    let startX = 250 * s
    let midY = 560 * s
    let accent = NSColor(calibratedRed: 0.65, green: 0.52, blue: 0.98, alpha: 1)
    for (i, h) in heights.enumerated() {
        let x = startX + CGFloat(i) * (barWidth + gap)
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: midY - h * s / 2, width: barWidth, height: h * s), xRadius: barWidth / 2, yRadius: barWidth / 2)
        accent.withAlphaComponent(0.55 + 0.45 * CGFloat(i) / CGFloat(heights.count)).setFill(); bar.fill()
    }
    let lineColor = NSColor.white.withAlphaComponent(0.85)
    for (i, w) in [520.0, 380.0].enumerated() {
        let y = (300 - Double(i) * 74) * Double(s)
        let line = NSBezierPath(roundedRect: NSRect(x: startX, y: CGFloat(y), width: CGFloat(w) * s, height: 34 * s), xRadius: 17 * s, yRadius: 17 * s)
        lineColor.withAlphaComponent(i == 0 ? 0.85 : 0.5).setFill(); line.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: CGFloat(base)).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: CGFloat(base * 2)).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
