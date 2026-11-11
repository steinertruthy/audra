import CoreGraphics
import Foundation

// The editing model is a plain value type. The timeline UI, the preview player and the exporter all
// read the same `EditProject`, and the composition engine is the only thing that turns it into
// AVFoundation objects. Original media files are only ever referenced, never modified.

struct EditProject: Codable, Identifiable, Hashable {
    static let fileExtension = "audraproj"
    static let currentVersion = 1

    var version = EditProject.currentVersion
    var id = UUID()
    var name: String
    var createdAt = Date()
    var modifiedAt = Date()
    var canvas = CanvasSettings()
    var media: [MediaItem] = []
    var tracks: [EditTrack] = []
    var markers: [TimelineMarker] = []
    var viewState = EditorViewState()

    init(name: String) {
        self.name = name
        tracks = [
            EditTrack(kind: .text, name: tr("Texto 1")),
            EditTrack(kind: .video, name: tr("Vídeo 1")),
            EditTrack(kind: .audio, name: tr("Áudio 1")),
        ]
    }
}

struct CanvasSettings: Codable, Hashable {
    var width: Int = 1920
    var height: Int = 1080
    var fps: Double = 30
    var background = RGBAColor.black

    var size: CGSize { CGSize(width: width, height: height) }
    var aspect: Double { Double(width) / Double(max(1, height)) }
}

struct EditorViewState: Codable, Hashable {
    var playhead: Double = 0
    var pixelsPerSecond: Double = 40
    var scrollX: Double = 0
    var transcriptMediaID: UUID?
}

struct TimelineMarker: Codable, Hashable, Identifiable {
    var id = UUID()
    var time: Double
    var title: String
}

// MARK: - Media

struct MediaItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var path: String
    var bookmark: Data?
    /// Playable proxy for containers AVFoundation cannot read (shared with the transcription library).
    var proxyPath: String?
    var duration: Double
    var hasVideo: Bool
    var hasAudio: Bool
    /// Display size after applying the track's preferred transform.
    var width: Int = 0
    var height: Int = 0
    var frameRate: Double = 30
    /// Library recording holding the transcript for this file, when there is one.
    var recordingID: UUID?
    var importedAt = Date()

    var isAudioOnly: Bool { !hasVideo }

    /// Original location, following moves through the bookmark when possible.
    var sourceURL: URL {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return URL(fileURLWithPath: path)
    }

    /// The file AVFoundation reads.
    var playableURL: URL {
        if let proxyPath, FileManager.default.fileExists(atPath: proxyPath) { return URL(fileURLWithPath: proxyPath) }
        return sourceURL
    }

    var isAvailable: Bool { FileManager.default.fileExists(atPath: playableURL.path) }
}

// MARK: - Tracks & clips

enum TrackKind: String, Codable, Hashable, CaseIterable {
    case video, audio, text

    var label: String {
        switch self {
        case .video: tr("Vídeo")
        case .audio: tr("Áudio")
        case .text: tr("Texto")
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .text: "textformat"
        }
    }

    /// Display order in the timeline: titles on top, then video, then audio.
    var displayRank: Int {
        switch self {
        case .text: 0
        case .video: 1
        case .audio: 2
        }
    }
}

enum TrackRole: String, Codable, Hashable {
    case standard
    /// Captions generated from the transcript; regenerating replaces this track's clips.
    case subtitles
}

struct EditTrack: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: TrackKind
    var name: String
    var role: TrackRole = .standard
    /// Audio is silenced for every clip on the track.
    var isMuted = false
    /// Video and text are not drawn.
    var isHidden = false
    /// Locked tracks ignore edits, including ripple operations.
    var isLocked = false
    var clips: [EditClip] = []
}

struct EditClip: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Media reference; nil for text clips.
    var mediaID: UUID?
    /// Position on the timeline, in seconds.
    var start: Double
    /// Source range in media time. For text clips the range is `0..<duration`.
    var sourceIn: Double
    var sourceOut: Double
    var speed: Double = 1

    // Audio
    var volume: Double = 1
    var audioMuted = false
    var audioFadeIn: Double = 0
    var audioFadeOut: Double = 0

    // Video
    var opacity: Double = 1
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var transform = ClipTransform()
    var crop = ClipCrop()
    /// Transition from the previous adjacent clip on the same track.
    var transition: ClipTransition?

    // Text
    var text: TextStyle?

    var label: String?

    var duration: Double { max(0, (sourceOut - sourceIn) / max(speed, 0.01)) }
    var end: Double { start + duration }
    var isText: Bool { text != nil }

    /// Media time shown at timeline time `t` (which should lie inside the clip).
    func sourceTime(atTimeline t: Double) -> Double { sourceIn + (t - start) * speed }
    /// Timeline time at which media time `s` plays.
    func timelineTime(forSource s: Double) -> Double { start + (s - sourceIn) / max(speed, 0.01) }

    func contains(_ t: Double) -> Bool { t >= start - 1e-6 && t < end - 1e-6 }

    static func text(_ style: TextStyle, start: Double, duration: Double) -> EditClip {
        EditClip(start: start, sourceIn: 0, sourceOut: duration, text: style)
    }
}

struct ClipTransform: Codable, Hashable {
    /// Multiplier on top of aspect-fit.
    var scale: Double = 1
    /// Offset of the clip center, as a fraction of the canvas size (y grows downward).
    var x: Double = 0
    var y: Double = 0
    /// Clockwise rotation in degrees.
    var rotation: Double = 0

    var isIdentity: Bool { self == ClipTransform() }
}

/// Fractions of the source frame removed from each edge.
struct ClipCrop: Codable, Hashable {
    var left: Double = 0
    var top: Double = 0
    var right: Double = 0
    var bottom: Double = 0

    var isEmpty: Bool { self == ClipCrop() }
}

enum TransitionKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case dissolve, dipToBlack, dipToWhite, slideLeft, wipeLeft
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dissolve: tr("Dissolver")
        case .dipToBlack: tr("Mergulho no preto")
        case .dipToWhite: tr("Mergulho no branco")
        case .slideLeft: tr("Deslizar")
        case .wipeLeft: tr("Cortina")
        }
    }

    var symbol: String {
        switch self {
        case .dissolve: "circle.lefthalf.filled"
        case .dipToBlack: "moon.fill"
        case .dipToWhite: "sun.max.fill"
        case .slideLeft: "rectangle.righthalf.inset.filled.arrow.right"
        case .wipeLeft: "rectangle.split.2x1"
        }
    }
}

struct ClipTransition: Codable, Hashable {
    var kind: TransitionKind = .dissolve
    var duration: Double = 0.75
}

// MARK: - Text

enum TextAnimation: String, Codable, Hashable, CaseIterable, Identifiable {
    case none, fade, slideUp, zoom, typewriter
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: tr("Nenhuma")
        case .fade: tr("Esmaecer")
        case .slideUp: tr("Deslizar")
        case .zoom: tr("Zoom")
        case .typewriter: tr("Máquina de escrever")
        }
    }
}

enum TextAlignmentOption: String, Codable, Hashable, CaseIterable {
    case leading, center, trailing
}

struct TextStyle: Codable, Hashable {
    var content: String
    var fontName: String = "SF Pro Display"
    /// Font size as a fraction of the canvas height, so text scales with the export resolution.
    var size: Double = 0.075
    var bold = true
    var italic = false
    var color = RGBAColor.white
    var showBackground = false
    var background = RGBAColor(r: 0, g: 0, b: 0, a: 0.55)
    var alignment: TextAlignmentOption = .center
    /// Center of the text block, normalized to the canvas (0…1, y grows downward).
    var x: Double = 0.5
    var y: Double = 0.5
    /// Maximum line width as a fraction of the canvas width.
    var maxWidth: Double = 0.86
    var shadow = true
    var animationIn: TextAnimation = .fade
    var animationOut: TextAnimation = .fade
    var animationDuration: Double = 0.4

    static func title(_ text: String = tr("Título")) -> TextStyle {
        TextStyle(content: text, size: 0.1, bold: true, y: 0.45, animationIn: .zoom, animationOut: .fade)
    }

    static func subtitle(_ text: String = tr("Texto sobre o vídeo")) -> TextStyle {
        TextStyle(content: text, size: 0.055, bold: false, y: 0.5, animationIn: .slideUp)
    }

    static func lowerThird(_ text: String = tr("Nome\nCargo ou descrição")) -> TextStyle {
        TextStyle(content: text, size: 0.045, bold: true, showBackground: true,
                  background: RGBAColor(r: 0.36, g: 0.22, b: 0.78, a: 0.85), alignment: .leading,
                  x: 0.3, y: 0.8, maxWidth: 0.5, shadow: false, animationIn: .slideUp, animationOut: .fade)
    }

    static func caption(_ text: String) -> TextStyle {
        TextStyle(content: text, size: 0.048, bold: true, showBackground: true,
                  background: RGBAColor(r: 0, g: 0, b: 0, a: 0.6), y: 0.86, maxWidth: 0.8, shadow: false,
                  animationIn: .none, animationOut: .none, animationDuration: 0.12)
    }
}

struct RGBAColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    static let white = RGBAColor(r: 1, g: 1, b: 1)
    static let black = RGBAColor(r: 0, g: 0, b: 0)

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// Fonts offered in the text inspector (all ship with macOS).
enum TextFonts {
    static let families = [
        "SF Pro Display", "SF Pro Rounded", "New York", "Helvetica Neue", "Avenir Next", "Futura",
        "Gill Sans", "Optima", "Didot", "Georgia", "Baskerville", "American Typewriter", "Menlo", "Impact",
    ]
}
