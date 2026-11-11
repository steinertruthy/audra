import Foundation

/// A run of recognized text, usually a word with its own timing.
struct RecognizedPiece: Sendable, Equatable {
    var text: String
    var start: Double?
    var end: Double?
    var confidence: Double?
}

/// Groups recognizer output into readable, timestamped blocks.
/// Blocks end at sentence boundaries once they are long enough, and are force-split
/// so a single block never spans too much of the timeline (which would make syncing coarse).
enum SegmentBuilder {
    static let preferredMinimum: Double = 4
    static let softMaximum: Double = 12
    static let hardMaximum: Double = 20
    /// A silence this long between words is treated as a natural break.
    static let pauseBreak: Double = 0.7

    static func build(pieces: [RecognizedPiece], fallbackStart: Double, fallbackEnd: Double) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var text = ""
        var start: Double?
        var end: Double?
        var confidences: [Double] = []
        var words: [TranscriptWord] = []

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            defer { text = ""; start = nil; end = nil; confidences = []; words = [] }
            guard !trimmed.isEmpty else { return }
            let s = start ?? segments.last?.end ?? fallbackStart
            let e = max(end ?? fallbackEnd, s)
            let conf = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
            segments.append(TranscriptSegment(start: s, end: e, text: trimmed, confidence: conf,
                                              words: words.isEmpty ? nil : words))
        }

        for piece in pieces {
            // Break on a noticeable pause once the block has some substance.
            if let s = piece.start, let blockStart = start, let blockEnd = end,
               s - blockEnd >= pauseBreak, blockEnd - blockStart >= preferredMinimum {
                flush()
            }
            if let s = piece.start, start == nil { start = s }
            if let e = piece.end { end = max(end ?? e, e) }
            if let c = piece.confidence { confidences.append(c) }
            text += piece.text
            appendWords(of: piece, to: &words)

            guard let s = start, let e = end else { continue }
            let length = e - s
            let trimmed = piece.text.trimmingCharacters(in: .whitespaces)
            let endsSentence = trimmed.last.map { ".?!…".contains($0) } ?? false
            let endsClause = trimmed.last.map { ",;:".contains($0) } ?? false

            if (endsSentence && length >= preferredMinimum)
                || (endsClause && length >= softMaximum)
                || length >= hardMaximum {
                flush()
            }
        }
        flush()
        return segments
    }

    /// A recognizer run may hold one word or several; split it so every word keeps a time span.
    private static func appendWords(of piece: RecognizedPiece, to words: inout [TranscriptWord]) {
        let tokens = piece.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty, let s = piece.start, let e = piece.end, e >= s else { return }
        if tokens.count == 1 {
            words.append(TranscriptWord(text: tokens[0], start: s, end: e))
            return
        }
        let weights = tokens.map { Double($0.count) + 1 }
        let total = weights.reduce(0, +)
        var cursor = s
        for (token, weight) in zip(tokens, weights) {
            let length = (e - s) * weight / total
            words.append(TranscriptWord(text: token, start: cursor, end: cursor + length, approximate: true))
            cursor += length
        }
    }
}
