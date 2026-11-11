import AppKit
import SwiftUI

/// The editing workspace: media/transcript panel, program monitor, inspector and timeline.
struct EditorView: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: EditorSession
    @State private var leftWidth: CGFloat = 310
    @State private var rightWidth: CGFloat = 292
    @State private var timelineHeight: CGFloat = 300
    @State private var keyMonitor = EditorKeyMonitor()
    @State private var showExport = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            EditorTopBar(session: session, showExport: $showExport)
            workspace
        }
        .background(Theme.canvas)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(Motion.smooth) { appeared = true }
            keyMonitor.start { handleKey($0) }
        }
        .onDisappear { keyMonitor.stop() }
        .sheet(isPresented: $showExport) { ExportSheet(session: session) }
        .onChange(of: app.exportRequest) { _, _ in showExport = true }
        .onChange(of: app.processing.activeCount) { _, _ in session.refreshTranscripts() }
    }

    private var workspace: some View {
        GeometryReader { geo in
            let left = min(max(leftWidth, 240), geo.size.width * 0.34)
            let right = min(max(rightWidth, 250), geo.size.width * 0.3)
            let timeline = min(max(timelineHeight, 170), max(170, geo.size.height - 250))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if session.showLeftPanel && !session.theaterMode {
                        EditorSidebar(session: session)
                            .frame(width: left)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        ResizeHandle(axis: .horizontal) { leftWidth = left + $0 }
                    }
                    MonitorView(session: session)
                        .frame(minWidth: 320)
                    if session.showInspector && !session.theaterMode {
                        ResizeHandle(axis: .horizontal) { rightWidth = right - $0 }
                        InspectorView(session: session)
                            .frame(width: right)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                if !session.theaterMode {
                    ResizeHandle(axis: .vertical) { timelineHeight = timeline - $0 }
                    TimelinePanel(session: session)
                        .frame(height: timeline)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Theme.canvas)
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        guard app.editor === session, event.window?.isKeyWindow == true else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command), shift = flags.contains(.shift)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if command {
            switch chars {
            case "z": shift ? session.redo() : session.undo(); return true
            case "b": session.splitAtPlayhead(); return true
            case "d": session.duplicateSelection(); return true
            case "a": session.selectAll(); return true
            case "e": showExport = true; return true
            case "=", "+": zoom(1.5); return true
            case "-": zoom(1 / 1.5); return true
            default: return false
            }
        }
        switch event.keyCode {
        case 49: session.togglePlayback(); return true                       // space
        case 123: shift ? session.jump(by: -1) : session.step(frames: -1); return true
        case 124: shift ? session.jump(by: 1) : session.step(frames: 1); return true
        case 51, 117:                                                        // delete
            if !session.selection.isEmpty { session.deleteSelection(ripple: shift); return true }
            if session.transcriptSelection != nil { session.removeSelectedTranscript(); return true }
            return false
        case 115: session.seek(to: 0); return true                            // home
        case 119: session.seek(to: session.duration); return true            // end
        case 53:                                                              // esc
            if session.theaterMode { withAnimation(Motion.smooth) { session.theaterMode = false }; return true }
            session.selection = []
            session.transcriptSelection = nil
            return true
        default: break
        }
        switch chars {
        case "n": session.snapping.toggle(); return true
        case "m": session.addMarker(); return true
        case "f": withAnimation(Motion.smooth) { session.theaterMode.toggle() }; return true
        case "j": session.jump(by: -5); return true
        case "l": session.jump(by: 5); return true
        case "k": session.pause(); return true
        case "s" where !shift: session.splitAtPlayhead(); return true
        default: return false
        }
    }

    private func zoom(_ factor: Double) {
        withAnimation(Motion.snappy) { session.zoom(by: factor) }
    }
}

private struct EditorTopBar: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: EditorSession
    @Binding var showExport: Bool

    var body: some View {
        TopBar {
            Button { app.closeEditor() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(IconButtonStyle(size: 28))
                .help(tr("Voltar aos projetos (o projeto é salvo automaticamente)"))
            Button(tr("Projetos")) { app.selection = .projects; app.closeEditor() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
            Text("/").font(.system(size: 13)).foregroundStyle(Theme.textQuaternary)
            ProjectTitleField(session: session)
        } center: {
            HStack(spacing: 2) {
                Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(IconButtonStyle(size: 28))
                    .help(session.undoName.map { tr("Desfazer %@ (⌘Z)", $0) } ?? tr("Nada para desfazer"))
                    .disabled(session.undoName == nil)
                Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(IconButtonStyle(size: 28))
                    .help(session.redoName.map { tr("Refazer %@ (⇧⌘Z)", $0) } ?? tr("Nada para refazer"))
                    .disabled(session.redoName == nil)
            }
            .padding(2)
            .background(Theme.base, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline))
        } trailing: {
            Button {
                withAnimation(Motion.smooth) { session.showLeftPanel.toggle() }
            } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(IconButtonStyle(isActive: session.showLeftPanel, size: 30))
                .help(tr("Painel de mídia e transcrição"))
            Button {
                withAnimation(Motion.smooth) { session.showInspector.toggle() }
            } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(IconButtonStyle(isActive: session.showInspector, size: 30))
                .help(tr("Propriedades"))
            Button { showExport = true } label: {
                Label(tr("Exportar"), systemImage: "arrow.up.circle")
            }
            .buttonStyle(AudraButtonStyle(kind: .primary))
            .help(tr("Exportar vídeo (⌘E)"))
            .padding(.leading, 4)
        }
    }
}

private struct ProjectTitleField: View {
    @Bindable var session: EditorSession
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(tr("Nome do projeto"), text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 80, maxWidth: 260)
                .fixedSize()
                .focused($focused)
                .onSubmit { session.rename(draft); focused = false }
                .onAppear { draft = session.project.name }
                .onChange(of: session.project.name) { _, new in if !focused { draft = new } }
                .onChange(of: focused) { _, isFocused in if !isFocused { session.rename(draft) } }
            SaveIndicator(state: session.saveState)
        }
    }
}

private struct SaveIndicator: View {
    let state: SaveState

    var body: some View {
        let (color, text): (Color, String) = switch state {
        case .saved: (Theme.success, tr("Salvo"))
        case .pending, .saving: (Theme.accentBright, tr("Salvando"))
        case .failed: (Theme.warning, tr("Falha ao salvar"))
        }
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .contentTransition(.opacity)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.textTertiary)
        .animation(Motion.fade, value: text)
        .help({ if case .failed(let message) = state { return message } else { return tr("Salvo automaticamente") } }())
        .accessibilityElement(children: .combine)
    }
}
