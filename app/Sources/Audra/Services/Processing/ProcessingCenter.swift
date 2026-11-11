import Foundation
import Observation
import SwiftData

/// Live, non-persisted state of the job currently running (or waiting).
@MainActor
@Observable
final class JobState {
    let recordingID: UUID
    var stage: ProcessingStatus = .queued
    var stageProgress: Double = 0
    var message: String?
    var startedAt: Date?
    var liveSegments: [TranscriptSegment] = []
    var transcriptProgress: Double = 0

    init(recordingID: UUID) { self.recordingID = recordingID }

    /// Weighted overall progress across stages, used for the main progress bar and ETA.
    var overallProgress: Double {
        switch stage {
        case .queued: 0
        case .preparing: stageProgress * 0.10
        case .detectingLanguage: 0.10 + stageProgress * 0.05
        case .transcribing: 0.15 + stageProgress * 0.70
        case .summarizing: 0.85 + stageProgress * 0.15
        default: 1
        }
    }
}

/// Serial processing queue. One file is processed at a time so the Neural Engine and
/// media decoder are not oversubscribed and the interface stays responsive.
@MainActor
@Observable
final class ProcessingCenter {
    enum Mode { case full, summaryOnly }

    private(set) var queue: [UUID] = []
    private(set) var jobs: [UUID: JobState] = [:]
    private(set) var currentID: UUID?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var modes: [UUID: Mode] = [:]
    @ObservationIgnored private var currentTask: Task<Void, Never>?

    init(context: ModelContext) {
        self.context = context
    }

    var activeCount: Int { queue.count + (currentID == nil ? 0 : 1) }

    func job(for id: UUID) -> JobState? { jobs[id] }

    func queuePosition(of id: UUID) -> Int? { queue.firstIndex(of: id).map { $0 + 1 } }

    // MARK: - Public API

    func enqueue(_ recording: Recording, mode: Mode = .full) {
        let id = recording.id
        guard currentID != id, !queue.contains(id) else { return }
        modes[id] = mode
        jobs[id] = JobState(recordingID: id)
        if mode == .full {
            recording.status = .queued
            recording.errorMessage = nil
        } else {
            recording.summaryError = nil
        }
        save()
        queue.append(id)
        pump()
    }

    func cancel(_ id: UUID) {
        if currentID == id {
            currentTask?.cancel()
        } else if let index = queue.firstIndex(of: id) {
            queue.remove(at: index)
            jobs[id] = nil
            if let recording = fetch(id), modes[id] == .full {
                recording.status = .cancelled
                save()
            }
        }
    }

    func cancelAll() {
        for id in queue { cancel(id) }
        if let currentID { cancel(currentID) }
    }

    /// Re-queues work interrupted by a quit or crash.
    func recoverInterruptedJobs() {
        let descriptor = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.createdAt)])
        guard let recordings = try? context.fetch(descriptor) else { return }
        for recording in recordings where recording.status.isActive {
            if !recording.sourceExists {
                recording.status = .failed
                recording.errorMessage = MediaError.fileMissing(recording.sourceURL.lastPathComponent).errorDescription
                continue
            }
            let summaryOnly = recording.status == .summarizing && recording.segmentCount > 0
            enqueue(recording, mode: summaryOnly ? .summaryOnly : .full)
        }
        save()
    }

    // MARK: - Queue

    private func pump() {
        guard currentID == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let recording = fetch(id) else { jobs[id] = nil; pump(); return }
        currentID = id
        let job = jobs[id] ?? JobState(recordingID: id)
        jobs[id] = job
        job.startedAt = Date()
        let mode = modes[id] ?? .full

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.run(recording, job: job, mode: mode)
            self.currentID = nil
            self.currentTask = nil
            self.jobs[id] = nil
            self.modes[id] = nil
            self.pump()
        }
    }

    private func run(_ recording: Recording, job: JobState, mode: Mode) async {
        let start = Date()
        do {
            if mode == .full {
                try await transcribe(recording, job: job)
            }
            if mode == .summaryOnly || Preferences.autoSummarize {
                await summarize(recording, job: job)
            }
            recording.status = .completed
            recording.completedAt = Date()
            if mode == .full { recording.processingSeconds = Date().timeIntervalSince(start) }
        } catch is CancellationError {
            if mode == .full {
                recording.status = .cancelled
                recording.errorMessage = nil
            } else {
                recording.status = .completed
            }
        } catch {
            if mode == .full {
                recording.status = .failed
                recording.errorMessage = error.localizedDescription
            } else {
                recording.status = .completed
                recording.summaryError = error.localizedDescription
            }
        }
        AudioExtractor.cleanUp(id: recording.id)
        save()
    }

    // MARK: - Pipeline

    private func transcribe(_ recording: Recording, job: JobState) async throws {
        let id = recording.id
        guard SpeechEngine.isAvailable else { throw TranscriptionError.unavailable }

        // 1. Media
        set(job, recording, .preparing, message: tr("Lendo arquivo…"))
        let source = recording.sourceURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw MediaError.fileMissing(source.lastPathComponent)
        }

        if MediaInspector.needsProxy.contains(source.pathExtension.lowercased()) {
            let proxy = AppPaths.media.appendingPathComponent("\(id.uuidString).mp4")
            if !FileManager.default.fileExists(atPath: proxy.path) {
                job.message = tr("Convertendo %@ para um formato compatível…", source.pathExtension.uppercased())
                try await FFmpegBridge.makePlayableProxy(from: source, to: proxy)
            }
            recording.proxyPath = proxy.path
        }

        let info = try await MediaInspector.inspect(recording.mediaURL)
        guard info.hasAudio else { throw MediaError.noAudioTrack }
        recording.duration = info.duration
        recording.hasVideo = info.hasVideo
        save()

        job.message = tr("Extraindo áudio…")
        let extracted = try await AudioExtractor().extract(from: recording.mediaURL, id: id) { value in
            Task { @MainActor in job.stageProgress = value }
        }
        try Task.checkCancellation()

        // 2. Language
        let locale: Locale
        let preferred = recording.requestedLanguage ?? Preferences.language
        if preferred == "auto" {
            set(job, recording, .detectingLanguage, message: tr("Identificando o idioma falado…"))
            locale = try await LanguageDetector.detect(sampleURL: extracted.sampleURL) { status in
                Task { @MainActor in job.message = status }
            }
            recording.languageWasDetected = true
        } else {
            guard let resolved = await SpeechEngine.resolve(preferred) else {
                throw TranscriptionError.unsupportedLanguage(preferred)
            }
            locale = resolved
            recording.languageWasDetected = false
        }
        recording.localeIdentifier = locale.identifier(.bcp47)
        try Task.checkCancellation()

        if !(await SpeechEngine.isInstalled(locale)) {
            job.message = tr("Baixando modelo de fala (%@)…", LanguageNames.name(for: recording.localeIdentifier))
            try await SpeechEngine.ensureAssets(for: locale) { value in
                Task { @MainActor in job.stageProgress = value }
            }
        }

        // 3. Transcription
        set(job, recording, .transcribing, message: tr("Transcrevendo em %@…", LanguageNames.name(for: recording.localeIdentifier)))
        let segments = try await SpeechEngine.transcribe(audioURL: extracted.url, locale: locale, duration: extracted.duration) { new, fraction in
            Task { @MainActor in
                job.liveSegments.append(contentsOf: new)
                job.stageProgress = fraction
            }
        }
        try Task.checkCancellation()
        guard !segments.isEmpty else { throw TranscriptionError.noSpeech }

        recording.store(segments: segments)
        recording.store(summary: nil)
        recording.summaryError = nil
        save()
        AudioExtractor.cleanUp(id: id)
    }

    private func summarize(_ recording: Recording, job: JobState) async {
        set(job, recording, .summarizing, message: tr("Gerando resumo…"))
        let summarizer = SummarizerFactory.make()
        job.message = tr("Gerando resumo com %@…", summarizer.displayName)
        let request = SummaryRequest(title: recording.title,
                                     segments: recording.decodeSegments(),
                                     localeIdentifier: recording.localeIdentifier ?? "pt-BR",
                                     detail: Preferences.summaryDetail)
        do {
            let summary = try await summarizer.summarize(request) { value in
                Task { @MainActor in job.stageProgress = value }
            }
            recording.store(summary: summary)
            recording.summaryError = nil
        } catch is CancellationError {
            recording.summaryError = tr("Geração do resumo cancelada.")
        } catch {
            recording.summaryError = error.localizedDescription
        }
        save()
    }

    // MARK: - Helpers

    private func set(_ job: JobState, _ recording: Recording, _ stage: ProcessingStatus, message: String) {
        job.stage = stage
        job.stageProgress = 0
        job.message = message
        // Regenerating the summary of a finished recording keeps it browsable.
        if recording.status != .completed {
            recording.status = stage
            save()
        }
    }

    private func fetch(_ id: UUID) -> Recording? {
        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        do { try context.save() } catch { NSLog("Audra: falha ao salvar: \(error)") }
    }
}
