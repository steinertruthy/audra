import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case transcriptText, transcriptMarkdown, transcriptSRT, summaryMarkdown, summaryPDF
    var id: String { rawValue }

    var label: String {
        switch self {
        case .transcriptText: tr("Transcrição (TXT)")
        case .transcriptMarkdown: tr("Transcrição (Markdown)")
        case .transcriptSRT: tr("Legendas (SRT)")
        case .summaryMarkdown: tr("Resumo (Markdown)")
        case .summaryPDF: tr("Resumo (PDF)")
        }
    }

    var fileExtension: String {
        switch self {
        case .transcriptText: "txt"
        case .transcriptMarkdown, .summaryMarkdown: "md"
        case .transcriptSRT: "srt"
        case .summaryPDF: "pdf"
        }
    }

    var contentType: UTType {
        switch self {
        case .transcriptText: .plainText
        case .transcriptMarkdown, .summaryMarkdown: UTType(filenameExtension: "md") ?? .plainText
        case .transcriptSRT: UTType(filenameExtension: "srt") ?? .plainText
        case .summaryPDF: .pdf
        }
    }

    var needsSummary: Bool { self == .summaryMarkdown || self == .summaryPDF }

    var suffix: String { needsSummary ? tr(" — Resumo") : "" }
}

/// Pure text renderers for every export format. Kept free of UI so they are testable.
enum TranscriptRenderer {
    static func plainText(title: String, segments: [TranscriptSegment]) -> String {
        var out = "\(title)\n\n"
        for s in segments { out += tr("[%@] %@\n", TimeFormat.full(s.start), s.text) }
        return out
    }

    static func markdown(title: String, meta: String, segments: [TranscriptSegment]) -> String {
        var out = tr("# %@\n\n_%@_\n\n## Transcrição\n\n", title, meta)
        for s in segments {
            let speaker = s.speaker.map { "**\($0):** " } ?? ""
            out += tr("**[%@]** %@%@\n\n", TimeFormat.clock(s.start), speaker, s.text)
        }
        return out
    }

    static func srt(segments: [TranscriptSegment]) -> String {
        var out = ""
        for (i, s) in segments.enumerated() {
            let end = max(s.end, s.start + 0.5)
            out += tr("%@\n%@ --> %@\n%@\n\n", i + 1, TimeFormat.srt(s.start), TimeFormat.srt(end), s.text)
        }
        return out
    }

    static func summaryMarkdown(title: String, meta: String, summary: VideoSummary) -> String {
        var out = tr("# %@\n\n_%@_\n\n## Visão geral\n\n%@\n\n", title, meta, summary.overview)
        func section(_ name: String, _ items: [String], empty: String? = nil) {
            if items.isEmpty {
                if let empty { out += tr("## %@\n\n_%@_\n\n", name, empty) }
                return
            }
            out += tr("## %@\n\n", name) + items.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !summary.chapters.isEmpty {
            out += tr("## Capítulos\n\n") + summary.chapters.map { "- **\(TimeFormat.clock($0.start))** \($0.title)" }.joined(separator: "\n") + "\n\n"
        }
        section(tr("Principais tópicos"), summary.topics)
        section(tr("Pontos importantes"), summary.keyPoints)
        section(tr("Decisões e conclusões"), summary.decisions, empty: tr("Nenhuma decisão identificada no conteúdo."))
        section(tr("Ações e próximos passos"), summary.actionItems, empty: tr("Nenhuma ação mencionada no conteúdo."))
        out += "---\n\n_\(disclaimer(summary))_\n"
        return out
    }

    static func disclaimer(_ summary: VideoSummary) -> String {
        tr("Resumo gerado automaticamente por IA (%@) a partir da transcrição. Não é uma citação literal do vídeo; confira informações importantes no original.", summary.provider)
    }
}

@MainActor
enum Exporter {
    static func export(_ format: ExportFormat, recording: Recording, segments: [TranscriptSegment], summary: VideoSummary?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(recording.title)\(format.suffix).\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let meta = metadata(recording)
            switch format {
            case .transcriptText:
                try TranscriptRenderer.plainText(title: recording.title, segments: segments).write(to: url, atomically: true, encoding: .utf8)
            case .transcriptMarkdown:
                try TranscriptRenderer.markdown(title: recording.title, meta: meta, segments: segments).write(to: url, atomically: true, encoding: .utf8)
            case .transcriptSRT:
                try TranscriptRenderer.srt(segments: segments).write(to: url, atomically: true, encoding: .utf8)
            case .summaryMarkdown:
                guard let summary else { return }
                try TranscriptRenderer.summaryMarkdown(title: recording.title, meta: meta, summary: summary).write(to: url, atomically: true, encoding: .utf8)
            case .summaryPDF:
                guard let summary else { return }
                try PDFRenderer.render(title: recording.title, meta: meta, summary: summary, to: url)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = tr("Não foi possível exportar")
            alert.runModal()
        }
    }

    static func metadata(_ recording: Recording) -> String {
        var parts = [TimeFormat.clock(recording.duration)]
        if let id = recording.localeIdentifier { parts.append(LanguageNames.name(for: id)) }
        parts.append(recording.createdAt.formatted(
            .dateTime.day().month(.wide).year().hour().minute().locale(Localization.shared.locale)))
        return parts.joined(separator: " · ")
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
