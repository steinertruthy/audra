import SwiftData
import SwiftUI

struct EditorSidebar: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            PillTabs(selection: $session.leftTab,
                     items: EditorLeftTab.allCases.map { .init(value: $0, title: $0.title, symbol: $0.symbol) },
                     compact: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ZStack {
                switch session.leftTab {
                case .media: MediaTab(session: session).transition(.opacity)
                case .transcript: TranscriptPanel(session: session).transition(.opacity)
                case .text: TextTab(session: session).transition(.opacity)
                case .tools: ToolsTab(session: session).transition(.opacity)
                case .ai: AITab(session: session).transition(.opacity)
                }
            }
            .animation(Motion.fade, value: session.leftTab)
            .frame(maxHeight: .infinity)
        }
        .background(Theme.panel)
    }
}

/// Small section header used inside panels.
struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            SectionLabel(title)
            Spacer()
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

// MARK: - Media

private struct MediaTab: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: EditorSession
    @Query(filter: #Predicate<Recording> { $0.statusRaw == "completed" }, sort: \Recording.createdAt, order: .reverse)
    private var recordings: [Recording]
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: tr("Mídias do projeto")) {
                    Button { session.presentImporter() } label: { Image(systemName: "plus") }
                        .iconButton(size: 24)
                        .help(tr("Adicionar mídia"))
                }
                if session.isImporting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(tr("Importando…")).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
                if session.project.media.isEmpty {
                    dropHint
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 10) {
                        ForEach(session.project.media) { item in
                            MediaCard(session: session, item: item)
                        }
                    }
                    .padding(.horizontal, 12)
                }

                let available = recordings.filter { rec in !session.project.media.contains { $0.path == rec.sourcePath } && rec.sourceExists }
                if !available.isEmpty {
                    PanelHeader(title: tr("Da biblioteca de transcrições")) { EmptyView() }
                        .padding(.top, 10)
                    VStack(spacing: 2) {
                        ForEach(available.prefix(12)) { recording in
                            Button {
                                session.importMedia([recording.sourceURL], placeOnTimeline: false)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: recording.hasVideo ? "film" : "waveform")
                                        .foregroundStyle(Theme.accentBright)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(recording.title).font(.system(size: 12)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                        Text(tr("%@ · transcrito", TimeFormat.clock(recording.duration)))
                                            .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(Theme.textTertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .hoverHighlight()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(tr("Adicionar ao projeto com a transcrição"))
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(.bottom, 16)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .animation(Motion.fade, value: dropTargeted)
        .animation(Motion.snappy, value: session.project.media.count)
        .dropDestination(for: URL.self) { urls, _ in
            session.importMedia(urls, placeOnTimeline: false)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }

    private var dropHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.accentBright)
            Text(tr("Arraste vídeos, músicas e áudios para cá"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button(tr("Escolher Arquivos…")) { session.presentImporter() }
                .buttonStyle(AudraButtonStyle(kind: .primary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .padding(.horizontal, 12)
    }
}

private struct MediaCard: View {
    let session: EditorSession
    let item: MediaItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.hasVideo ? Theme.videoClip : Theme.audioClip)
                    .overlay {
                        if let poster = MediaCache.shared.poster(for: item) {
                            Image(decorative: poster, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: item.hasVideo ? "film" : "waveform")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(TimeFormat.clock(item.duration))
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(5)
                if hovering {
                    Button { session.addToTimeline(item.id) } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Theme.accentGradient, in: Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
                    .help(tr("Adicionar ao fim da timeline"))
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(hovering ? Theme.accent.opacity(0.7) : Theme.stroke))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    if session.transcripts[item.id] != nil {
                        Image(systemName: "text.quote").help(tr("Transcrição disponível"))
                    }
                    if !item.isAvailable {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).help(tr("Arquivo não encontrado"))
                    }
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(5)
            }
            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .draggable(item.id.uuidString) {
            Label(item.name, systemImage: item.hasVideo ? "film" : "waveform")
                .padding(8)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        }
        .onTapGesture(count: 2) { session.addToTimeline(item.id) }
        .contextMenu {
            Button(tr("Adicionar à Timeline")) { session.addToTimeline(item.id) }
            Button(tr("Adicionar no Cursor")) { session.addToTimeline(item.id, at: session.currentTime) }
            if item.hasAudio, session.transcripts[item.id] == nil {
                Button(tr("Transcrever")) { session.transcribe(item.id) }
            }
            Button(tr("Mostrar no Finder")) { NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL]) }
                .disabled(!item.isAvailable)
            Divider()
            Button(tr("Remover do Projeto"), role: .destructive) { session.removeMedia(item.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(TimeFormat.clock(item.duration))")
        .accessibilityAction(named: Text(tr("Adicionar à timeline"))) { session.addToTimeline(item.id) }
    }
}

// MARK: - Text presets

private struct TextTab: View {
    let session: EditorSession

    private let presets: [(String, String, TextStyle)] = [
        (tr("Título"), tr("Grande e centralizado"), .title()),
        (tr("Texto"), tr("Sobre o vídeo"), .subtitle()),
        (tr("Terço inferior"), tr("Nome e descrição"), .lowerThird()),
        (tr("Legenda"), tr("Faixa inferior com fundo"), .caption(tr("Legenda de exemplo"))),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: tr("Adicionar no cursor")) { EmptyView() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(presets, id: \.0) { preset in
                        TextPresetTile(title: preset.0, subtitle: preset.1, style: preset.2) {
                            session.addText(preset.2)
                        }
                    }
                }
                .padding(.horizontal, 12)

                PanelHeader(title: tr("Legendas automáticas")) { EmptyView() }
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("Cria legendas sincronizadas a partir da transcrição, respeitando os cortes feitos na timeline."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let mediaID = session.transcriptMediaID {
                        Button {
                            session.generateSubtitles(for: mediaID)
                        } label: {
                            Label(tr("Gerar Legendas"), systemImage: "captions.bubble")
                        }
                        .buttonStyle(AudraButtonStyle(kind: .primary))
                    } else {
                        Text(tr("Nenhuma mídia do projeto tem transcrição ainda."))
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        Button(tr("Ver Transcrição")) { session.leftTab = .transcript }
                            .buttonStyle(AudraButtonStyle(kind: .secondary))
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 16)
        }
    }
}

private struct TextPresetTile: View {
    let title: String
    let subtitle: String
    let style: TextStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x2A2140), Color(hex: 0x16121F)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    preview
                }
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(hovering ? Theme.accent : Theme.stroke))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .scaleEffect(hovering ? 1.025 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .help(tr("Adicionar %@ no cursor", title.lowercased()))
    }

    @ViewBuilder
    private var preview: some View {
        let text = Text(style.content.components(separatedBy: "\n").first ?? style.content)
            .font(.system(size: max(9, style.size * 110), weight: style.bold ? .bold : .regular))
            .foregroundStyle(.white)
            .lineLimit(1)
        if style.showBackground {
            text.padding(.horizontal, 6).padding(.vertical, 2)
                .background(style.background.color, in: RoundedRectangle(cornerRadius: 3))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment == .leading ? .bottomLeading : .bottom)
                .padding(8)
        } else {
            text.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Tools

private struct ToolsTab: View {
    @Bindable var session: EditorSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: tr("Edição")) { EmptyView() }
                toolGrid([
                    Tool(title: tr("Dividir"), symbol: "scissors", shortcut: "⌘B") { session.splitAtPlayhead() },
                    Tool(title: tr("Duplicar"), symbol: "plus.square.on.square", shortcut: "⌘D", enabled: !session.selection.isEmpty) { session.duplicateSelection() },
                    Tool(title: tr("Excluir"), symbol: "trash", shortcut: "⌫", enabled: !session.selection.isEmpty) { session.deleteSelection() },
                    Tool(title: tr("Fechar espaço"), symbol: "arrow.left.to.line.compact", shortcut: "⇧⌫", enabled: !session.selection.isEmpty) { session.deleteSelection(ripple: true) },
                    Tool(title: tr("Remover lacuna"), symbol: "rectangle.compress.vertical") { session.perform(tr("Remover lacuna")) { $0.closeGap(at: session.currentTime) } },
                    Tool(title: tr("Marcador"), symbol: "bookmark", shortcut: tr("M")) { session.addMarker() },
                ])

                PanelHeader(title: tr("Áudio")) { EmptyView() }
                toolGrid([
                    Tool(title: tr("Separar áudio"), symbol: "waveform.badge.minus", enabled: session.singleSelectedClip?.mediaID != nil) { session.detachAudio() },
                    Tool(title: tr("Substituir áudio"), symbol: "arrow.triangle.2.circlepath", enabled: session.singleSelectedClip?.mediaID != nil) {
                        if let id = session.singleSelectedClip?.id { session.replaceAudio(of: id) }
                    },
                    Tool(title: tr("Adicionar trilha"), symbol: "music.note") { session.presentImporter() },
                    Tool(title: tr("Remover pausas"), symbol: "waveform.path.badge.minus") { session.removeSilences() },
                ])
                Text(tr("“Remover pausas” corta silêncios com mais de 0,8 s nos clipes selecionados (ou em toda a faixa de vídeo) e fecha os espaços."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)

                PanelHeader(title: tr("Faixas")) { EmptyView() }
                toolGrid([
                    Tool(title: tr("Faixa de vídeo"), symbol: "film") { session.perform(tr("Adicionar faixa")) { $0.addTrack(.video) } },
                    Tool(title: tr("Faixa de áudio"), symbol: "waveform") { session.perform(tr("Adicionar faixa")) { $0.addTrack(.audio) } },
                    Tool(title: tr("Faixa de texto"), symbol: "textformat") { session.perform(tr("Adicionar faixa")) { $0.addTrack(.text) } },
                    Tool(title: session.snapping ? tr("Ímã ligado") : tr("Ímã desligado"), symbol: "arrow.left.and.line.vertical.and.arrow.right", active: session.snapping) { session.snapping.toggle() },
                ])
            }
            .padding(.bottom, 16)
        }
    }

    private struct Tool: Identifiable {
        let title: String
        let symbol: String
        var shortcut: String? = nil
        var enabled = true
        var active = false
        let action: () -> Void
        var id: String { title }
    }

    private func toolGrid(_ tools: [Tool]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
            ForEach(tools) { tool in
                Button(action: tool.action) {
                    VStack(spacing: 6) {
                        Image(systemName: tool.symbol).font(.system(size: 16))
                            .foregroundStyle(tool.active ? Theme.accentBright : Theme.textPrimary)
                        Text(tool.title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if let shortcut = tool.shortcut {
                            Text(shortcut).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textQuaternary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Theme.control.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .hoverHighlight(radius: 10, isSelected: tool.active)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!tool.enabled)
                .opacity(tool.enabled ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - AI

private struct AITab: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: EditorSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let mediaID = session.transcriptMediaID, let transcript = session.transcripts[mediaID] {
                    PanelHeader(title: tr("Resumo")) {
                        if session.transcripts.count > 1 { TranscriptMediaMenu(session: session) }
                    }
                    if let summary = transcript.summary {
                        summaryView(summary, mediaID: mediaID)
                    } else {
                        noSummary(transcript)
                    }
                    PanelHeader(title: tr("Ações inteligentes")) { EmptyView() }
                        .padding(.top, 6)
                    VStack(spacing: 6) {
                        action(tr("Gerar legendas da transcrição"), "captions.bubble") { session.generateSubtitles(for: mediaID) }
                        action(tr("Capítulos como marcadores"), "bookmark", enabled: transcript.summary?.chapters.isEmpty == false) {
                            session.addChapterMarkers(for: mediaID)
                        }
                        action(tr("Remover pausas longas"), "waveform.path.badge.minus") { session.removeSilences() }
                        action(tr("Editar pelo texto"), "text.quote") { session.leftTab = .transcript }
                    }
                    .padding(.horizontal, 12)
                } else {
                    EmptyStateView(symbol: "sparkles", title: tr("Recursos de IA"),
                                   message: tr("Transcreva um vídeo do projeto para gerar resumo, capítulos, legendas automáticas e editar pelo texto.")) {
                        Button(tr("Abrir Transcrição")) { session.leftTab = .transcript }
                            .buttonStyle(AudraButtonStyle(kind: .primary))
                    }
                    .padding(.top, 30)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func summaryView(_ summary: VideoSummary, mediaID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("Gerado por IA a partir da transcrição"), systemImage: "sparkles")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.accentBright)
            Text(summary.overview)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !summary.chapters.isEmpty {
                SectionLabel(tr("Capítulos"))
                VStack(spacing: 2) {
                    ForEach(summary.chapters) { chapter in
                        let t = session.project.timelineTime(forSource: chapter.start, media: mediaID)
                        Button {
                            if let t { session.seek(to: t); session.revealInTimeline(t) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(t.map { TimeFormat.clock($0) } ?? tr("cortado"))
                                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(t == nil ? Theme.textQuaternary : Theme.accentBright)
                                    .frame(width: 46, alignment: .leading)
                                Text(chapter.title)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(t == nil ? Theme.textTertiary : Theme.textPrimary)
                                    .strikethrough(t == nil)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .hoverHighlight(radius: 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(t == nil)
                    }
                }
            }
            if !summary.keyPoints.isEmpty {
                SectionLabel(tr("Pontos importantes"))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Circle().fill(Theme.accent).frame(width: 4, height: 4).offset(y: -2)
                            Text(point).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !summary.actionItems.isEmpty {
                SectionLabel(tr("Próximos passos"))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                        Label(item, systemImage: "circle").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func noSummary(_ transcript: MediaTranscript) -> some View {
        let job = app.processing.job(for: transcript.recordingID)
        VStack(alignment: .leading, spacing: 8) {
            if let job, job.stage == .summarizing || job.stage == .queued {
                HStack(spacing: 8) { PulseBars(); Text(tr("Gerando resumo…")).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary) }
                AudraProgressBar(value: job.stageProgress)
            } else {
                Text(app.recording(transcript.recordingID)?.summaryError ?? tr("Ainda não há resumo para esta transcrição."))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Gerar Resumo")) {
                    if let recording = app.recording(transcript.recordingID) { app.regenerateSummary(recording) }
                }
                .buttonStyle(AudraButtonStyle(kind: .primary))
            }
        }
        .padding(.horizontal, 14)
        .onChange(of: app.processing.job(for: transcript.recordingID) == nil) { _, finished in
            if finished { session.refreshTranscripts() }
        }
    }

    private func action(_ title: String, _ symbol: String, enabled: Bool = true, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                    .frame(width: 26, height: 26)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 7))
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textQuaternary)
            }
            .padding(7)
            .hoverHighlight(radius: 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Picker for which media's transcript is shown.
struct TranscriptMediaMenu: View {
    let session: EditorSession

    var body: some View {
        Menu {
            ForEach(session.project.media.filter { session.transcripts[$0.id] != nil }) { item in
                Button(item.name) { session.chooseTranscriptMedia(item.id) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(session.transcriptMediaID.flatMap { session.project.mediaItem($0)?.name } ?? tr("Mídia"))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
