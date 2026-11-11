import AppKit
import Observation

struct ProjectSummary: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var name: String
    var modifiedAt: Date
    var duration: Double
    var clipCount: Int
    var poster: MediaItem?
}

/// Projects are stored as JSON documents in Application Support. Writes are atomic, so a crash
/// mid-save never leaves a half-written project behind.
@MainActor
@Observable
final class ProjectStore {
    private(set) var projects: [ProjectSummary] = []
    private(set) var loadErrors: [String] = []

    init() { refresh() }

    nonisolated static func url(for id: UUID) -> URL {
        AppPaths.projects.appendingPathComponent("\(id.uuidString).\(EditProject.fileExtension)")
    }

    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(at: AppPaths.projects, includingPropertiesForKeys: nil)) ?? []
        var summaries: [ProjectSummary] = []
        var errors: [String] = []
        for url in files where url.pathExtension == EditProject.fileExtension {
            do {
                let project = try Self.read(url)
                summaries.append(Self.summary(project, url: url))
            } catch {
                errors.append(url.lastPathComponent)
            }
        }
        projects = summaries.sorted { $0.modifiedAt > $1.modifiedAt }
        loadErrors = errors
    }

    static func summary(_ project: EditProject, url: URL) -> ProjectSummary {
        let firstVideo = project.tracks.filter { $0.kind == .video }.flatMap(\.clips).min { $0.start < $1.start }
        return ProjectSummary(id: project.id, url: url, name: project.name, modifiedAt: project.modifiedAt,
                              duration: project.duration, clipCount: project.tracks.reduce(0) { $0 + $1.clips.count },
                              poster: project.mediaItem(firstVideo?.mediaID) ?? project.media.first { $0.hasVideo })
    }

    nonisolated static func read(_ url: URL) throws -> EditProject {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EditProject.self, from: data)
    }

    func load(_ id: UUID) throws -> EditProject {
        try Self.read(Self.url(for: id))
    }

    /// Atomic write; nonisolated so autosave never blocks the UI.
    nonisolated static func write(_ project: EditProject) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: url(for: project.id), options: .atomic)
    }

    func save(_ project: EditProject) throws {
        try Self.write(project)
        upsert(project)
    }

    func upsert(_ project: EditProject) {
        let summary = Self.summary(project, url: Self.url(for: project.id))
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = summary
        } else {
            projects.insert(summary, at: 0)
        }
        projects.sort { $0.modifiedAt > $1.modifiedAt }
    }

    func create(name: String, media: [MediaItem] = [], canvasFrom first: MediaItem? = nil) throws -> EditProject {
        var project = EditProject(name: name)
        if let reference = first ?? media.first(where: { $0.hasVideo }), reference.width > 0, reference.height > 0 {
            project.canvas.width = reference.width
            project.canvas.height = reference.height
            project.canvas.fps = min(60, max(24, reference.frameRate.rounded()))
        }
        for item in media {
            project.media.append(item)
            project.insert(media: item, at: nil)
        }
        try save(project)
        return project
    }

    func rename(_ id: UUID, to name: String) {
        guard var project = try? load(id), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        project.name = name.trimmingCharacters(in: .whitespaces)
        project.modifiedAt = Date()
        try? save(project)
    }

    func duplicate(_ id: UUID) -> EditProject? {
        guard var project = try? load(id) else { return nil }
        project.id = UUID()
        project.name += tr(" (cópia)")
        project.createdAt = Date()
        project.modifiedAt = Date()
        try? save(project)
        return project
    }

    /// Moves the project file to the Trash (recoverable).
    func trash(_ id: UUID) {
        try? FileManager.default.trashItem(at: Self.url(for: id), resultingItemURL: nil)
        projects.removeAll { $0.id == id }
    }

    func uniqueName(_ base: String) -> String {
        let names = Set(projects.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
