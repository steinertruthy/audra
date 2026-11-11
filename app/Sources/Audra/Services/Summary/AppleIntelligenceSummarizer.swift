import Foundation
import FoundationModels

@Generable
struct SectionNotes {
    @Guide(description: "Título curto e descritivo para este trecho, com no máximo 8 palavras")
    var title: String
    @Guide(description: "Síntese fiel do trecho em 2 a 4 frases")
    var summary: String
    @Guide(description: "Assuntos discutidos no trecho")
    var topics: [String]
    @Guide(description: "Informações que merecem destaque: fatos, números, nomes, argumentos")
    var keyPoints: [String]
    @Guide(description: "Decisões ou conclusões declaradas explicitamente. Vazio se não houver")
    var decisions: [String]
    @Guide(description: "Tarefas, encaminhamentos ou próximos passos mencionados. Vazio se não houver")
    var actionItems: [String]
}

@Generable
struct CombinedSummary {
    @Guide(description: "Visão geral clara do assunto abordado no vídeo inteiro")
    var overview: String
    @Guide(description: "Principais tópicos discutidos, sem repetição")
    var topics: [String]
    @Guide(description: "Pontos importantes que merecem destaque")
    var keyPoints: [String]
    @Guide(description: "Decisões e conclusões identificadas. Vazio se não houver")
    var decisions: [String]
    @Guide(description: "Ações e próximos passos mencionados. Vazio se não houver")
    var actionItems: [String]
}

/// On-device summarization with Apple's Foundation Models (Apple Intelligence).
/// The ~4K-token context is handled with a map-reduce pass: each transcript window is condensed
/// into structured notes (which also become chapters), then the notes are merged.
struct AppleIntelligenceSummarizer: Summarizer {
    var displayName: String { tr("Apple Intelligence (no dispositivo)") }

    private static let chunkCharacters = 5_000
    private static let mergeCharacters = 6_000

    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return tr("Este Mac não é compatível com o Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled): return tr("Ative o Apple Intelligence em Ajustes do Sistema para gerar resumos no dispositivo.")
        case .unavailable(.modelNotReady): return tr("O modelo do Apple Intelligence ainda está sendo baixado. Tente novamente em alguns minutos.")
        case .unavailable: return tr("O Apple Intelligence não está disponível no momento.")
        }
    }

    private var model: SystemLanguageModel {
        SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    }

    func summarize(_ request: SummaryRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> VideoSummary {
        if let message = Self.availabilityMessage { throw SummaryError.modelUnavailable(message) }
        guard !request.segments.isEmpty else { throw SummaryError.emptyTranscript }
        let locale = Locale(identifier: request.localeIdentifier)
        guard model.supportsLocale(locale) else { throw SummaryError.unsupportedLanguage(request.languageName) }

        let chunks = TranscriptChunker.chunks(request.segments, maxCharacters: Self.chunkCharacters)
        let totalSteps = Double(chunks.count + 1)
        var sections: [(start: Double, notes: SectionNotes)] = []

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let notes = try await notesWithSplitting(for: chunk.text, request: request, position: (index + 1, chunks.count))
            sections.append((chunk.start, notes))
            progress(Double(index + 1) / totalSteps)
        }

        let combined = try await merge(sections.map(\.notes), request: request)
        progress(1)

        let chapters = sections.count > 1
            ? sections.map { SummaryChapter(start: $0.start, title: $0.notes.title) }
            : []

        return VideoSummary(
            overview: combined.overview.trimmingCharacters(in: .whitespacesAndNewlines),
            topics: clean(combined.topics),
            keyPoints: clean(combined.keyPoints),
            decisions: clean(combined.decisions),
            actionItems: clean(combined.actionItems),
            chapters: chapters,
            provider: displayName,
            detail: request.detail
        )
    }

    // MARK: - Map

    private func notesWithSplitting(for text: String, request: SummaryRequest, position: (Int, Int)) async throws -> SectionNotes {
        do {
            return try await notes(for: text, request: request, position: position)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Dense speech can exceed the estimate; halve the window and merge.
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            guard lines.count > 1 else { throw SummaryError.modelUnavailable(tr("Trecho longo demais para o modelo no dispositivo.")) }
            let mid = lines.count / 2
            let a = try await notesWithSplitting(for: lines[..<mid].joined(separator: "\n"), request: request, position: position)
            let b = try await notesWithSplitting(for: lines[mid...].joined(separator: "\n"), request: request, position: position)
            return SectionNotes(title: a.title, summary: a.summary + " " + b.summary,
                                topics: a.topics + b.topics, keyPoints: a.keyPoints + b.keyPoints,
                                decisions: a.decisions + b.decisions, actionItems: a.actionItems + b.actionItems)
        } catch let error as LanguageModelSession.GenerationError {
            throw map(error, request: request)
        }
    }

    private func notes(for text: String, request: SummaryRequest, position: (Int, Int)) async throws -> SectionNotes {
        let session = LanguageModelSession(model: model, instructions: SummaryPrompts.faithfulnessRules(language: request.languageName))
        let prompt = """
        Trecho \(position.0) de \(position.1) da transcrição do vídeo "\(request.title)".
        Extraia notas estruturadas apenas deste trecho. \(request.detail.guidance)

        TRANSCRIÇÃO:
        \(text)
        """
        let response = try await session.respond(to: prompt, generating: SectionNotes.self,
                                                 options: GenerationOptions(temperature: 0.2))
        return response.content
    }

    // MARK: - Reduce

    private func merge(_ sections: [SectionNotes], request: SummaryRequest) async throws -> CombinedSummary {
        var notesText = sections.enumerated().map { describe($1, index: $0 + 1) }

        // Hierarchical reduction when the notes alone exceed the context window.
        while notesText.joined(separator: "\n\n").count > Self.mergeCharacters, notesText.count > 1 {
            var reduced: [String] = []
            var group: [String] = []
            for note in notesText {
                if (group + [note]).joined(separator: "\n\n").count > Self.mergeCharacters, !group.isEmpty {
                    reduced.append(describe(try await condense(group, request: request), index: reduced.count + 1))
                    group = []
                }
                group.append(note)
            }
            if !group.isEmpty { reduced.append(describe(try await condense(group, request: request), index: reduced.count + 1)) }
            if reduced.count >= notesText.count { break }
            notesText = reduced
        }

        let session = LanguageModelSession(model: model, instructions: SummaryPrompts.faithfulnessRules(language: request.languageName))
        let prompt = """
        A seguir estão notas extraídas, em ordem, de todos os trechos do vídeo "\(request.title)".
        Produza o resumo final do vídeo inteiro, consolidando itens repetidos. \(request.detail.guidance)

        NOTAS:
        \(notesText.joined(separator: "\n\n"))
        """
        do {
            return try await session.respond(to: prompt, generating: CombinedSummary.self,
                                             options: GenerationOptions(temperature: 0.2)).content
        } catch let error as LanguageModelSession.GenerationError {
            throw map(error, request: request)
        }
    }

    private func condense(_ notes: [String], request: SummaryRequest) async throws -> SectionNotes {
        let session = LanguageModelSession(model: model, instructions: SummaryPrompts.faithfulnessRules(language: request.languageName))
        let prompt = "Consolide estas notas consecutivas em um único conjunto de notas, sem perder decisões nem ações.\n\n" + notes.joined(separator: "\n\n")
        return try await session.respond(to: prompt, generating: SectionNotes.self,
                                         options: GenerationOptions(temperature: 0.2)).content
    }

    private func describe(_ notes: SectionNotes, index: Int) -> String {
        func list(_ name: String, _ items: [String]) -> String {
            items.isEmpty ? "" : "\n\(name): " + items.joined(separator: "; ")
        }
        return "Parte \(index) — \(notes.title)\nSíntese: \(notes.summary)"
            + list("Tópicos", notes.topics) + list("Destaques", notes.keyPoints)
            + list("Decisões", notes.decisions) + list("Ações", notes.actionItems)
    }

    private func clean(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private func map(_ error: LanguageModelSession.GenerationError, request: SummaryRequest) -> Error {
        switch error {
        case .unsupportedLanguageOrLocale: SummaryError.unsupportedLanguage(request.languageName)
        case .guardrailViolation: SummaryError.refused
        case .assetsUnavailable: SummaryError.modelUnavailable("O modelo do Apple Intelligence não está disponível no momento.")
        default: error
        }
    }
}
