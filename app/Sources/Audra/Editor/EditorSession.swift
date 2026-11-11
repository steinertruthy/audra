import AVFoundation
import AppKit
import Observation
import SwiftData

enum SaveState: Equatable {
    case saved(Date)
    case pending
    case saving
    case failed(String)
}

enum EditorLeftTab: String, CaseIterable, Identifiable {
    case media, transcript, text, tools, ai
    var id: String { rawValue }
    var title: String {
        switch self {
        case .media: tr("Mídia")
        case .transcript: tr("Transcrição")
        case .text: tr("Texto")
        case .tools: tr("Ferramentas")
        case .ai: tr("IA")
        }
    }
    var symbol: String {
        switch self {
        case .media: "photo.on.rectangle.angled"
        case .transcript: "text.quote"
        case .text: "textformat"
        case .tools: "slider.horizontal.3"
        case .ai: "sparkles"
        }
    }
}

/// Transcript of one media file, flattened to words for fast lookup.
struct MediaTranscript {
    let recordingID: UUID
    let title: String
    let segments: [TranscriptSegment]
    let words: [TranscriptWord]
    /// Index of the first word of each segment.
    let segmentStarts: [Int]
    let summary: VideoSummary?
    let hasWordTiming: Bool

    init(recording: Recording) {
        recordingID = recording.id
        title = recording.title
        segments = recording.decodeSegments()
        var words: [TranscriptWord] = []
        var starts: [Int] = []
        for segment in segments {
            starts.append(words.count)
            words += segment.timedWords
        }
        self.words = words
        segmentStarts = starts
        summary = recording.decodeSummary()
        hasWordTiming = segments.contains { $0.words != nil && !$0.edited }
    }

    /// Word being spoken at media time `s`.
    func wordIndex(at s: Double) -> Int? {
        var low = 0, high = words.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if words[mid].start <= s + 0.02 { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard found >= 0, s <= words[found].end + 0.35 else { return nil }
        return found
    }
}

struct TranscriptSelection: Equatable {
    var mediaID: UUID
    var anchor: Int
    var head: Int
    var lower: Int { min(anchor, head) }
    var upper: Int { max(anchor, head) }
}

/// Live state of one open project: the edit, selection, playback, undo history and autosave.
@MainActor
@Observable
final class EditorSession {
    private(set) var project: EditProject
    var selection: Set<UUID> = []
    var leftTab: EditorLeftTab = .media
    var showLeftPanel = true
    var showInspector = true
    var theaterMode = false
    var snapping = true

    // Timeline viewport (not part of undo history).
    var pixelsPerSecond: Double
    var scrollX: Double

    // Playback
    let player = AVPlayer()
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var isBuilding = false
    private(set) var buildError: String?
    var monitorVolume: Float = 1 { didSet { player.volume = monitorVolume } }
    var monitorMuted = false { didSet { player.isMuted = monitorMuted } }
    var playbackRate: Float = 1 { didSet { if isPlaying { player.rate = playbackRate } } }

    // History & saving
    private(set) var saveState: SaveState = .saved(Date())
    private var undoStack: [(name: String, project: EditProject)] = []
    private var redoStack: [(name: String, project: EditProject)] = []
    private var lastCoalesceKey: String?
    private var lastCoalesceDate = Date.distantPast
    var undoName: String? { undoStack.last?.name }
    var redoName: String? { redoStack.last?.name }

    // Transcripts
    private(set) var transcripts: [UUID: MediaTranscript] = [:]
    var transcriptSelection: TranscriptSelection?
    /// Timeline ranges briefly highlighted after "find in timeline".
    var highlightedRanges: [ClosedRange<Double>] = []

    // Export
    var exportJob: ExportJob?
    var isImporting = false

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var structureKey: Int?
    @ObservationIgnored private var buildGeneration = 0
    @ObservationIgnored private var seekInFlight = false
    @ObservationIgnored private var pendingSeek: Double?

    init(project: EditProject, store: ProjectStore, app: AppModel?) {
        self.project = project
        self.store = store
        self.app = app
        pixelsPerSecond = project.viewState.pixelsPerSecond
        scrollX = project.viewState.scrollX
        currentTime = project.viewState.playhead
        player.actionAtItemEnd = .pause
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.seekInFlight else { return }
                let t = time.seconds
                if t.isFinite { self.currentTime = min(max(0, t), self.duration) }
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let playing = player.rate != 0
            Task { @MainActor in self?.isPlaying = playing }
        }
        refreshTranscripts()
        rebuild(immediately: true)
    }

    func close() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        rateObservation?.invalidate()
        rebuildTask?.cancel()
        exportJob?.cancel()
        flushSave()
        player.replaceCurrentItem(with: nil)
    }

    var duration: Double { project.duration }
    var fps: Double { project.canvas.fps }

    // MARK: - Editing

    /// Applies an edit as one undoable step. Edits sharing a `coalesce` key within a second merge
    /// into one step (slider drags, typing).
    func perform(_ name: String, coalesce: String? = nil, _ change: (inout EditProject) -> Void) {
        var updated = project
        change(&updated)
        guard updated != project else { return }
        let now = Date()
        let merges = coalesce != nil && coalesce == lastCoalesceKey && now.timeIntervalSince(lastCoalesceDate) < 1.2
        if !merges {
            undoStack.append((name, project))
            if undoStack.count > 200 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        lastCoalesceKey = coalesce
        lastCoalesceDate = now
        updated.modifiedAt = now
        apply(updated)
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        redoStack.append((entry.name, project))
        lastCoalesceKey = nil
        apply(entry.project)
        app?.notice = tr("Desfeito: %@", entry.name)
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        undoStack.append((entry.name, project))
        lastCoalesceKey = nil
        apply(entry.project)
    }

    private func apply(_ updated: EditProject) {
        project = updated
        let ids = Set(project.tracks.flatMap(\.clips).map(\.id))
        selection = selection.intersection(ids)
        if currentTime > duration { seek(to: duration) }
        rebuild()
        scheduleSave()
    }

    /// Changes that should not create history (e.g. linking a transcript).
    private func silently(_ change: (inout EditProject) -> Void) {
        var updated = project
        change(&updated)
        guard updated != project else { return }
        project = updated
        scheduleSave()
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform(tr("Renomear projeto")) { $0.name = trimmed }
    }

    // MARK: Clip commands

    var selectedClips: [EditClip] { selection.compactMap { project.clip($0) } }
    var singleSelectedClip: EditClip? { selection.count == 1 ? selection.first.flatMap { project.clip($0) } : nil }

    func splitAtPlayhead() {
        let t = currentTime
        var created: [UUID] = []
        perform(tr("Dividir")) { created = $0.split(at: t, clipIDs: selection) }
        if created.isEmpty { app?.notice = tr("Posicione o cursor de reprodução sobre um clipe para dividir.") }
    }

    func deleteSelection(ripple: Bool = false) {
        guard !selection.isEmpty else { return }
        let clips = selectedClips
        if ripple {
            let ranges = clips.map { $0.start...$0.end }
            perform(tr("Excluir e fechar espaço")) { project in
                project.delete(Set(clips.map(\.id)))
                project.rippleDelete(ranges: ranges)
            }
        } else {
            perform(clips.count == 1 ? tr("Excluir clipe") : tr("Excluir clipes")) { $0.delete(selection) }
        }
        selection = []
    }

    func duplicateSelection() {
        var created: [UUID] = []
        perform(tr("Duplicar")) { created = $0.duplicate(selection) }
        if !created.isEmpty { selection = Set(created) }
    }

    func detachAudio() {
        guard let clip = singleSelectedClip else { return }
        var audioID: UUID?
        perform(tr("Separar áudio")) { audioID = $0.detachAudio(clip.id) }
        if let audioID { selection = [audioID] } else { app?.notice = tr("Este clipe não tem áudio para separar.") }
    }

    func update(_ clipID: UUID, _ name: String, coalesce: String? = nil, _ change: (inout EditClip) -> Void) {
        perform(name, coalesce: coalesce.map { "\($0)-\(clipID)" }) { project in
            guard let loc = project.location(of: clipID), !project.tracks[loc.track].isLocked else { return }
            change(&project.tracks[loc.track].clips[loc.clip])
        }
    }

    func setSpeed(_ clipID: UUID, _ speed: Double) {
        perform(tr("Alterar velocidade"), coalesce: "speed-\(clipID)") { $0.setSpeed(clipID, speed) }
    }

    func selectAll() {
        selection = Set(project.tracks.filter { !$0.isLocked }.flatMap(\.clips).map(\.id))
    }

    func updateTrack(_ id: UUID, _ name: String, _ change: (inout EditTrack) -> Void) {
        perform(name) { project in
            guard let index = project.trackIndex(id) else { return }
            change(&project.tracks[index])
        }
    }

    func removeTrack(_ id: UUID) {
        perform(tr("Remover faixa")) { $0.tracks.removeAll { $0.id == id } }
    }

    func addMarker() {
        let t = currentTime
        perform(tr("Adicionar marcador")) { $0.markers.append(TimelineMarker(time: t, title: tr("Marcador %@", $0.markers.count + 1))) }
    }

    func addText(_ style: TextStyle, duration: Double = 4) {
        let t = currentTime
        var created: EditClip?
        perform(tr("Adicionar texto")) { created = $0.insertText(style, at: t, duration: duration) }
        if let created { selection = [created.id] }
    }

    // MARK: - Media

    func importMedia(_ urls: [URL], placeOnTimeline: Bool = true, at time: Double? = nil, trackID: UUID? = nil) {
        let accepted = urls.filter(MediaInspector.isAccepted)
        let rejected = urls.count - accepted.count
        guard !accepted.isEmpty else {
            if rejected > 0 { app?.notice = tr("Formato não suportado.") }
            return
        }
        isImporting = true
        Task {
            var items: [MediaItem] = []
            var failures: [String] = []
            for url in accepted {
                if let existing = project.media.first(where: { $0.path == url.path }) {
                    items.append(existing)
                    continue
                }
                do {
                    var proxy: URL?
                    if MediaInspector.needsProxy.contains(url.pathExtension.lowercased()) {
                        if let recordingProxy = app?.library(for: url)?.proxyPath {
                            proxy = URL(fileURLWithPath: recordingProxy)
                        } else {
                            let target = AppPaths.media.appendingPathComponent("\(UUID().uuidString).mp4")
                            try await FFmpegBridge.makePlayableProxy(from: url, to: target)
                            proxy = target
                        }
                    }
                    var item = try await MediaPool.probe(url: url, proxy: proxy)
                    item.recordingID = app?.library(for: url)?.id
                    items.append(item)
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            isImporting = false
            if !items.isEmpty {
                var placed: [UUID] = []
                perform(items.count == 1 ? tr("Importar mídia") : tr("Importar mídias")) { project in
                    var cursor = time
                    for item in items {
                        if !project.media.contains(where: { $0.id == item.id }) { project.media.append(item) }
                        guard placeOnTimeline else { continue }
                        if let clip = project.insert(media: item, at: cursor, trackID: trackID) {
                            placed.append(clip.id)
                            if cursor != nil { cursor = clip.end }
                        }
                    }
                    if project.media.count == items.count, let first = items.first(where: \.hasVideo), first.width > 0,
                       project.tracks.flatMap(\.clips).count == placed.count {
                        // First media of an empty project defines the canvas.
                        project.canvas.width = first.width
                        project.canvas.height = first.height
                        project.canvas.fps = min(60, max(24, first.frameRate.rounded()))
                    }
                }
                if !placed.isEmpty { selection = Set(placed) }
                refreshTranscripts()
            }
            if let failure = failures.first {
                app?.notice = failures.count == 1 ? tr("Não foi possível importar %@", failure) : tr("%@ arquivos não puderam ser importados.", failures.count)
            }
        }
    }

    func presentImporter() {
        let panel = NSOpenPanel()
        panel.title = tr("Adicionar mídia ao projeto")
        panel.prompt = tr("Adicionar")
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = MediaInspector.contentTypes
        guard panel.runModal() == .OK else { return }
        importMedia(panel.urls)
    }

    func addToTimeline(_ mediaID: UUID, at time: Double? = nil, trackID: UUID? = nil) {
        guard let item = project.mediaItem(mediaID) else { return }
        var placed: EditClip?
        perform(tr("Adicionar à timeline")) { placed = $0.insert(media: item, at: time, trackID: trackID) }
        if let placed { selection = [placed.id] }
    }

    func removeMedia(_ mediaID: UUID) {
        perform(tr("Remover mídia do projeto")) { project in
            for t in project.tracks.indices { project.tracks[t].clips.removeAll { $0.mediaID == mediaID } }
            project.media.removeAll { $0.id == mediaID }
        }
    }

    /// Replaces a video clip's sound with an audio file, keeping the picture.
    func replaceAudio(of clipID: UUID) {
        let panel = NSOpenPanel()
        panel.title = tr("Escolha o novo áudio")
        panel.allowedContentTypes = [.audio, .movie]
        guard panel.runModal() == .OK, let url = panel.url, let clip = project.clip(clipID) else { return }
        Task {
            do {
                let item = try await MediaPool.probe(url: url)
                guard item.hasAudio else { app?.notice = tr("O arquivo escolhido não tem áudio."); return }
                var newID: UUID?
                perform(tr("Substituir áudio")) { project in
                    if !project.media.contains(where: { $0.path == item.path }) { project.media.append(item) }
                    let media = project.media.first { $0.path == item.path } ?? item
                    guard let loc = project.location(of: clipID) else { return }
                    project.tracks[loc.track].clips[loc.clip].audioMuted = true
                    var audio = EditClip(mediaID: media.id, start: clip.start, sourceIn: 0,
                                         sourceOut: min(media.duration, clip.duration), label: media.name)
                    audio.audioFadeOut = min(0.5, audio.duration / 4)
                    var target = project.tracks.indices.first {
                        project.tracks[$0].kind == .audio && !project.tracks[$0].isLocked
                            && project.isFree(track: $0, start: audio.start, duration: audio.duration)
                    }
                    if target == nil {
                        project.addTrack(.audio)
                        target = project.tracks.lastIndex { $0.kind == .audio }
                    }
                    guard let target else { return }
                    project.tracks[target].clips.append(audio)
                    project.sortClips(track: target)
                    newID = audio.id
                }
                if let newID { selection = [newID] }
            } catch {
                app?.notice = error.localizedDescription
            }
        }
    }

    // MARK: - Transcripts

    func refreshTranscripts() {
        guard let app else { return }
        var found: [UUID: MediaTranscript] = [:]
        var links: [(UUID, UUID)] = []
        for item in project.media where item.hasAudio {
            let recording = item.recordingID.flatMap { app.recording($0) } ?? app.library(for: item.sourceURL)
            guard let recording, recording.status == .completed || recording.segmentCount > 0 else { continue }
            found[item.id] = MediaTranscript(recording: recording)
            if item.recordingID != recording.id { links.append((item.id, recording.id)) }
        }
        transcripts = found
        if !links.isEmpty {
            silently { project in
                for (mediaID, recordingID) in links {
                    if let i = project.media.firstIndex(where: { $0.id == mediaID }) { project.media[i].recordingID = recordingID }
                }
            }
        }
    }

    /// Media whose transcript the panel shows: the user's choice, else the media under the playhead.
    var transcriptMediaID: UUID? {
        if let chosen = project.viewState.transcriptMediaID, transcripts[chosen] != nil { return chosen }
        let underPlayhead = project.tracks.filter { $0.kind != .text }.flatMap(\.clips)
            .first { $0.contains(currentTime) && $0.mediaID.map { transcripts[$0] != nil } == true }
        return underPlayhead?.mediaID ?? project.media.first { transcripts[$0.id] != nil }?.id
    }

    func chooseTranscriptMedia(_ id: UUID) {
        silently { $0.viewState.transcriptMediaID = id }
    }

    func transcribe(_ mediaID: UUID) {
        guard let item = project.mediaItem(mediaID), let app else { return }
        if let recording = app.enqueueTranscription(item.sourceURL) {
            silently { project in
                if let i = project.media.firstIndex(where: { $0.id == mediaID }) { project.media[i].recordingID = recording.id }
            }
        }
    }

    /// Media-time range of the selected words, with cut points nudged into the surrounding silence.
    func selectedSourceRange() -> (media: UUID, start: Double, end: Double)? {
        guard let sel = transcriptSelection, let transcript = transcripts[sel.mediaID],
              transcript.words.indices.contains(sel.lower), transcript.words.indices.contains(sel.upper) else { return nil }
        var a = transcript.words[sel.lower].start
        var b = transcript.words[sel.upper].end
        let previousEnd = sel.lower > 0 ? transcript.words[sel.lower - 1].end : max(0, a - 0.3)
        let nextStart = sel.upper + 1 < transcript.words.count ? transcript.words[sel.upper + 1].start : b + 0.3
        if let item = project.mediaItem(sel.mediaID), let wave = MediaCache.shared.waveform(for: item) {
            a = wave.quietestPoint(in: max(previousEnd - 0.02, a - 0.2)...(a + 0.04), fallback: a)
            b = wave.quietestPoint(in: (b - 0.04)...min(nextStart + 0.02, b + 0.2), fallback: b)
        } else {
            a = max(previousEnd, a - 0.03)
            b = min(nextStart, b + 0.03)
        }
        return (sel.mediaID, a, max(b, a + 0.05))
    }

    func removeSelectedTranscript() {
        guard let range = selectedSourceRange() else { return }
        var removed: [ClosedRange<Double>] = []
        perform(tr("Remover trecho da transcrição")) { removed = $0.removeSource(range.start, range.end, media: range.media) }
        transcriptSelection = nil
        if removed.isEmpty {
            app?.notice = tr("Esse trecho já não faz parte da edição.")
        } else {
            let total = removed.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
            app?.notice = tr("Trecho removido (%@ s). Use ⌘Z para desfazer.", String(format: "%.1f", total))
            if let first = removed.first { seek(to: first.lowerBound) }
        }
    }

    func muteSelectedTranscript() {
        guard let range = selectedSourceRange() else { return }
        perform(tr("Silenciar trecho")) { $0.muteSource(range.start, range.end, media: range.media) }
        transcriptSelection = nil
    }

    func revealSelectedTranscript() {
        guard let range = selectedSourceRange() else { return }
        let ranges = project.timelineRanges(forSource: range.start, range.end, media: range.media)
        guard let first = ranges.first else { app?.notice = tr("Esse trecho não está na timeline."); return }
        highlightedRanges = ranges
        selection = Set(project.tracks.flatMap(\.clips).filter { clip in
            clip.mediaID == range.media && ranges.contains { clip.start < $0.upperBound && clip.end > $0.lowerBound }
        }.map(\.id))
        seek(to: first.lowerBound)
        revealInTimeline(first.lowerBound)
    }

    func captionSelectedTranscript() {
        guard let sel = transcriptSelection, let transcript = transcripts[sel.mediaID],
              let range = selectedSourceRange() else { return }
        let text = transcript.words[sel.lower...sel.upper].map(\.text).joined(separator: " ")
        guard let start = project.timelineTime(forSource: range.start, media: range.media) else {
            app?.notice = tr("Esse trecho não está na timeline.")
            return
        }
        let length = max(0.6, (range.end - range.start))
        addText(.caption(CaptionBuilder.wrap(text, lineLength: 42)), duration: length)
        if let id = selection.first { update(id, tr("Posicionar legenda")) { $0.start = start } }
    }

    func generateSubtitles(for mediaID: UUID) {
        guard let transcript = transcripts[mediaID] else { return }
        var count = 0
        perform(tr("Gerar legendas")) { count = $0.generateSubtitles(from: transcript.segments, media: mediaID) }
        app?.notice = count > 0 ? tr("%@ legendas criadas na faixa “Legendas”.", count) : tr("Nenhum trecho transcrito está na timeline.")
    }

    func addChapterMarkers(for mediaID: UUID) {
        guard let chapters = transcripts[mediaID]?.summary?.chapters, !chapters.isEmpty else { return }
        perform(tr("Adicionar capítulos")) { project in
            for chapter in chapters {
                guard let t = project.timelineTime(forSource: chapter.start, media: mediaID) else { continue }
                if !project.markers.contains(where: { abs($0.time - t) < 0.5 }) {
                    project.markers.append(TimelineMarker(time: t, title: chapter.title))
                }
            }
        }
    }

    /// Removes pauses longer than `minimum` seconds from a clip, using the waveform.
    func removeSilences(minimum: Double = 0.8, threshold: Float = 0.06) {
        let candidates = selectedClips.isEmpty ? project.tracks.filter { $0.kind == .video }.flatMap(\.clips) : selectedClips
        var ranges: [ClosedRange<Double>] = []
        for clip in candidates {
            guard let item = project.mediaItem(clip.mediaID), let wave = MediaCache.shared.waveform(for: item) else { continue }
            var silenceStart: Double?
            var s = clip.sourceIn
            while s < clip.sourceOut {
                let quiet = wave.peak(from: s, to: s + 0.05) < threshold
                if quiet, silenceStart == nil { silenceStart = s }
                if !quiet || s + 0.05 >= clip.sourceOut, let start = silenceStart {
                    let end = s
                    if end - start >= minimum {
                        // Keep a short breath on each side so speech is not clipped.
                        let a = clip.timelineTime(forSource: start + 0.15), b = clip.timelineTime(forSource: end - 0.15)
                        if b > a { ranges.append(a...b) }
                    }
                    silenceStart = nil
                }
                s += 0.05
            }
        }
        guard !ranges.isEmpty else {
            app?.notice = MediaCache.shared.waveforms.isEmpty ? tr("Analisando o áudio… tente novamente em instantes.") : tr("Nenhuma pausa longa encontrada.")
            return
        }
        let total = ranges.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        perform(tr("Remover pausas")) { $0.rippleDelete(ranges: ranges) }
        app?.notice = tr("%@ pausas removidas (%@ s).", ranges.count, String(format: "%.1f", total))
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - 0.05 { seek(to: 0) }
            player.playImmediately(atRate: playbackRate)
        }
    }

    func pause() { player.pause() }

    /// Frame-accurate seek that coalesces rapid requests (scrubbing).
    func seek(to seconds: Double) {
        let target = min(max(0, seconds), max(0, duration))
        currentTime = target
        guard player.currentItem != nil else { return }
        if seekInFlight { pendingSeek = target; return }
        seekInFlight = true
        player.seek(to: CompositionBuilder.time(target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seekInFlight = false
                if let next = self.pendingSeek {
                    self.pendingSeek = nil
                    self.seek(to: next)
                }
            }
        }
    }

    func step(frames: Int) {
        pause()
        let frame = 1 / max(1, fps)
        let snapped = (currentTime / frame).rounded() * frame
        seek(to: snapped + Double(frames) * frame)
    }

    func jump(by seconds: Double) { seek(to: currentTime + seconds) }

    /// Zooms the timeline around the playhead.
    func zoom(by factor: Double) {
        let new = min(max(pixelsPerSecond * factor, TimelineMetrics.minPPS), TimelineMetrics.maxPPS)
        let anchor = currentTime * pixelsPerSecond - scrollX
        pixelsPerSecond = new
        scrollX = max(0, currentTime * new - anchor)
    }

    /// Request to scroll the timeline so `time` is visible.
    var revealRequest: (time: Double, id: Int)?
    func revealInTimeline(_ time: Double) {
        revealRequest = (time, (revealRequest?.id ?? 0) + 1)
    }

    // MARK: - Composition

    func rebuild(immediately: Bool = false) {
        rebuildTask?.cancel()
        buildGeneration += 1
        let generation = buildGeneration
        let snapshot = project
        rebuildTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(70)) }
            guard !Task.isCancelled, let self else { return }
            self.isBuilding = true
            do {
                let built = try await CompositionBuilder.build(snapshot)
                guard generation == self.buildGeneration else { return }
                self.install(built, key: Self.structureKey(snapshot))
                self.buildError = nil
            } catch is CancellationError {
            } catch {
                if generation == self.buildGeneration { self.buildError = error.localizedDescription }
            }
            if generation == self.buildGeneration { self.isBuilding = false }
        }
    }

    private func install(_ built: BuiltComposition, key: Int) {
        if key == structureKey, let item = player.currentItem {
            // Same tracks and timing: swap the render instructions in place (no flicker).
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
            if !isPlaying { refreshFrame() }
            return
        }
        structureKey = key
        let wasPlaying = isPlaying
        let time = min(currentTime, built.duration)
        let item = AVPlayerItem(asset: built.asset)
        item.videoComposition = built.videoComposition
        item.audioMix = built.audioMix
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)
        player.seek(to: CompositionBuilder.time(time), toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying { player.playImmediately(atRate: playbackRate) }
    }

    private func refreshFrame() {
        player.seek(to: CompositionBuilder.time(currentTime), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    static func structureKey(_ project: EditProject) -> Int {
        var hasher = Hasher()
        hasher.combine(project.duration)
        for track in project.tracks where track.kind != .text {
            hasher.combine(track.id)
            hasher.combine(track.isHidden)
            hasher.combine(track.isMuted)
            for clip in track.clips {
                hasher.combine(clip.id)
                hasher.combine(clip.mediaID)
                hasher.combine(clip.start)
                hasher.combine(clip.sourceIn)
                hasher.combine(clip.sourceOut)
                hasher.combine(clip.speed)
                hasher.combine(clip.audioMuted)
                hasher.combine(clip.volume > 0.001)
                hasher.combine(clip.transition)
            }
        }
        return hasher.finalize()
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveState = .pending
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private func snapshotForSave() -> EditProject {
        var copy = project
        copy.viewState.playhead = currentTime
        copy.viewState.pixelsPerSecond = pixelsPerSecond
        copy.viewState.scrollX = scrollX
        return copy
    }

    func saveNow() async {
        saveState = .saving
        let snapshot = snapshotForSave()
        do {
            try await Task.detached(priority: .utility) { try ProjectStore.write(snapshot) }.value
            store.upsert(snapshot)
            saveState = .saved(Date())
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    /// Synchronous save used when closing the project or quitting.
    func flushSave() {
        saveTask?.cancel()
        let snapshot = snapshotForSave()
        do {
            try ProjectStore.write(snapshot)
            store.upsert(snapshot)
            saveState = .saved(Date())
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Export

    func startExport(_ settings: ExportSettings, to url: URL) {
        pause()
        let job = ExportJob(settings: settings, destination: url)
        exportJob = job
        job.start(project: project)
    }
}

/// Progress and outcome of one export.
@MainActor
@Observable
final class ExportJob {
    enum State: Equatable { case running, finished, failed(String), cancelled }
    let settings: ExportSettings
    let destination: URL
    private(set) var progress: Double = 0
    private(set) var state: State = .running
    private(set) var startedAt = Date()
    private(set) var finishedAt: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(settings: ExportSettings, destination: URL) {
        self.settings = settings
        self.destination = destination
    }

    func start(project: EditProject) {
        startedAt = Date()
        let settings = self.settings, destination = self.destination
        task = Task { [weak self] in
            do {
                try await VideoExporter.export(project, settings: settings, to: destination) { value in
                    Task { @MainActor in if let self, value > self.progress { self.progress = value } }
                }
                self?.progress = 1
                self?.state = .finished
            } catch is CancellationError {
                self?.state = .cancelled
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
            self?.finishedAt = Date()
        }
    }

    func cancel() {
        guard state == .running else { return }
        task?.cancel()
    }
}
