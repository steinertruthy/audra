#if DEBUG
import AppKit
import SwiftData
import SwiftUI

/// Development-only UI harness. With `AUDRA_DEBUG_SNAPSHOTS=<dir>` the app writes PNG snapshots of its
/// own window while it imports `AUDRA_DEBUG_IMPORT`, walks through the results screen and then the
/// editor (transcript-based cut, subtitles, title, playback and a real export).
@MainActor
enum DebugHarness {
    static func log(_ message: String) {
        FileHandle.standardError.write(Data("[harness] \(message)\n".utf8))
    }

    static func start(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["AUDRA_MARKETING"], let media = env["AUDRA_DEBUG_IMPORT"] {
            self.model = model
            Task { @MainActor in await marketing(model: model, out: URL(fileURLWithPath: dir), media: URL(fileURLWithPath: media)) }
            return
        }
        guard let dir = env["AUDRA_DEBUG_SNAPSHOTS"] else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        self.model = model
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            var opened = false
            if let appMenu = NSApp.mainMenu?.items.first?.submenu,
               let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
                appMenu.performActionForItem(at: index)
                opened = true
            }
            try? await Task.sleep(for: .seconds(1.5))
            log("settings opened=\(opened) windows=\(NSApp.windows.map { "\($0.title):\(Int($0.frame.width))x\(Int($0.frame.height)) v=\($0.isVisible)" })")
            if let settings = NSApp.windows.first(where: { $0.isVisible && $0.frame.width < 800 && $0.frame.width > 500 }),
               let image = composited(settings) {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: out.appendingPathComponent("00-settings.png"))
                settings.close()
            }
            NSApp.deactivate()
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }?.activate()
            try? await Task.sleep(for: .seconds(1))
            snap(out, "00-inactive")
            NSApp.activate()
            try? await Task.sleep(for: .seconds(1))
            snap(out, "01-home")
            if env["AUDRA_DEBUG_LANGS"] != nil {
                for language in [InterfaceLanguage.en, .es] {
                    Localization.shared.preference = language
                    try? await Task.sleep(for: .seconds(0.8))
                    snap(out, "01-home-\(language.rawValue)")
                }
                Localization.shared.preference = .en
            }
            // Synthetic click on the "Projetos" tab in the top bar, to prove the bar is clickable.
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) {
                let point = NSPoint(x: 395, y: window.contentView!.bounds.height - Theme.topBarHeight / 2)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        NSApp.sendEvent(event)
                    }
                }
                try? await Task.sleep(for: .seconds(0.6))
                log("top-bar click → selection \(String(describing: model.selection))")
            }
            model.selection = .projects
            try? await Task.sleep(for: .seconds(0.8))
            snap(out, "02-projects")
            model.selection = .home

            guard let path = env["AUDRA_DEBUG_IMPORT"] else { return }
            model.importFiles([URL(fileURLWithPath: path)])
            var tick = 0
            while let recording = model.selectedRecording, recording.status.isActive, tick < 400 {
                try? await Task.sleep(for: .seconds(0.5))
                tick += 1
                if tick == 6 { snap(out, "03-processing") }
            }
            try? await Task.sleep(for: .seconds(1.5))
            model.player?.seek(to: 32)
            try? await Task.sleep(for: .seconds(1))
            snap(out, "04-results")
            model.resultMode = .summary
            try? await Task.sleep(for: .seconds(1))
            snap(out, "05-summary")
            model.resultMode = .full
            let current = model.selection
            model.selection = .transcriptions
            try? await Task.sleep(for: .seconds(1))
            snap(out, "05b-transcriptions")
            model.selection = current
            try? await Task.sleep(for: .seconds(0.5))

            guard let recording = model.selectedRecording, recording.status == .completed else {
                log("recording not completed"); return
            }
            log("words: \(recording.decodeSegments().compactMap(\.words).count) segments with word timing")
            model.editInNewProject(recording)
            for _ in 0..<40 where model.editor == nil { try? await Task.sleep(for: .seconds(0.25)) }
            guard let session = model.editor else { log("editor did not open"); return }
            try? await Task.sleep(for: .seconds(2.5))
            session.seek(to: 14)
            try? await Task.sleep(for: .seconds(1))
            snap(out, "06-editor-transcript")
            await keyTest(session: session)
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) {
                window.toggleFullScreen(nil)
                try? await Task.sleep(for: .seconds(2.5))
                log("full screen: \(WindowState.shared.isFullScreen)")
                snap(out, "06b-fullscreen")
                window.toggleFullScreen(nil)
                try? await Task.sleep(for: .seconds(2.5))
                log("after exit: \(WindowState.shared.isFullScreen)")
            }

            // Select a clip to show the inspector.
            if let clip = session.project.tracks.first(where: { $0.kind == .video })?.clips.first {
                session.selection = [clip.id]
            }
            session.leftTab = .media
            try? await Task.sleep(for: .seconds(1))
            snap(out, "07-editor-media-inspector")

            // Transcript-based edit: remove words 4…12.
            let before = session.duration
            if let mediaID = session.transcriptMediaID {
                session.transcriptSelection = TranscriptSelection(mediaID: mediaID, anchor: 4, head: 12)
                session.leftTab = .transcript
                try? await Task.sleep(for: .seconds(1))
                snap(out, "08-transcript-selection")
                session.removeSelectedTranscript()
                try? await Task.sleep(for: .seconds(1))
                log(String(format: "duration %.2f → %.2f after transcript cut", before, session.duration))
                snap(out, "09-after-cut")
                session.generateSubtitles(for: mediaID)
            }
            session.seek(to: 0)
            session.addText(.title("Reunião semanal"), duration: 3)
            session.selection = []
            session.leftTab = .text
            try? await Task.sleep(for: .seconds(1))
            snap(out, "10-subtitles-title")
            if let text = session.project.tracks.first(where: { $0.kind == .text && $0.role == .standard })?.clips.first {
                session.selection = [text.id]
            }
            session.leftTab = .ai
            try? await Task.sleep(for: .seconds(1))
            snap(out, "11-ai-text-inspector")
            session.selection = []
            session.leftTab = .tools

            session.togglePlayback()
            try? await Task.sleep(for: .seconds(2))
            log(String(format: "playhead after 2 s of playback: %.2f (playing=%@)", session.currentTime, session.isPlaying ? "yes" : "no"))
            session.pause()
            snap(out, "12-tools-playing")

            session.undo()
            session.undo()
            log("undo → \(session.undoName ?? "-"), redo available: \(session.redoName ?? "-")")
            session.redo()
            session.redo()

            var settings = ExportSettings()
            settings.resolution = .hd
            let target = out.appendingPathComponent("export.mp4")
            session.startExport(settings, to: target)
            model.exportRequest += 1
            try? await Task.sleep(for: .seconds(1))
            snap(out, "13-export")
            while session.exportJob?.state == .running { try? await Task.sleep(for: .seconds(0.5)) }
            log("export state: \(String(describing: session.exportJob?.state)) → \(target.path)")
            try? await Task.sleep(for: .seconds(0.6))
            snap(out, "14-export-done")
            NSApp.keyWindow?.attachedSheet.map { NSApp.keyWindow?.endSheet($0) }
            session.exportJob = nil

            session.flushSave()
            let projectID = session.project.id
            model.closeEditor()
            model.selection = .projects
            try? await Task.sleep(for: .seconds(1.2))
            snap(out, "15-projects-after")
            model.openProject(projectID)
            try? await Task.sleep(for: .seconds(2))
            log("reopened: \(model.editor?.project.tracks.map { "\($0.name)=\($0.clips.count)" } ?? [])")
            snap(out, "16-reopened")
            log("done")
        }
    }

    static weak var model: AppModel?

    private static func shot(_ out: URL, _ name: String, window: NSWindow? = nil) {
        guard let window = window ?? NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 900 }),
              let image = composited(window) else { log("shot failed: \(name)"); return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: out.appendingPathComponent("\(name).png"))
        log("shot \(name)")
    }

    /// Website screenshots: drives the real app through import → transcript → summary → editor → export.
    static func marketing(model: AppModel, out: URL, media: URL) async {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Localization.shared.use("pt")
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) else { return }
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.center()
        try? await Task.sleep(for: .seconds(1))

        model.importFiles([media])
        while let recording = model.selectedRecording, recording.status.isActive {
            try? await Task.sleep(for: .seconds(0.5))
        }
        guard let recording = model.selectedRecording, recording.status == .completed else { log("transcription failed"); return }
        try? await Task.sleep(for: .seconds(1.5))
        model.player?.seek(to: 21.5)
        try? await Task.sleep(for: .seconds(1.5))
        shot(out, "results")
        model.resultMode = .summary
        try? await Task.sleep(for: .seconds(1.2))
        shot(out, "summary")
        model.resultMode = .full

        model.editInNewProject(recording)
        for _ in 0..<40 where model.editor == nil { try? await Task.sleep(for: .seconds(0.25)) }
        guard let session = model.editor else { return }
        try? await Task.sleep(for: .seconds(2))
        if let mediaID = session.transcriptMediaID {
            session.generateSubtitles(for: mediaID)
        }
        session.seek(to: 0)
        session.addText(.title("Podcast em 5 passos"), duration: 4)
        session.pixelsPerSecond = 22
        session.scrollX = 0
        session.selection = []
        session.seek(to: 15.2)
        model.notice = nil
        try? await Task.sleep(for: .seconds(1.5))
        if let mediaID = session.transcriptMediaID {
            session.transcriptSelection = TranscriptSelection(mediaID: mediaID, anchor: 22, head: 33)
        }
        session.leftTab = .transcript
        model.notice = nil
        try? await Task.sleep(for: .seconds(1.5))
        shot(out, "editor")

        session.transcriptSelection = nil
        if let clip = session.project.tracks.first(where: { $0.kind == .video })?.clips.first {
            session.selection = [clip.id]
        }
        session.leftTab = .ai
        session.seek(to: 31)
        try? await Task.sleep(for: .seconds(1.5))
        shot(out, "editor-ai")

        if let text = session.project.tracks.first(where: { $0.kind == .text && $0.role == .standard })?.clips.first {
            session.selection = [text.id]
        }
        session.leftTab = .text
        session.seek(to: 1.6)
        try? await Task.sleep(for: .seconds(1.5))
        shot(out, "editor-text")

        session.selection = []
        model.exportRequest += 1
        try? await Task.sleep(for: .seconds(1.5))
        if let sheet = window.attachedSheet { shot(out, "export-sheet", window: sheet); window.endSheet(sheet) }
        try? await Task.sleep(for: .seconds(0.5))

        session.flushSave()
        model.closeEditor()
        model.selection = .home
        try? await Task.sleep(for: .seconds(1.5))
        shot(out, "home")
        model.selection = .transcriptions
        try? await Task.sleep(for: .seconds(1.2))
        shot(out, "transcriptions")
        model.selection = .projects
        try? await Task.sleep(for: .seconds(1.2))
        shot(out, "projects")
        log("marketing done")
    }

    private static func key(_ chars: String, code: UInt16, window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: chars,
                                            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                NSApp.sendEvent(event)
            }
        }
    }

    private static func findTextField(_ view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews { if let f = findTextField(sub) { return f } }
        return nil
    }

    /// Space must type into a focused text field, and play/pause otherwise.
    static func keyTest(session: EditorSession) async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }),
              let root = window.contentView else { return }
        window.makeKeyAndOrderFront(nil)
        if let field = findTextField(root) {
            window.makeFirstResponder(field)
            try? await Task.sleep(for: .milliseconds(300))
            let before = (window.firstResponder as? NSTextView)?.string ?? field.stringValue
            key(" ", code: 49, window: window)
            try? await Task.sleep(for: .milliseconds(300))
            let after = (window.firstResponder as? NSTextView)?.string ?? field.stringValue
            log("typing: '\(before)' → '\(after)', playing=\(session.isPlaying)")
            (window.firstResponder as? NSTextView)?.string = before
            window.makeFirstResponder(nil)
        }
        try? await Task.sleep(for: .milliseconds(300))
        key(" ", code: 49, window: window)
        try? await Task.sleep(for: .milliseconds(600))
        log("space without focus → playing=\(session.isPlaying)")
        session.pause()
    }

    /// Offscreen SwiftUI render of individual screens/panels (AppKit-backed controls appear as placeholders).
    static func render(_ dir: URL, _ name: String) {
        guard let model else { return }
        var parts: [(String, AnyView, CGSize)] = []
        if let editor = model.editor {
            parts = [
                ("left", AnyView(EditorSidebar(session: editor)), CGSize(width: 310, height: 820)),
                ("inspector", AnyView(InspectorView(session: editor)), CGSize(width: 292, height: 820)),
                ("timeline", AnyView(TimelinePanel(session: editor)), CGSize(width: 1440, height: 320)),
            ]
        } else {
            switch model.selection {
            case .projects: parts = [("main", AnyView(ProjectsView()), CGSize(width: 1180, height: 860))]
            case .recording: parts = [("main", AnyView(RecordingScreenPreview()), CGSize(width: 1180, height: 860))]
            default: parts = [("main", AnyView(HomeView()), CGSize(width: 1180, height: 860))]
            }
        }
        for (suffix, view, size) in parts {
            let root = view
                .environment(model)
                .modelContainer(model.container)
                .environment(\.colorScheme, .dark)
                .tint(Theme.accent)
                .frame(width: size.width, height: size.height)
                .background(Theme.canvas)
            let renderer = ImageRenderer(content: root)
            renderer.scale = 1.5
            if let image = renderer.cgImage {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
    }

    private typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// Captures the composited window (what is really on screen) through the window server.
    static func composited(_ window: NSWindow) -> CGImage? {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(symbol, to: WindowImageFn.self)
        // kCGWindowListOptionIncludingWindow = 1 << 3, kCGWindowImageBoundsIgnoreFraming = 1 << 0
        return fn(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue()
    }

    static func snap(_ dir: URL, _ name: String) {
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }), let image = composited(window) {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("\(name).png"))
            return
        }
        render(dir, name)
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 500 }),
              let view = window.contentView else { return }
        // Layer render captures SwiftUI/Metal-backed content that cacheDisplay misses.
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        if let layer = view.layer,
           let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                               bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.scaleBy(x: scale, y: scale)
            if !view.isFlipped {} else { ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1) }
            layer.render(in: ctx)
            if let image = ctx.makeImage() {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("\(name).png"))
                return
            }
        }
    }
}
private struct RecordingScreenPreview: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let recording = model.selectedRecording {
            switch recording.status {
            case .completed: ResultsView(recording: recording)
            case .failed, .cancelled: FailureView(recording: recording)
            default: ProcessingView(recording: recording)
            }
        }
    }
}
#endif
