import Foundation

struct SummaryRequest: Sendable {
    var title: String
    var segments: [TranscriptSegment]
    var localeIdentifier: String
    var detail: SummaryDetail

    var languageName: String { LanguageNames.name(for: localeIdentifier) }
}

protocol Summarizer: Sendable {
    var displayName: String { get }
    func summarize(_ request: SummaryRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> VideoSummary
}

enum SummaryError: LocalizedError {
    case emptyTranscript
    case modelUnavailable(String)
    case unsupportedLanguage(String)
    case consentRequired
    case missingAPIKey
    case api(String)
    case refused
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyTranscript: tr("Não há fala transcrita suficiente para gerar um resumo.")
        case .modelUnavailable(let reason): reason
        case .unsupportedLanguage(let name): tr("O modelo de resumo no dispositivo ainda não suporta %@.", name)
        case .consentRequired: tr("O envio da transcrição para a API da Anthropic não foi autorizado. Ative a permissão em Ajustes › Resumo.")
        case .missingAPIKey: tr("Informe uma chave da API da Anthropic em Ajustes › Resumo.")
        case .api(let message): tr("A API retornou um erro: %@", message)
        case .refused: tr("O modelo recusou resumir este conteúdo.")
        case .invalidResponse: tr("A resposta do modelo não pôde ser interpretada.")
        }
    }
}

enum SummarizerFactory {
    static func make() -> any Summarizer {
        switch Preferences.summaryProvider {
        case .apple: AppleIntelligenceSummarizer()
        case .claude: ClaudeSummarizer(model: Preferences.claudeModel)
        }
    }
}

/// Shared prompt rules that keep summaries faithful to what was actually said.
enum SummaryPrompts {
    static func faithfulnessRules(language: String) -> String {
        """
        Você resume transcrições automáticas de vídeos. Regras obrigatórias:
        - Use exclusivamente informações presentes na transcrição. Não invente fatos, nomes, números, decisões ou conclusões.
        - Se algo não foi dito explicitamente, não inclua. Listas sem conteúdo correspondente devem ficar vazias.
        - "Decisões" são apenas decisões ou conclusões declaradas no conteúdo. "Ações" são apenas tarefas ou próximos passos mencionados.
        - A transcrição pode conter erros de reconhecimento; não tente adivinhar o que foi dito além do razoável.
        - Escreva em \(language), de forma clara e objetiva, sem introduções como "O vídeo fala sobre".
        """
    }
}

/// Splits a transcript into windows that fit a model's context, keeping timestamps.
enum TranscriptChunker {
    struct Chunk: Sendable, Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    static func chunks(_ segments: [TranscriptSegment], maxCharacters: Int) -> [Chunk] {
        var result: [Chunk] = []
        var current: [String] = []
        var size = 0
        var start: Double?
        var end: Double = 0

        for segment in segments {
            let line = "[\(TimeFormat.clock(segment.start))] \(segment.text)"
            if size + line.count > maxCharacters, !current.isEmpty {
                result.append(Chunk(start: start ?? 0, end: end, text: current.joined(separator: "\n")))
                current = []; size = 0; start = nil
            }
            if start == nil { start = segment.start }
            current.append(line)
            size += line.count + 1
            end = segment.end
        }
        if !current.isEmpty {
            result.append(Chunk(start: start ?? 0, end: end, text: current.joined(separator: "\n")))
        }
        return result
    }

    static func fullText(_ segments: [TranscriptSegment]) -> String {
        segments.map { "[\(TimeFormat.clock($0.start))] \($0.text)" }.joined(separator: "\n")
    }
}
