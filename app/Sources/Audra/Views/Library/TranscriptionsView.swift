import SwiftData
import SwiftUI

/// All transcriptions, grouped by state and date, filtered by the top-bar search.
struct TranscriptionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TranscriptionList(search: model.search.trimmingCharacters(in: .whitespaces))
    }
}

private struct TranscriptionList: View {
    @Environment(AppModel.self) private var model
    @Query private var recordings: [Recording]
    let search: String

    init(search: String) {
        self.search = search
        let term = search
        _recordings = Query(
            filter: #Predicate<Recording> { recording in
                term.isEmpty
                    || recording.title.localizedStandardContains(term)
                    || recording.transcriptText.localizedStandardContains(term)
            },
            sort: [SortDescriptor(\Recording.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageTitle(title: search.isEmpty ? tr("Transcrições") : tr("Resultados para “%@”", search),
                          subtitle: subtitle) {
                    Button { model.presentImporter() } label: { Label(tr("Transcrever"), systemImage: "waveform.badge.plus") }
                        .buttonStyle(AudraButtonStyle(kind: .secondary))
                }

                if recordings.isEmpty {
                    EmptyStateView(symbol: search.isEmpty ? "waveform" : "magnifyingglass",
                                   title: search.isEmpty ? tr("Nenhuma transcrição ainda") : tr("Nada encontrado"),
                                   message: search.isEmpty
                                    ? tr("Arraste vídeos para a janela ou escolha arquivos. A transcrição e o resumo são feitos no seu Mac.")
                                    : tr("Nenhum título ou trecho falado contém “%@”.", search)) {
                        if search.isEmpty {
                            Button(tr("Escolher Vídeos…")) { model.presentImporter() }
                                .buttonStyle(AudraButtonStyle(kind: .primary, large: true))
                        }
                    }
                    .frame(height: 360)
                } else {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(group.title).padding(.leading, 12)
                            VStack(spacing: 0) {
                                ForEach(group.items) { recording in
                                    TranscriptionRow(recording: recording, search: search)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .animation(Motion.smooth, value: recordings.map(\.id))
    }

    private var subtitle: String {
        let count = recordings.count
        return count == 1 ? tr("1 arquivo") : tr("%@ arquivos", count)
    }

    private var groups: [(title: String, items: [Recording])] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now)!
        let active = recordings.filter { $0.status.isActive }
        let rest = recordings.filter { !$0.status.isActive }
        let today = rest.filter { calendar.isDateInToday($0.createdAt) }
        let week = rest.filter { !calendar.isDateInToday($0.createdAt) && $0.createdAt > weekAgo }
        let older = rest.filter { $0.createdAt <= weekAgo }
        return [(tr("Em processamento"), active), (tr("Hoje"), today), (tr("Últimos 7 dias"), week), (tr("Anteriores"), older)]
            .filter { !$0.1.isEmpty }
    }
}

private struct TranscriptionRow: View {
    @Environment(AppModel.self) private var model
    let recording: Recording
    let search: String
    @State private var hovering = false

    var body: some View {
        Button { model.selection = .recording(recording.id) } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.control.opacity(0.8))
                    Image(systemName: recording.hasVideo ? "play.rectangle" : "waveform")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(recording.status == .completed ? Theme.accentBright : Theme.textTertiary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !search.isEmpty, let snippet {
                        Text(snippet).font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    } else {
                        Text(meta).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if recording.status != .completed {
                    StatusChip(status: recording.status, progress: model.processing.job(for: recording.id)?.overallProgress)
                }
                if hovering, recording.status == .completed {
                    Button { model.editInNewProject(recording) } label: {
                        Label(tr("Editar"), systemImage: "scissors")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(AudraButtonStyle(kind: .secondary))
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .help(tr("Abrir no editor"))
                }
                Text(recording.createdAt.formatted(.relative(presentation: .named).locale(Localization.shared.locale)))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(width: 92, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Theme.elevated : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .contextMenu {
            if recording.status.isActive {
                Button(tr("Cancelar Processamento")) { model.processing.cancel(recording.id) }
            } else {
                if recording.status == .completed {
                    Button(tr("Editar em Novo Projeto")) { model.editInNewProject(recording) }
                    Divider()
                }
                Button(tr("Transcrever Novamente")) { model.reprocess(recording) }
                if recording.segmentCount > 0 {
                    Button(tr("Gerar Resumo Novamente")) { model.regenerateSummary(recording) }
                }
            }
            Divider()
            Button(tr("Mostrar no Finder")) { model.revealInFinder(recording) }
                .disabled(!recording.sourceExists)
            Divider()
            Button(tr("Remover da Biblioteca…"), role: .destructive) { model.confirmDelete(recording) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(recording.status.label)
    }

    private var meta: String {
        var parts: [String] = []
        if recording.duration > 0 { parts.append(TimeFormat.clock(recording.duration)) }
        if let id = recording.localeIdentifier { parts.append(LanguageNames.name(for: id)) }
        if recording.segmentCount > 0 { parts.append(tr("%@ trechos", recording.segmentCount)) }
        if recording.summaryData != nil { parts.append(tr("com resumo")) }
        if recording.status == .failed { parts.append(recording.errorMessage ?? tr("Falhou")) }
        return parts.isEmpty ? recording.fileExtension : parts.joined(separator: " · ")
    }

    /// Excerpt around the first match, with the match highlighted.
    private var snippet: AttributedString? {
        let text = recording.transcriptText
        guard let range = text.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let lower = text.index(range.lowerBound, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 90, limitedBy: text.endIndex) ?? text.endIndex
        var result = AttributedString((lower > text.startIndex ? "…" : "") + text[lower..<range.lowerBound])
        var match = AttributedString(text[range])
        match.foregroundColor = Theme.accentBright
        match.font = .system(size: 12, weight: .semibold)
        result += match
        result += AttributedString(text[range.upperBound..<upper] + (upper < text.endIndex ? "…" : ""))
        return result
    }
}
