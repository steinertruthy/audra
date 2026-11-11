import SwiftData
import SwiftUI

/// Root: the library or the editor, each with its own top bar, and an animated hand-off.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            if let editor = model.editor {
                EditorView(session: editor)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.99)), removal: .opacity))
            } else {
                LibraryShell()
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: model.editor == nil)
        .background(Theme.canvas)
        .background(WindowChrome())
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { NoticeBanner(message: $model.notice) }
        .animation(Motion.bouncy, value: model.notice)
    }
}

private struct LibraryShell: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            LibraryTopBar()
            DetailRouter()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.canvas)
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter(MediaInspector.isAccepted)
            guard !accepted.isEmpty else {
                model.notice = tr("Arraste arquivos de vídeo ou áudio (MP4, MOV, MKV, M4A…).")
                return false
            }
            model.importFiles(accepted)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay { if isDropTargeted { DropOverlay() } }
        .animation(Motion.fade, value: isDropTargeted)
    }
}

private struct LibraryTopBar: View {
    @Environment(AppModel.self) private var model
    @Query private var recordings: [Recording]
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        TopBar {
            HStack(spacing: 9) {
                AppMark(size: 22)
                Text(tr("Audra"))
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.trailing, 14)
            NavTabs(selection: model.selection?.tab,
                    items: [
                        .init(value: SidebarItem.home, title: tr("Início")),
                        .init(value: .transcriptions, title: tr("Transcrições"), count: recordings.count),
                        .init(value: .projects, title: tr("Projetos"), count: model.projects.projects.count),
                    ]) { model.selection = $0 }
        } trailing: {
            SearchField(text: $model.search, prompt: tr("Buscar nas transcrições"), focus: $searchFocused)
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle(size: 30))
            .help(tr("Ajustes (⌘,)"))
            Menu {
                Button(tr("Transcrever Vídeos…"), systemImage: "waveform.badge.plus") { model.presentImporter() }
                Button(tr("Novo Projeto de Edição"), systemImage: "film.stack") { model.newProject() }
            } label: {
                Label(tr("Novo"), systemImage: "plus")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tr("Transcrever vídeos (⌘O) ou criar projeto (⇧⌘N)"))
        }
        .onChange(of: model.search) { _, text in
            if !text.isEmpty, model.selection?.tab != .transcriptions { model.selection = .transcriptions }
        }
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
        .task {
            // Don't start with the cursor in the search field.
            try? await Task.sleep(for: .milliseconds(50))
            searchFocused = false
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

private struct DetailRouter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.selection {
            case .recording(let id):
                if let recording = model.recording(id) {
                    RecordingScreen(recording: recording)
                        .id(id)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    TranscriptionsView()
                }
            case .transcriptions:
                TranscriptionsView().transition(.opacity)
            case .projects:
                ProjectsView().transition(.opacity)
            default:
                HomeView().transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: model.selection)
    }
}

/// Picks the right state for a recording: queued/processing, failed, or finished.
struct RecordingScreen: View {
    @Environment(AppModel.self) private var model
    let recording: Recording

    var body: some View {
        Group {
            switch recording.status {
            case .completed:
                ResultsView(recording: recording)
                    .transition(.opacity)
            case .failed, .cancelled:
                VStack(spacing: 0) {
                    RecordingHeader(recording: recording) { LanguageMenu(recording: recording) }
                    FailureView(recording: recording)
                }
            default:
                VStack(spacing: 0) {
                    RecordingHeader(recording: recording) { EmptyView() }
                    ProcessingView(recording: recording)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: recording.status)
    }
}

/// Breadcrumb header for a recording: back, title, metadata and contextual actions.
struct RecordingHeader<Actions: View>: View {
    @Environment(AppModel.self) private var model
    let recording: Recording
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Button { model.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .keyboardShortcut("[", modifiers: .command)
            .help(tr("Voltar (⌘[)"))
            VStack(alignment: .leading, spacing: 1) {
                Text(recording.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var subtitle: String {
        var parts: [String] = []
        if recording.duration > 0 { parts.append(TimeFormat.clock(recording.duration)) }
        parts.append(recording.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Localization.shared.locale)))
        return parts.joined(separator: " · ")
    }
}

private struct DropOverlay: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.canvas.opacity(0.86))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [8, 7]))
                .padding(24)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Theme.accentBright)
                    .scaleEffect(pulse ? 1.06 : 1)
                Text(tr("Solte para transcrever"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(tr("Processado localmente no seu Mac"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
    }
}

private struct NoticeBanner: View {
    @Binding var message: String?

    var body: some View {
        if let message {
            HStack(spacing: 10) {
                Circle().fill(Theme.accentBright).frame(width: 6, height: 6)
                Text(message).font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary)
                Button { self.message = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(IconButtonStyle(size: 20))
                    .accessibilityLabel(tr("Fechar aviso"))
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 7)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.strokeStrong))
            .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: message) {
                try? await Task.sleep(for: .seconds(4.5))
                withAnimation(Motion.smooth) { self.message = nil }
            }
        }
    }
}
