import AppKit
import Observation
import SwiftData

/// Library destinations shown in the top bar.
enum SidebarItem: Hashable {
    case home
    case transcriptions
    case projects
    case recording(UUID)

    /// The tab highlighted in the top bar for this destination.
    var tab: SidebarItem {
        if case .recording = self { return .transcriptions }
        return self
    }
}

enum ResultMode: String, CaseIterable, Identifiable {
    case full, transcript, summary
    var id: String { rawValue }
    var label: String {
        switch self {
        case .full: tr("Completo")
        case .transcript: tr("Transcrição")
        case .summary: tr("Resumo")
        }
    }
    var symbol: String {
        switch self {
        case .full: "rectangle.split.2x1"
        case .transcript: "text.alignleft"
        case .summary: "sparkles.rectangle.stack"
        }
    }
}

/// App-wide state: selection, import, the processing queue and command routing.
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let processing: ProcessingCenter
    let projects = ProjectStore()

    /// The open editing project; nil while browsing the library.
    private(set) var editor: EditorSession?
    /// Incremented to ask the editor to show its export sheet (menu command).
    var exportRequest = 0

    var selection: SidebarItem? = .home {
        didSet { if case .recording = selection {} else if let selection { lastTab = selection } }
    }
    /// Tab to return to when leaving a recording.
    private(set) var lastTab: SidebarItem = .home
    /// Library-wide search text (top bar).
    var search = ""
    /// Incremented to focus the top-bar search field (⌘K).
    var searchFocusRequest = 0
    var resultMode: ResultMode = .full
    var notice: String?

    /// Set by the visible results screen so menu commands can drive playback.
    weak var player: PlayerController?
    /// Incremented to ask the transcript to show and focus its find bar.
    var findRequest = 0

    var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
        self.processing = ProcessingCenter(context: container.mainContext)
    }

    var selectedRecording: Recording? {
        guard case .recording(let id)? = selection else { return nil }
        return recording(id)
    }

    func recording(_ id: UUID) -> Recording? {
        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Import

    func presentImporter() {
        let panel = NSOpenPanel()
        panel.title = tr("Importar vídeos")
        panel.prompt = tr("Transcrever")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = MediaInspector.contentTypes
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    func importFiles(_ urls: [URL]) {
        var rejected: [String] = []
        var firstID: UUID?

        for url in urls {
            guard MediaInspector.isAccepted(url) else { rejected.append(url.lastPathComponent); continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate

            // Skip redundant work: the same unchanged file was already processed.
            if let existing = findExisting(path: url.path, size: size, modified: modified) {
                if existing.status == .failed || existing.status == .cancelled {
                    processing.enqueue(existing)
                } else if existing.status == .completed {
                    notice = tr("“%@” já foi transcrito. Abrindo o resultado existente.", existing.title)
                }
                firstID = firstID ?? existing.id
                continue
            }

            let recording = Recording(url: url, fileSize: size, fileModified: modified)
            context.insert(recording)
            processing.enqueue(recording)
            firstID = firstID ?? recording.id
        }
        try? context.save()

        if let firstID { selection = .recording(firstID) }
        if !rejected.isEmpty {
            notice = tr("Formato não suportado: ") + rejected.joined(separator: ", ")
        }
    }

    private func findExisting(path: String, size: Int64, modified: Date?) -> Recording? {
        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.sourcePath == path && $0.fileSize == size })
        descriptor.fetchLimit = 5
        let matches = (try? context.fetch(descriptor)) ?? []
        return matches.first { existing in
            guard let a = existing.fileModified, let b = modified else { return true }
            return abs(a.timeIntervalSince(b)) < 1
        }
    }

    /// Library recording made from the file at `url`, if any.
    func library(for url: URL) -> Recording? {
        let path = url.path
        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.sourcePath == path },
                                                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Queues a transcription without changing the current screen (used by the editor).
    @discardableResult
    func enqueueTranscription(_ url: URL) -> Recording? {
        if let existing = library(for: url) {
            if !existing.status.isActive && existing.status != .completed { processing.enqueue(existing) }
            return existing
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let recording = Recording(url: url, fileSize: Int64(values?.fileSize ?? 0), fileModified: values?.contentModificationDate)
        context.insert(recording)
        processing.enqueue(recording)
        try? context.save()
        return recording
    }

    func goBack() {
        selection = lastTab == .home || lastTab == .projects ? lastTab : .transcriptions
    }

    // MARK: - Projects

    func openProject(_ id: UUID) {
        do {
            let project = try projects.load(id)
            openProject(project)
        } catch {
            notice = tr("Não foi possível abrir o projeto: %@", error.localizedDescription)
            projects.refresh()
        }
    }

    func openProject(_ project: EditProject) {
        editor?.close()
        player?.player.pause()
        editor = EditorSession(project: project, store: projects, app: self)
    }

    func closeEditor() {
        editor?.close()
        editor = nil
        projects.refresh()
        if selection == nil { selection = .projects }
    }

    func newProject() {
        do {
            let project = try projects.create(name: projects.uniqueName(tr("Novo projeto")))
            openProject(project)
        } catch {
            notice = tr("Não foi possível criar o projeto: %@", error.localizedDescription)
        }
    }

    /// Creates a project from a transcribed recording, keeping the link to its transcript.
    func editInNewProject(_ recording: Recording) {
        Task {
            do {
                var item = try await MediaPool.probe(url: recording.sourceURL,
                                                     proxy: recording.proxyPath.map(URL.init(fileURLWithPath:)))
                item.recordingID = recording.id
                let project = try projects.create(name: projects.uniqueName(recording.title), media: [item])
                openProject(project)
                editor?.leftTab = .transcript
            } catch {
                notice = tr("Não foi possível abrir no editor: %@", error.localizedDescription)
            }
        }
    }

    func confirmDeleteProject(_ summary: ProjectSummary) {
        let alert = NSAlert()
        alert.messageText = tr("Mover “%@” para o Lixo?", summary.name)
        alert.informativeText = tr("Os arquivos de vídeo e áudio usados no projeto não serão alterados. Você pode recuperar o projeto no Lixo.")
        alert.addButton(withTitle: tr("Mover para o Lixo"))
        alert.addButton(withTitle: tr("Cancelar"))
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { projects.trash(summary.id) }
    }

    // MARK: - Library actions

    func reprocess(_ recording: Recording) {
        processing.enqueue(recording, mode: .full)
        selection = .recording(recording.id)
    }

    /// Transcribes the file again in `language` ("auto" detects it). Replaces the transcript and summary.
    func retranscribe(_ recording: Recording, language: String) {
        if recording.status == .completed {
            let alert = NSAlert()
            alert.messageText = tr("Transcrever novamente em %@?", language == "auto" ? "idioma detectado automaticamente" : LanguageNames.name(for: language))
            alert.informativeText = tr("A transcrição atual e o resumo de “%@” serão substituídos. O arquivo original não é alterado.", recording.title)
            alert.addButton(withTitle: tr("Transcrever"))
            alert.addButton(withTitle: tr("Cancelar"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        recording.requestedLanguage = language
        try? context.save()
        reprocess(recording)
        notice = tr("Transcrevendo “%@” em %@…", recording.title, language == "auto" ? "idioma detectado" : LanguageNames.name(for: language))
    }

    func regenerateSummary(_ recording: Recording) {
        guard recording.segmentCount > 0 else { return }
        processing.enqueue(recording, mode: .summaryOnly)
    }

    func delete(_ recording: Recording) {
        processing.cancel(recording.id)
        if let proxy = recording.proxyPath { try? FileManager.default.removeItem(atPath: proxy) }
        AudioExtractor.cleanUp(id: recording.id)
        if selection == .recording(recording.id) { selection = .home }
        context.delete(recording)
        try? context.save()
    }

    func confirmDelete(_ recording: Recording) {
        let alert = NSAlert()
        alert.messageText = tr("Remover “%@” da biblioteca?", recording.title)
        alert.informativeText = tr("A transcrição e o resumo serão apagados. O arquivo de vídeo original não será alterado.")
        alert.addButton(withTitle: tr("Remover"))
        alert.addButton(withTitle: tr("Cancelar"))
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { delete(recording) }
    }

    func revealInFinder(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.sourceURL])
    }
}
