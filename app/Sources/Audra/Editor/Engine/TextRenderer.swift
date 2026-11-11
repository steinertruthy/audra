import AppKit
import CoreImage
import CoreText

/// Rasterizes text overlays with Core Text and animates them in canvas space.
/// Rendered bitmaps are cached per style, size and visible character count.
enum TextRenderer {
    private final class Box { let image: CIImage; init(_ image: CIImage) { self.image = image } }
    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 400
        return cache
    }()

    static func image(for layer: TextLayer, at t: Double, canvas: CGSize) -> CIImage? {
        let style = layer.style
        let duration = layer.end - layer.start
        let animation = min(style.animationDuration, duration / 2)

        var alpha = 1.0, scale = 1.0, dy = 0.0
        var characters = style.content.count

        func apply(_ kind: TextAnimation, progress p: Double, entering: Bool) {
            let eased = 1 - pow(1 - min(1, max(0, p)), 3)
            switch kind {
            case .none: break
            case .fade: alpha *= eased
            case .slideUp:
                alpha *= eased
                dy += (1 - eased) * 0.05 * canvas.height * (entering ? 1 : -1)
            case .zoom:
                alpha *= eased
                scale *= 0.82 + 0.18 * eased
            case .typewriter:
                if entering {
                    characters = Int((Double(style.content.count) * min(1, max(0, p))).rounded(.up))
                } else {
                    alpha *= eased
                }
            }
        }

        if style.animationIn != .none {
            // Typewriter reveals over a longer span so it reads naturally.
            let length = style.animationIn == .typewriter ? min(duration * 0.6, Double(style.content.count) * 0.045 + 0.2) : animation
            if length > 0, t < layer.start + length { apply(style.animationIn, progress: (t - layer.start) / length, entering: true) }
        }
        if style.animationOut != .none, animation > 0, t > layer.end - animation {
            apply(style.animationOut, progress: (layer.end - t) / animation, entering: false)
        }
        guard alpha > 0.002, characters > 0 else { return nil }

        guard let base = rasterize(style, canvas: canvas, characters: characters) else { return nil }
        let w = base.extent.width, h = base.extent.height
        let cx = style.x * canvas.width
        let cy = (1 - style.y) * canvas.height - dy
        var image = base.transformed(by: CGAffineTransform(translationX: -w / 2, y: -h / 2)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: cx, y: cy)))
        if alpha < 0.999 { image = image.applyingAlpha(alpha) }
        return image
    }

    /// Bitmap of the text block (with optional background box), origin at zero.
    static func rasterize(_ style: TextStyle, canvas: CGSize, characters: Int) -> CIImage? {
        let content = String(style.content.prefix(characters))
        let key = "\(style.hashValue)|\(Int(canvas.width))x\(Int(canvas.height))|\(characters)" as NSString
        if let cached = cache.object(forKey: key) { return cached.image }

        let fontSize = max(6, style.size * canvas.height)
        let font = makeFont(style, size: fontSize)
        var alignment: CTTextAlignment = switch style.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        var lineSpacing = CGFloat(fontSize * 0.08)
        // The setting pointers must stay valid while the paragraph style is created.
        let paragraph = withUnsafeBytes(of: &alignment) { alignmentBytes in
            withUnsafeBytes(of: &lineSpacing) { spacingBytes in
                let settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: alignmentBytes.count, value: alignmentBytes.baseAddress!),
                    CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: spacingBytes.count, value: spacingBytes.baseAddress!),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color.cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ]
        let attributed = NSAttributedString(string: content.isEmpty ? " " : content, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let maxWidth = max(fontSize * 2, style.maxWidth * canvas.width)
        // Measure with the full text so the box does not jump while typing out.
        let fullAttributed = NSAttributedString(string: style.content.isEmpty ? " " : style.content, attributes: attributes)
        let fullSetter = CTFramesetterCreateWithAttributedString(fullAttributed)
        let fullSize = CTFramesetterSuggestFrameSizeWithConstraints(fullSetter, CFRange(), nil,
                                                                   CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let textSize = CGSize(width: ceil(fullSize.width) + 2, height: ceil(fullSize.height) + 2)

        let padX = style.showBackground ? fontSize * 0.45 : fontSize * 0.2
        let padY = style.showBackground ? fontSize * 0.25 : fontSize * 0.2
        let width = Int(textSize.width + padX * 2), height = Int(textSize.height + padY * 2)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        if style.showBackground {
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: fontSize * 0.22, cornerHeight: fontSize * 0.22, transform: nil))
            ctx.setFillColor(style.background.cgColor)
            ctx.fillPath()
        }
        if style.shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -fontSize * 0.04), blur: fontSize * 0.18,
                          color: CGColor(gray: 0, alpha: 0.6))
        }
        let path = CGPath(rect: CGRect(x: padX, y: padY, width: textSize.width, height: textSize.height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
        CTFrameDraw(frame, ctx)

        guard let cg = ctx.makeImage() else { return nil }
        let image = CIImage(cgImage: cg)
        cache.setObject(Box(image), forKey: key)
        return image
    }

    /// Thread-safe font lookup (the compositor renders off the main thread).
    static func makeFont(_ style: TextStyle, size: CGFloat) -> CTFont {
        var font: CTFont
        switch style.fontName {
        case "SF Pro Display", "SF Pro Rounded", "New York":
            let system = NSFont.systemFont(ofSize: size, weight: style.bold ? .bold : .medium)
            let design: NSFontDescriptor.SystemDesign? = style.fontName == "SF Pro Rounded" ? .rounded
                : style.fontName == "New York" ? .serif : nil
            if let design, let descriptor = system.fontDescriptor.withDesign(design),
               let designed = NSFont(descriptor: descriptor, size: size) {
                font = designed as CTFont
            } else {
                font = system as CTFont
            }
        default:
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: style.fontName] as CFDictionary)
            font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }
        var traits: CTFontSymbolicTraits = []
        if style.bold { traits.insert(.traitBold) }
        if style.italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) {
            font = styled
        }
        return font
    }
}
