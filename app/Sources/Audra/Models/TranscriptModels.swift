import Foundation

/// A contiguous block of speech with its position in the media timeline.
struct TranscriptSegment: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var start: Double
    var end: Double
    var text: String
    /// Speaker label, when diarization is available. Reserved for future engines.
    var speaker: String?
    /// Mean recognizer confidence (0–1) for the words in this block, when reported.
    var confidence: Double?
    /// True when the user edited the recognized text by hand.
    var edited: Bool = false
    /// Word-level timing reported by the recognizer. Absent for transcripts made by older versions.
    var words: [TranscriptWord]?

    var duration: Double { max(0, end - start) }

    /// Words with timing. Uses recognizer timing when it is still valid (text not edited),
    /// otherwise distributes the block's time span across words proportionally to their length.
    var timedWords: [TranscriptWord] {
        if !edited, let words, !words.isEmpty { return words }
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return [] }
        let weights = tokens.map { Double($0.count) + 1 }
        let total = weights.reduce(0, +)
        var cursor = start
        return zip(tokens, weights).map { token, weight in
            let length = duration * weight / total
            defer { cursor += length }
            return TranscriptWord(text: token, start: cursor, end: cursor + length, approximate: true)
        }
    }
}

/// A recognized word and the media time span in which it was spoken.
struct TranscriptWord: Codable, Hashable, Sendable {
    var text: String
    var start: Double
    var end: Double
    /// True when timing was estimated rather than reported by the recognizer.
    var approximate: Bool = false
}

struct SummaryChapter: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var start: Double
    var title: String
}

/// Structured, AI-generated summary. Always derived from the transcript, never presented as spoken content.
struct VideoSummary: Codable, Hashable, Sendable {
    var overview: String
    var topics: [String]
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [String]
    var chapters: [SummaryChapter]
    var provider: String
    var detail: SummaryDetail
    var generatedAt: Date = Date()
}

enum SummaryDetail: String, Codable, CaseIterable, Identifiable, Sendable {
    case brief, standard, detailed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .brief: tr("Conciso")
        case .standard: tr("Padrão")
        case .detailed: tr("Detalhado")
        }
    }
    var guidance: String {
        switch self {
        case .brief: "Seja conciso: visão geral em 2 a 3 frases e no máximo 4 itens por lista."
        case .standard: "Visão geral em um parágrafo curto e no máximo 7 itens por lista."
        case .detailed: "Visão geral em até dois parágrafos e até 12 itens por lista, preservando nomes, números e detalhes relevantes."
        }
    }
}

enum ProcessingStatus: String, Codable, Sendable {
    case queued
    case preparing
    case detectingLanguage
    case transcribing
    case summarizing
    case completed
    case failed
    case cancelled

    var isActive: Bool {
        switch self {
        case .queued, .preparing, .detectingLanguage, .transcribing, .summarizing: true
        default: false
        }
    }

    var label: String {
        switch self {
        case .queued: tr("Na fila")
        case .preparing: tr("Preparando mídia")
        case .detectingLanguage: tr("Detectando idioma")
        case .transcribing: tr("Transcrevendo")
        case .summarizing: tr("Gerando resumo")
        case .completed: tr("Concluído")
        case .failed: tr("Falhou")
        case .cancelled: tr("Cancelado")
        }
    }

    var symbol: String {
        switch self {
        case .queued: "clock"
        case .preparing, .detectingLanguage, .transcribing, .summarizing: "waveform"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}
