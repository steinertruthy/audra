import Foundation

enum TimeFormat {
    /// `1:02:03` or `02:03`.
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Always `HH:MM:SS`.
    static func full(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// SubRip timestamp: `HH:MM:SS,mmm`.
    static func srt(_ seconds: Double) -> String {
        let ms = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms % 3_600_000) / 60_000, (ms % 60_000) / 1000, ms % 1000)
    }

    /// Human duration such as `1 h 4 min` or `3 min 12 s`.
    static func spoken(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return m > 0 ? tr("%@ h %@ min", h, m) : tr("%@ h", h) }
        if m > 0 { return s > 0 && m < 10 ? tr("%@ min %@ s", m, s) : tr("%@ min", m) }
        return tr("%@ s", s)
    }
}

enum LanguageNames {
    static func name(for identifier: String?) -> String {
        guard let identifier else { return tr("Idioma desconhecido") }
        let pt = Localization.shared.locale
        return pt.localizedString(forIdentifier: identifier)?.capitalizedFirst ?? identifier
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }

    /// Ranges of `query` ignoring case and diacritics.
    func ranges(of query: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var searchRange = startIndex..<endIndex
        while let r = range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            result.append(r)
            searchRange = r.upperBound..<endIndex
        }
        return result
    }

    func matches(_ query: String) -> Bool {
        range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

enum AppPaths {
    static let bundleID = Bundle.main.bundleIdentifier ?? "app.audra.mac"

    static var support: URL {
        // Debug/test runs can point at an isolated library.
        let base = ProcessInfo.processInfo.environment["AUDRA_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Audra", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var store: URL { support.appendingPathComponent("Library.store") }

    static var media: URL {
        let url = support.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var audioCache: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Saved editing projects (`.audraproj` JSON files).
    static var projects: URL {
        let url = support.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Thumbnails, waveforms and other derived editor data; safe to delete at any time.
    static var editorCache: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Editor", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension TimeFormat {
    /// Editing timecode `HH:MM:SS:FF`.
    static func timecode(_ seconds: Double, fps: Double) -> String {
        let fps = max(1, fps.rounded())
        let totalFrames = Int((max(0, seconds.isFinite ? seconds : 0) * fps).rounded(.down))
        let frames = totalFrames % Int(fps)
        let total = totalFrames / Int(fps)
        return String(format: "%02d:%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60, frames)
    }

    /// Compact ruler label: `0:05`, `1:20`, `1:02:00`.
    static func ruler(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
