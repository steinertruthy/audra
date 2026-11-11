import Foundation
import NaturalLanguage

/// Identifies the spoken language by transcribing a short excerpt with candidate
/// recognizers and scoring each one by acoustic confidence and textual consistency.
/// Brazilian Portuguese is evaluated first and gets a small prior.
enum LanguageDetector {
    struct Candidate { let identifier: String; let language: NLLanguage; let prior: Double }

    static let candidates: [Candidate] = [
        Candidate(identifier: "pt-BR", language: .portuguese, prior: 0.06),
        Candidate(identifier: "en-US", language: .english, prior: 0),
        Candidate(identifier: "es-ES", language: .spanish, prior: 0),
    ]

    static func detect(sampleURL: URL, onStatus: @escaping @Sendable (String) -> Void) async throws -> Locale {
        var best: (locale: Locale, score: Double)?

        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            guard let locale = await SpeechEngine.resolve(candidate.identifier) else { continue }

            // Only download extra languages when Portuguese clearly doesn't fit.
            if index > 0, !(await SpeechEngine.isInstalled(locale)) {
                onStatus(tr("Baixando modelo de %@…", LanguageNames.name(for: locale.identifier)))
            }
            try await SpeechEngine.ensureAssets(for: locale)

            let (text, confidence) = try await SpeechEngine.sample(audioURL: sampleURL, locale: locale)
            let words = text.split(separator: " ").count
            if words < 3 {
                // Little or no speech in the excerpt: nothing to compare, keep the preferred language.
                if best == nil { best = (locale, 0) }
                break
            }

            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            let textual = recognizer.languageHypotheses(withMaximum: 3)[candidate.language] ?? 0
            let score = confidence * 0.55 + textual * 0.45 + candidate.prior

            if best == nil || score > best!.score { best = (locale, score) }
            // Confident early exit avoids running other recognizers.
            if score >= 0.82 { break }
        }

        guard let best else { throw TranscriptionError.unsupportedLanguage("pt-BR") }
        return best.locale
    }
}
