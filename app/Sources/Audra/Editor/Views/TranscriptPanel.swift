import AppKit
import SwiftUI

/// Transcript inside the editor: follows playback word by word, seeks on click, and edits the video
/// through the text (select words → remove, mute, caption or find them in the timeline).
struct TranscriptPanel: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: EditorSession
    @State private var follow = true
    @State private var query = ""

    var body: some View {
        if let mediaID = session.transcriptMediaID, let transcript = session.transcripts[mediaID] {
            content(mediaID: mediaID, transcript: transcript)
        } else {
            emptyState
        }
    }

    // MARK: Content

    private func content(mediaID: UUID, transcript: MediaTranscript) -> some View {
        let sourceTime = session.project.sourceTime(atTimeline: session.currentTime, media: mediaID)
        let activeWord = sourceTime.flatMap { transcript.wordIndex(at: $0) }
        let editKey = editVersion(for: mediaID)
        let selection = session.transcriptSelection?.mediaID == mediaID ? session.transcriptSelection : nil

        return VStack(spacing: 0) {
            header(mediaID: mediaID, transcript: transcript)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(transcript.segments.enumerated()), id: \.element.id) { index, segment in
                            let first = transcript.segmentStarts[index]
                            let count = (index + 1 < transcript.segmentStarts.count ? transcript.segmentStarts[index + 1] : transcript.words.count) - first
                            ParagraphView(
                                session: session,
                                mediaID: mediaID,
                                words: Array(transcript.words[first..<(first + count)]),
                                firstIndex: first,
                                activeWord: activeWord.flatMap { $0 >= first && $0 < first + count ? $0 : nil },
                                selection: selection.flatMap { $0.upper >= first && $0.lower < first + count ? ($0.lower...$0.upper) : nil },
                                editKey: editKey,
                                query: query.count >= 2 ? query : ""
                            )
                            .equatable()
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .padding(.bottom, selection == nil ? 0 : 90)
                }
                .onScrollPhaseChange { _, phase in if phase == .interacting { follow = false } }
                .onChange(of: activeWord) { _, word in
                    guard follow, session.isPlaying, let word, let segment = segmentIndex(of: word, in: transcript) else { return }
                    withAnimation(Motion.smooth) { proxy.scrollTo(segment, anchor: UnitPoint(x: 0, y: 0.3)) }
                }
                .onChange(of: query) { _, q in
                    guard q.count >= 2, let index = transcript.segments.firstIndex(where: { $0.text.matches(q) }) else { return }
                    follow = false
                    withAnimation(Motion.smooth) { proxy.scrollTo(index, anchor: .top) }
                }
            }
            .overlay(alignment: .bottom) {
                if let selection {
                    SelectionBar(session: session, transcript: transcript, selection: selection)
                        .padding(10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.snappy, value: selection)
        }
    }

    private func header(mediaID: UUID, transcript: MediaTranscript) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if session.transcripts.count > 1 {
                    TranscriptMediaMenu(session: session)
                } else {
                    Text(transcript.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Button { follow.toggle() } label: {
                    Image(systemName: follow ? "dot.radiowaves.left.and.right" : "arrow.down.to.line")
                }
                .iconButton(follow, size: 24)
                .help(follow ? tr("Acompanhando a reprodução") : tr("Acompanhar a reprodução"))
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                TextField(tr("Buscar na transcrição"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 7))
            Text(transcript.hasWordTiming
                 ? tr("Clique para ir ao momento · ⇧-clique seleciona um trecho · clique duplo seleciona a frase")
                 : tr("Tempo por palavra estimado (transcrição antiga). Os cortes são ajustados pelo áudio."))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private func segmentIndex(of word: Int, in transcript: MediaTranscript) -> Int? {
        var low = 0, high = transcript.segmentStarts.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if transcript.segmentStarts[mid] <= word { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }

    /// Changes whenever the clips using this media change, so paragraphs refresh their "removed" marks.
    private func editVersion(for mediaID: UUID) -> Int {
        var hasher = Hasher()
        for clip in session.project.clips(of: mediaID) {
            hasher.combine(clip.start)
            hasher.combine(clip.sourceIn)
            hasher.combine(clip.sourceOut)
            hasher.combine(clip.speed)
            hasher.combine(clip.audioMuted)
        }
        return hasher.finalize()
    }

    // MARK: Empty / transcribing

    @ViewBuilder
    private var emptyState: some View {
        let candidates = session.project.media.filter(\.hasAudio)
        if candidates.isEmpty {
            EmptyStateView(symbol: "text.quote", title: tr("Sem transcrição"),
                           message: tr("Adicione um vídeo ou áudio ao projeto para transcrevê-lo e editar pelo texto.")) {
                Button(tr("Adicionar Mídia…")) { session.presentImporter() }
                    .buttonStyle(AudraButtonStyle(kind: .primary))
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    EmptyStateView(symbol: "waveform.and.magnifyingglass", title: tr("Transcreva para editar pelo texto"),
                                   message: tr("A transcrição roda no seu Mac. Depois, selecione palavras para cortar trechos, gerar legendas e navegar."))
                        .frame(height: 220)
                    ForEach(candidates) { item in
                        TranscribeRow(session: session, item: item)
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct TranscribeRow: View {
    @Environment(AppModel.self) private var app
    let session: EditorSession
    let item: MediaItem

    var body: some View {
        let recording = item.recordingID.flatMap { app.recording($0) }
        let job = recording.flatMap { app.processing.job(for: $0.id) }
        HStack(spacing: 10) {
            Image(systemName: item.hasVideo ? "film" : "waveform").foregroundStyle(Theme.accentBright).frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if let job {
                    AudraProgressBar(value: job.overallProgress, height: 4)
                    Text("\(job.stage.label) · \(Int(job.overallProgress * 100))%")
                        .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                } else if let recording, recording.status == .failed {
                    Text(recording.errorMessage ?? tr("Falhou")).font(.system(size: 10.5)).foregroundStyle(Theme.warning).lineLimit(2)
                } else {
                    Text(TimeFormat.clock(item.duration)).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            if job == nil {
                Button(tr("Transcrever")) { session.transcribe(item.id) }
                    .buttonStyle(AudraButtonStyle(kind: .primary))
            }
        }
        .padding(10)
        .panelSurface(radius: 10, fill: Theme.elevated, shadow: false)
        .onChange(of: recording?.status) { _, status in
            if status == .completed { session.refreshTranscripts() }
        }
    }
}

// MARK: - Paragraph

private struct ParagraphView: View, Equatable {
    let session: EditorSession
    let mediaID: UUID
    let words: [TranscriptWord]
    let firstIndex: Int
    let activeWord: Int?
    let selection: ClosedRange<Int>?
    let editKey: Int
    let query: String

    static func == (a: ParagraphView, b: ParagraphView) -> Bool {
        a.firstIndex == b.firstIndex && a.words.count == b.words.count && a.activeWord == b.activeWord
            && a.selection == b.selection && a.editKey == b.editKey && a.query == b.query && a.mediaID == b.mediaID
    }

    var body: some View {
        let start = words.first?.start ?? 0
        let timelineStart = session.project.timelineTime(forSource: start + 0.01, media: mediaID)
            ?? words.lazy.compactMap { session.project.timelineTime(forSource: ($0.start + $0.end) / 2, media: mediaID) }.first
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                if let t = timelineStart { session.seek(to: t) }
            } label: {
                Text(timelineStart.map { TimeFormat.clock($0) } ?? "—")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(activeWord != nil ? Theme.accentBright : Theme.textQuaternary)
                    .frame(width: 40, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(timelineStart == nil ? tr("Trecho removido da edição") : tr("Ir para este trecho"))

            FlowLayout(spacing: 0, lineSpacing: 3) {
                ForEach(Array(words.enumerated()), id: \.offset) { offset, word in
                    let index = firstIndex + offset
                    WordView(
                        word: word,
                        isActive: index == activeWord,
                        isSelected: selection?.contains(index) == true,
                        isRemoved: isRemoved(word),
                        isMatch: !query.isEmpty && word.text.matches(query)
                    )
                    .onTapGesture(count: 2) { selectParagraph() }
                    .onTapGesture { tap(index, word) }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(activeWord != nil ? Theme.accent.opacity(0.07) : .clear)
        )
        .animation(Motion.fade, value: activeWord != nil)
        .contextMenu {
            Button(tr("Selecionar Frase")) { selectParagraph() }
            Button(tr("Copiar Frase")) { Exporter.copy(words.map(\.text).joined(separator: " ")) }
        }
    }

    private func isRemoved(_ word: TranscriptWord) -> Bool {
        session.project.coverage(source: word.start, word.end, media: mediaID) < 0.5
    }

    private func tap(_ index: Int, _ word: TranscriptWord) {
        if NSEvent.modifierFlags.contains(.shift) {
            let current = session.transcriptSelection?.mediaID == mediaID ? session.transcriptSelection?.anchor : nil
            let remembered = WordAnchor.last?.0 == mediaID ? WordAnchor.last?.1 : nil
            session.transcriptSelection = TranscriptSelection(mediaID: mediaID, anchor: current ?? remembered ?? index, head: index)
            return
        }
        session.transcriptSelection = nil
        WordAnchor.last = (mediaID, index)
        if let t = session.project.timelineTime(forSource: word.start + 0.005, media: mediaID) {
            session.seek(to: t)
        }
    }

    private func selectParagraph() {
        session.transcriptSelection = TranscriptSelection(mediaID: mediaID, anchor: firstIndex, head: firstIndex + words.count - 1)
    }
}

/// Anchor of the last plain click, shared so a shift-click in another paragraph can extend from it.
@MainActor
enum WordAnchor {
    static var last: (UUID, Int)?
}

private struct WordView: View {
    let word: TranscriptWord
    let isActive: Bool
    let isSelected: Bool
    let isRemoved: Bool
    let isMatch: Bool
    @State private var hovering = false

    var body: some View {
        Text(word.text + " ")
            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
            .foregroundStyle(color)
            .strikethrough(isRemoved, color: Theme.danger.opacity(0.7))
            .padding(.vertical, 1)
            .padding(.horizontal, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(background)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isActive)
            .accessibilityLabel(word.text)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var color: Color {
        if isRemoved { return Theme.textQuaternary }
        if isActive { return .white }
        if isSelected { return Theme.textPrimary }
        return Theme.textPrimary.opacity(0.82)
    }

    private var background: Color {
        if isSelected { return Theme.accent.opacity(0.38) }
        if isActive { return Theme.accent.opacity(0.85) }
        if isMatch { return Theme.highlight.opacity(0.3) }
        return hovering ? Color.white.opacity(0.08) : .clear
    }
}

// MARK: - Selection actions

private struct SelectionBar: View {
    let session: EditorSession
    let transcript: MediaTranscript
    let selection: TranscriptSelection

    var body: some View {
        let words = transcript.words[selection.lower...selection.upper]
        let duration = (words.last?.end ?? 0) - (words.first?.start ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(words.count == 1 ? tr("1 palavra · %@ s", String(format: "%.1f", duration))
                     : tr("%@ palavras · %@ s", words.count, String(format: "%.1f", duration)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { session.transcriptSelection = nil } label: { Image(systemName: "xmark") }
                    .iconButton(size: 20)
                    .help(tr("Limpar seleção (Esc)"))
            }
            HStack(spacing: 6) {
                Button { session.removeSelectedTranscript() } label: { Label(tr("Remover trecho"), systemImage: "scissors") }
                    .buttonStyle(AudraButtonStyle(kind: .primary))
                    .help(tr("Remove o trecho do vídeo e fecha o espaço em todas as faixas"))
                Menu {
                    Button(tr("Localizar na Timeline"), systemImage: "scope") { session.revealSelectedTranscript() }
                    Button(tr("Silenciar Trecho"), systemImage: "speaker.slash") { session.muteSelectedTranscript() }
                    Button(tr("Criar Legenda"), systemImage: "captions.bubble") { session.captionSelectedTranscript() }
                    Divider()
                    Button(tr("Copiar Texto"), systemImage: "doc.on.doc") { Exporter.copy(words.map(\.text).joined(separator: " ")) }
                } label: {
                    Label(tr("Mais"), systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer(minLength: 0)
                Button { session.revealSelectedTranscript() } label: { Image(systemName: "scope") }
                    .iconButton(size: 26)
                    .help(tr("Localizar na timeline"))
            }
        }
        .padding(10)
        .panelSurface(radius: 12, fill: Theme.elevated)
    }
}
