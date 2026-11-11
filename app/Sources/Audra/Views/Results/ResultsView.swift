import AVKit
import SwiftUI

/// Decoded, editable view of a finished recording. Decoding happens once per selection.
@MainActor
@Observable
final class TranscriptDocument {
    let recording: Recording
    var segments: [TranscriptSegment]
    var summary: VideoSummary?
    private var startTimes: [Double]

    init(recording: Recording) {
        self.recording = recording
        let segments = recording.decodeSegments()
        self.segments = segments
        self.startTimes = segments.map(\.start)
        self.summary = recording.decodeSummary()
    }

    func reloadSummary() { summary = recording.decodeSummary() }

    /// Binary search for the block being spoken at `time`.
    func activeSegmentID(at time: Double) -> UUID? {
        guard !segments.isEmpty else { return nil }
        var low = 0, high = startTimes.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if startTimes[mid] <= time + 0.05 { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard found >= 0 else { return nil }
        let segment = segments[found]
        // Between blocks (silence) keep the previous one lit for a short grace period.
        return time <= segment.end + 1.5 ? segment.id : nil
    }

    func update(_ id: UUID, text: String) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != segments[index].text else { return }
        segments[index].text = trimmed
        segments[index].edited = true
        recording.store(segments: segments)
        try? recording.modelContext?.save()
    }

    var plainText: String { TranscriptRenderer.plainText(title: recording.title, segments: segments) }
}

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    let recording: Recording
    @State private var document: TranscriptDocument
    @State private var player: PlayerController

    init(recording: Recording) {
        self.recording = recording
        _document = State(initialValue: TranscriptDocument(recording: recording))
        _player = State(initialValue: PlayerController(url: recording.mediaURL))
    }

    var body: some View {
        @Bindable var model = model
        content
            .onAppear { model.player = player }
            .onDisappear {
                if model.player === player { model.player = nil }
                player.invalidate()
            }
            .onChange(of: recording.summaryData) { document.reloadSummary() }
    }

    private var content: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            RecordingHeader(recording: recording) {
                LanguageMenu(recording: recording)
                PillTabs(selection: $model.resultMode,
                         items: ResultMode.allCases.map { .init(value: $0, title: $0.label) })
                    .help(tr("Alternar visualização (⌘1, ⌘2, ⌘3)"))
                    .padding(.trailing, 6)
                copyMenu
                exportMenu
                Button { model.editInNewProject(recording) } label: {
                    Label(tr("Editar vídeo"), systemImage: "scissors")
                }
                .buttonStyle(AudraButtonStyle(kind: .primary))
                .help(tr("Abrir no editor com a transcrição integrada"))
                .disabled(!recording.sourceExists)
            }
            ZStack { layout }
                .background(Theme.panel)
                .animation(Motion.smooth, value: model.resultMode)
        }
    }

    @ViewBuilder
    private var layout: some View {
        switch model.resultMode {
        case .full:
            HSplitView {
                VStack(spacing: 0) {
                    PlayerPane(player: player, hasVideo: recording.hasVideo, sourceMissing: !FileManager.default.fileExists(atPath: recording.mediaURL.path))
                        .frame(minHeight: 200, idealHeight: 300, maxHeight: 420)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    SummaryView(document: document, player: player, compact: true)
                }
                .frame(minWidth: 380, idealWidth: 520)
                TranscriptView(document: document, player: player)
                    .frame(minWidth: 360, idealWidth: 560)
            }
        case .transcript:
            VSplitView {
                PlayerPane(player: player, hasVideo: recording.hasVideo, sourceMissing: !FileManager.default.fileExists(atPath: recording.mediaURL.path))
                    .frame(minHeight: 160, idealHeight: 260, maxHeight: 480)
                TranscriptView(document: document, player: player)
                    .frame(minHeight: 240)
            }
        case .summary:
            SummaryView(document: document, player: player, compact: false)
        }
    }

    private var copyMenu: some View {
        Menu {
            Button(tr("Copiar Transcrição")) { Exporter.copy(document.plainText) }
            Button(tr("Copiar Transcrição sem Timestamps")) {
                Exporter.copy(document.segments.map(\.text).joined(separator: "\n"))
            }
            Button(tr("Copiar Resumo (Markdown)")) {
                if let summary = document.summary {
                    Exporter.copy(TranscriptRenderer.summaryMarkdown(title: recording.title, meta: Exporter.metadata(recording), summary: summary))
                }
            }
            .disabled(document.summary == nil)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 30)
        .help(tr("Copiar conteúdo"))
    }

    private var exportMenu: some View {
        Menu {
            Section(tr("Transcrição")) {
                ForEach([ExportFormat.transcriptText, .transcriptMarkdown, .transcriptSRT]) { format in
                    Button(format.label) { export(format) }
                }
            }
            Section(tr("Resumo")) {
                ForEach([ExportFormat.summaryMarkdown, .summaryPDF]) { format in
                    Button(format.label) { export(format) }.disabled(document.summary == nil)
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 30)
        .help(tr("Exportar transcrição ou resumo"))
    }

    private func export(_ format: ExportFormat) {
        Exporter.export(format, recording: recording, segments: document.segments, summary: document.summary)
    }
}

/// Native AVKit player; falls back to a clear message when the media is gone.
struct PlayerPane: View {
    let player: PlayerController
    let hasVideo: Bool
    let sourceMissing: Bool

    var body: some View {
        ZStack {
            Theme.canvas
            if sourceMissing {
                ContentUnavailableView(tr("Vídeo indisponível"), systemImage: "film.stack",
                                       description: Text(tr("O arquivo original foi movido ou excluído. A transcrição continua disponível.")))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                AVPlayerViewRepresentable(player: player.player)
                if !hasVideo {
                    Image(systemName: "waveform")
                        .font(.system(size: 54, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.35))
                        .allowsHitTesting(false)
                        .offset(y: -18)
                }
            }
        }
    }
}

private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
