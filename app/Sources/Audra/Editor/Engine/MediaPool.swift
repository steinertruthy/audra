import AVFoundation
import Foundation

/// Loaded AVFoundation objects for one media file.
struct LoadedMedia: @unchecked Sendable {
    let asset: AVURLAsset
    let video: AVAssetTrack?
    let audio: AVAssetTrack?
    let orientation: CGImagePropertyOrientation
}

/// Caches assets and their tracks so rebuilding the composition after an edit is cheap.
final class MediaPool: @unchecked Sendable {
    static let shared = MediaPool()
    private var loaded: [String: LoadedMedia] = [:]
    private let lock = NSLock()

    func load(_ item: MediaItem) async throws -> LoadedMedia {
        let url = item.playableURL
        let key = url.path
        if let cached = lock.withLock({ loaded[key] }) { return cached }
        guard FileManager.default.fileExists(atPath: url.path) else { throw MediaError.fileMissing(item.name) }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        var orientation = CGImagePropertyOrientation.up
        if let video {
            orientation = CGImagePropertyOrientation(preferredTransform: try await video.load(.preferredTransform))
        }
        let media = LoadedMedia(asset: asset, video: video, audio: audio, orientation: orientation)
        lock.withLock { loaded[key] = media }
        return media
    }

    func forget(_ item: MediaItem) {
        _ = lock.withLock { loaded.removeValue(forKey: item.playableURL.path) }
    }

    /// Reads duration, dimensions and frame rate for a newly imported file.
    static func probe(url: URL, proxy: URL? = nil) async throws -> MediaItem {
        let readable = proxy ?? url
        let asset = AVURLAsset(url: readable, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard try await asset.load(.isReadable) else {
            throw MediaError.unreadable("O macOS não reconhece este formato de arquivo.")
        }
        let duration = try await asset.load(.duration).seconds
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        guard videoTrack != nil || audioTrack != nil else { throw MediaError.noAudioTrack }

        var item = MediaItem(name: url.deletingPathExtension().lastPathComponent,
                             path: url.path,
                             bookmark: try? url.bookmarkData(),
                             proxyPath: proxy?.path,
                             duration: duration.isFinite ? duration : 0,
                             hasVideo: videoTrack != nil,
                             hasAudio: audioTrack != nil)
        if let videoTrack {
            let (size, transform, fps) = try await videoTrack.load(.naturalSize, .preferredTransform, .nominalFrameRate)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            item.width = Int(abs(rect.width).rounded())
            item.height = Int(abs(rect.height).rounded())
            item.frameRate = fps > 0 ? Double(fps) : 30
        }
        return item
    }
}

/// A tiny black movie used as the composition's base layer, so the compositor always has frames to
/// render (gaps, title-only stretches and audio-only projects still produce video).
enum BlackVideo {
    static let url = AppPaths.editorCache.appendingPathComponent("base-black-v1.mov")
    private static let lock = NSLock()

    static func ensure() async throws -> URL {
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let temp = url.deletingLastPathComponent().appendingPathComponent("base-\(UUID().uuidString).mov")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let writer = try AVAssetWriter(outputURL: temp, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 36,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 36,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 0, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? MediaError.conversionFailed("Falha ao preparar a base da composição.")
        }
        lock.withLock {
            if !FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.moveItem(at: temp, to: url) }
            try? FileManager.default.removeItem(at: temp)
        }
        return url
    }
}
