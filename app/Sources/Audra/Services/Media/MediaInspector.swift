import AVFoundation
import UniformTypeIdentifiers

struct MediaInfo: Sendable {
    var duration: Double
    var hasVideo: Bool
    var hasAudio: Bool
}

enum MediaInspector {
    /// Extensions offered in the open panel and accepted by drag and drop.
    static let acceptedExtensions: Set<String> = [
        "mp4", "m4v", "mov", "qt", "mkv", "webm", "avi", "wmv", "flv", "mpg", "mpeg", "ts", "mts", "m2ts", "3gp",
        "m4a", "mp3", "wav", "aiff", "aif", "aac", "caf", "flac", "ogg", "opus",
    ]

    /// Containers that AVFoundation cannot open and that need an FFmpeg remux first.
    static let needsProxy: Set<String> = ["mkv", "webm", "avi", "wmv", "flv", "ogg", "opus", "mts", "m2ts", "ts"]

    static var contentTypes: [UTType] {
        var types: [UTType] = [.movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .mpeg4Audio, .mp3, .wav, .aiff]
        types += acceptedExtensions.compactMap { UTType(filenameExtension: $0) }
        return types
    }

    static func isAccepted(_ url: URL) -> Bool {
        acceptedExtensions.contains(url.pathExtension.lowercased())
    }

    static func inspect(_ url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        do {
            guard try await asset.load(.isReadable) else {
                throw MediaError.unreadable("O macOS não reconhece este formato de arquivo.")
            }
            let duration = try await asset.load(.duration).seconds
            let audio = try await asset.loadTracks(withMediaType: .audio)
            let video = try await asset.loadTracks(withMediaType: .video)
            return MediaInfo(duration: duration.isFinite ? duration : 0, hasVideo: !video.isEmpty, hasAudio: !audio.isEmpty)
        } catch let error as MediaError {
            throw error
        } catch {
            throw MediaError.unreadable(error.localizedDescription)
        }
    }
}
