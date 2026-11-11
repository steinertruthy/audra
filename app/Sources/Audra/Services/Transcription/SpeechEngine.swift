import AVFoundation
import Speech

enum TranscriptionError: LocalizedError {
    case unavailable
    case unsupportedLanguage(String)
    case assetsUnavailable(String)
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .unavailable:
            tr("O reconhecimento de fala no dispositivo não está disponível neste Mac.")
        case .unsupportedLanguage(let id):
            tr("O idioma %@ não é suportado pelo reconhecimento de fala do macOS.", LanguageNames.name(for: id))
        case .assetsUnavailable(let detail):
            tr("Não foi possível obter o modelo de fala do idioma. Verifique a conexão para o download inicial. %@", detail)
        case .noSpeech:
            tr("Nenhuma fala foi reconhecida neste arquivo.")
        }
    }
}

/// Wraps Apple's on-device `SpeechAnalyzer` / `SpeechTranscriber` (macOS 26).
/// Runs fully offline once the language model is installed and uses the Neural Engine.
enum SpeechEngine {
    static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    static func installedLocales() async -> [Locale] {
        await SpeechTranscriber.installedLocales
    }

    static func resolve(_ identifier: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
    }

    static func isInstalled(_ locale: Locale) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale,
                          transcriptionOptions: [],
                          reportingOptions: [],
                          attributeOptions: [.audioTimeRange, .transcriptionConfidence])
    }

    /// Downloads the on-device model for `locale` if needed (one-time, handled by the system).
    static func ensureAssets(for locale: Locale, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let transcriber = makeTranscriber(locale: locale)
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let observation = progress.map { handler in
                    request.progress.observe(\.fractionCompleted, options: [.new]) { p, _ in handler(p.fractionCompleted) }
                }
                try await request.downloadAndInstall()
                observation?.invalidate()
            }
        } catch {
            throw TranscriptionError.assetsUnavailable(error.localizedDescription)
        }
    }

    /// Transcribes an audio file, streaming finalized blocks through `onSegments` as they are produced.
    static func transcribe(
        audioURL: URL,
        locale: Locale,
        duration: Double,
        onSegments: @escaping @Sendable ([TranscriptSegment], Double) -> Void
    ) async throws -> [TranscriptSegment] {
        let transcriber = makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: audioURL)

        let collector = Task<[TranscriptSegment], Error> {
            var all: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let new = segments(from: result)
                guard !new.isEmpty else { continue }
                all += new
                let reached = result.range.end.seconds
                onSegments(new, duration > 0 && reached.isFinite ? min(1, reached / duration) : 0)
            }
            return all
        }

        do {
            try await withTaskCancellationHandler {
                if let last = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }
            try Task.checkCancellation()
            return try await collector.value
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    /// Quick pass over a short excerpt, used for language identification.
    static func sample(audioURL: URL, locale: Locale) async throws -> (text: String, confidence: Double) {
        let segments = try await transcribe(audioURL: audioURL, locale: locale, duration: 0) { _, _ in }
        let text = segments.map(\.text).joined(separator: " ")
        let confidences = segments.compactMap(\.confidence)
        let mean = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        return (text, mean)
    }

    private static func segments(from result: SpeechTranscriber.Result) -> [TranscriptSegment] {
        let text = result.text
        var pieces: [RecognizedPiece] = []
        for run in text.runs {
            let piece = String(text[run.range].characters)
            let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self]
            let confidence = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self]
            pieces.append(RecognizedPiece(
                text: piece,
                start: range.map { $0.start.seconds },
                end: range.map { $0.end.seconds },
                confidence: confidence
            ))
        }
        return SegmentBuilder.build(pieces: pieces,
                                    fallbackStart: result.range.start.seconds,
                                    fallbackEnd: result.range.end.seconds)
    }
}
