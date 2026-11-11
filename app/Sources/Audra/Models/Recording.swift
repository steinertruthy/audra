import Foundation
import SwiftData

/// One imported media file and everything derived from it.
@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourcePath: String
    var bookmark: Data?
    /// Locally remuxed copy used for playback/decoding when the original container
    /// is not natively supported by AVFoundation (e.g. MKV, WebM).
    var proxyPath: String?
    var fileSize: Int64
    var fileModified: Date?
    var duration: Double
    var hasVideo: Bool
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var processingSeconds: Double?

    var statusRaw: String
    var errorMessage: String?

    var localeIdentifier: String?
    var languageWasDetected: Bool
    /// Language chosen by the user for this file ("auto" or BCP-47); overrides the global preference.
    var requestedLanguage: String?

    @Attribute(.externalStorage) var segmentsData: Data?
    /// Flattened transcript used for library-wide search.
    var transcriptText: String
    var segmentCount: Int

    @Attribute(.externalStorage) var summaryData: Data?
    var summaryError: String?

    init(url: URL, fileSize: Int64, fileModified: Date?) {
        self.id = UUID()
        self.title = url.deletingPathExtension().lastPathComponent
        self.sourcePath = url.path
        self.bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        self.fileSize = fileSize
        self.fileModified = fileModified
        self.duration = 0
        self.hasVideo = true
        self.createdAt = Date()
        self.updatedAt = Date()
        self.statusRaw = ProcessingStatus.queued.rawValue
        self.languageWasDetected = false
        self.transcriptText = ""
        self.segmentCount = 0
    }

    var status: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue; updatedAt = Date() }
    }

    /// Resolves the original file, following moves/renames through the bookmark.
    var sourceURL: URL {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if stale { self.bookmark = try? url.bookmarkData() ; self.sourcePath = url.path }
                return url
            }
        }
        return URL(fileURLWithPath: sourcePath)
    }

    /// The file that AVFoundation should read for playback and decoding.
    var mediaURL: URL {
        if let proxyPath, FileManager.default.fileExists(atPath: proxyPath) {
            return URL(fileURLWithPath: proxyPath)
        }
        return sourceURL
    }

    var sourceExists: Bool { FileManager.default.fileExists(atPath: sourceURL.path) }

    var fileExtension: String { (sourcePath as NSString).pathExtension.uppercased() }

    var locale: Locale? { localeIdentifier.map(Locale.init(identifier:)) }

    func decodeSegments() -> [TranscriptSegment] {
        guard let segmentsData else { return [] }
        return (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? []
    }

    func store(segments: [TranscriptSegment]) {
        segmentsData = try? JSONEncoder().encode(segments)
        transcriptText = segments.map(\.text).joined(separator: " ")
        segmentCount = segments.count
        updatedAt = Date()
    }

    func decodeSummary() -> VideoSummary? {
        guard let summaryData else { return nil }
        return try? JSONDecoder().decode(VideoSummary.self, from: summaryData)
    }

    func store(summary: VideoSummary?) {
        summaryData = summary.flatMap { try? JSONEncoder().encode($0) }
        updatedAt = Date()
    }
}
