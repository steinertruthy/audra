import AppKit
import SwiftData
import SwiftUI

@main
struct AudraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        Preferences.registerDefaults()
        CLIRunner.runIfRequested()
        let container = Self.makeContainer()
        let model = AppModel(container: container)
        _model = State(initialValue: model)
        AppDelegate.model = model
        model.processing.recoverInterruptedJobs()
    }

    var body: some Scene {
        Window(tr("Audra"), id: "main") {
            ContentView()
                .environment(model)
                .modelContainer(model.container)
                .frame(minWidth: 1040, minHeight: 640)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands { AudraCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }

    private static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(url: AppPaths.store)
        if let container = try? ModelContainer(for: Recording.self, configurations: configuration) {
            return container
        }
        // The store is unreadable (e.g. corrupted). Keep a backup and start fresh instead of crashing.
        let backup = AppPaths.store.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).store")
        try? FileManager.default.moveItem(at: AppPaths.store, to: backup)
        do {
            return try ModelContainer(for: Recording.self, configurations: configuration)
        } catch {
            return try! ModelContainer(for: Recording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        #if DEBUG
        MainActor.assumeIsolated { if let model = Self.model { DebugHarness.start(model: model) } }
        #endif
    }

    /// Files opened from Finder ("Abrir com") or dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in Self.model?.importFiles(urls) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            Self.model?.editor?.flushSave()
            if Self.model?.editor?.exportJob?.state == .running {
                let alert = NSAlert()
                alert.messageText = tr("Uma exportação está em andamento")
                alert.informativeText = tr("Se sair agora, a exportação será cancelada e o arquivo incompleto será descartado.")
                alert.addButton(withTitle: tr("Sair"))
                alert.addButton(withTitle: tr("Cancelar"))
                if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
            }
            guard let model = Self.model, model.processing.activeCount > 0 else { return .terminateNow }
            let alert = NSAlert()
            alert.messageText = tr("Há transcrições em andamento")
            alert.informativeText = tr("Se sair agora, o processamento será retomado do início na próxima vez que abrir o Audra.")
            alert.addButton(withTitle: tr("Sair"))
            alert.addButton(withTitle: tr("Cancelar"))
            return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
