import AVFoundation
import CoreImage
import Metal

/// How a clip enters (or leaves) the frame during a transition.
struct LayerEffect: Sendable {
    enum Kind: Sendable { case dissolve, slideLeft, wipeLeft, dip(white: Bool, entering: Bool) }
    var kind: Kind
    var start: Double
    var end: Double

    func progress(at t: Double) -> Double? {
        guard t >= start, t <= end, end > start else { return nil }
        return (t - start) / (end - start)
    }
}

/// One video clip as the compositor sees it, in composition time.
struct VideoLayer: Sendable {
    var trackID: CMPersistentTrackID
    var start: Double
    var end: Double
    /// The clip's own (untransitioned) range, for fades.
    var clipStart: Double
    var clipEnd: Double
    var orientation: CGImagePropertyOrientation
    var transform: ClipTransform
    var crop: ClipCrop
    var opacity: Double
    var fadeIn: Double
    var fadeOut: Double
    var effects: [LayerEffect]
}

struct TextLayer: Sendable {
    var start: Double
    var end: Double
    var style: TextStyle
}

/// Instruction for one stretch of the timeline where the same layers are active.
final class AudraInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let layers: [VideoLayer]
    let texts: [TextLayer]
    let background: RGBAColor

    init(timeRange: CMTimeRange, layers: [VideoLayer], texts: [TextLayer], background: RGBAColor, baseTrackID: CMPersistentTrackID) {
        self.timeRange = timeRange
        self.layers = layers
        self.texts = texts
        self.background = background
        var ids = [NSNumber(value: baseTrackID)]
        for layer in layers where !ids.contains(NSNumber(value: layer.trackID)) { ids.append(NSNumber(value: layer.trackID)) }
        self.requiredSourceTrackIDs = ids
    }
}

/// Renders every frame of the edit with Core Image on the GPU. The same compositor drives the
/// preview player and the exporter, so what you see is what gets exported.
final class AudraCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    static let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .name: "Audra"])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    static let outputColorSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()

    private let queue = DispatchQueue(label: "app.audra.compositor", qos: .userInitiated)
    private var cancelled = false

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            if cancelled { request.finishCancelledRequest(); return }
            autoreleasepool {
                guard let instruction = request.videoCompositionInstruction as? AudraInstruction,
                      let output = request.renderContext.newPixelBuffer() else {
                    request.finish(with: NSError(domain: "Audra", code: -1, userInfo: [NSLocalizedDescriptionKey: "Instrução de composição inválida."]))
                    return
                }
                let size = request.renderContext.size
                let image = Self.render(instruction: instruction, time: request.compositionTime.seconds, size: size) { trackID in
                    request.sourceFrame(byTrackID: trackID).map { CIImage(cvPixelBuffer: $0) }
                }
                Self.context.render(image, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: Self.outputColorSpace)
                request.finish(withComposedVideoFrame: output)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        cancelled = true
        queue.async { [self] in cancelled = false }
    }

    // MARK: - Frame rendering (pure, also used for poster frames)

    static func render(instruction: AudraInstruction, time t: Double, size: CGSize,
                       source: (CMPersistentTrackID) -> CIImage?) -> CIImage {
        let frame = CGRect(origin: .zero, size: size)
        let bg = instruction.background
        var output = CIImage(color: CIColor(red: bg.r, green: bg.g, blue: bg.b)).cropped(to: frame)

        for layer in instruction.layers where t >= layer.start - 1e-4 && t < layer.end + 1e-4 {
            guard let raw = source(layer.trackID) else { continue }
            var image = place(raw, layer: layer, in: size)
            var alpha = layer.opacity
            if layer.fadeIn > 0, t < layer.clipStart + layer.fadeIn {
                alpha *= max(0, (t - layer.clipStart) / layer.fadeIn)
            }
            if layer.fadeOut > 0, t > layer.clipEnd - layer.fadeOut {
                alpha *= max(0, (layer.clipEnd - t) / layer.fadeOut)
            }
            var dipAmount = 0.0, dipWhite = false
            for effect in layer.effects {
                guard let p = effect.progress(at: t) else { continue }
                let eased = p * p * (3 - 2 * p)
                switch effect.kind {
                case .dissolve:
                    alpha *= eased
                case .slideLeft:
                    image = image.transformed(by: CGAffineTransform(translationX: (1 - eased) * size.width, y: 0))
                case .wipeLeft:
                    let x = (1 - eased) * size.width
                    image = image.cropped(to: CGRect(x: x, y: 0, width: size.width - x, height: size.height))
                case .dip(let white, let entering):
                    dipWhite = white
                    dipAmount = max(dipAmount, entering ? 1 - eased : eased)
                }
            }
            if alpha < 0.999 { image = image.applyingAlpha(alpha) }
            if alpha > 0.001 { output = image.composited(over: output) }
            if dipAmount > 0.001 {
                let color = dipWhite ? CIColor(red: 1, green: 1, blue: 1, alpha: dipAmount) : CIColor(red: 0, green: 0, blue: 0, alpha: dipAmount)
                output = CIImage(color: color).cropped(to: frame).composited(over: output)
            }
        }

        for text in instruction.texts where t >= text.start - 1e-4 && t < text.end + 1e-4 {
            if let image = TextRenderer.image(for: text, at: t, canvas: size) {
                output = image.composited(over: output)
            }
        }
        return output.cropped(to: frame)
    }

    /// Orients, crops, fits and transforms a source frame into canvas coordinates.
    static func place(_ raw: CIImage, layer: VideoLayer, in size: CGSize) -> CIImage {
        var image = raw.oriented(layer.orientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let w = image.extent.width, h = image.extent.height
        guard w > 0, h > 0 else { return image }

        let crop = layer.crop
        if !crop.isEmpty {
            let rect = CGRect(x: w * crop.left, y: h * crop.bottom,
                              width: w * max(0.02, 1 - crop.left - crop.right),
                              height: h * max(0.02, 1 - crop.top - crop.bottom))
            image = image.cropped(to: rect)
            image = image.transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        }
        let cw = image.extent.width, ch = image.extent.height
        let fit = min(size.width / cw, size.height / ch) * max(0.01, layer.transform.scale)
        let radians = -layer.transform.rotation * .pi / 180
        let transform = CGAffineTransform(translationX: -cw / 2, y: -ch / 2)
            .concatenating(CGAffineTransform(scaleX: fit, y: fit))
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: size.width / 2 + layer.transform.x * size.width,
                                             y: size.height / 2 - layer.transform.y * size.height))
        return image.transformed(by: transform, highQualityDownsample: true)
    }
}

extension CIImage {
    func applyingAlpha(_ alpha: Double) -> CIImage {
        applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
    }
}

extension CGImagePropertyOrientation {
    /// Maps a track's preferred transform to the orientation Core Image should apply.
    init(preferredTransform t: CGAffineTransform) {
        let angle = atan2(t.b, t.a) * 180 / .pi
        let mirrored = t.a * t.d - t.b * t.c < 0
        switch (Int(angle.rounded()), mirrored) {
        case (90, false): self = .right
        case (-90, false): self = .left
        case (180, false), (-180, false): self = .down
        case (0, true): self = .upMirrored
        case (90, true): self = .rightMirrored
        case (-90, true): self = .leftMirrored
        case (180, true), (-180, true): self = .downMirrored
        default: self = .up
        }
    }
}
