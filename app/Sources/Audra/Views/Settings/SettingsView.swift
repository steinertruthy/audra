import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, transcription, summary, storage, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: tr("Geral")
        case .transcription: tr("Transcrição")
        case .summary: tr("Resumo")
        case .storage: tr("Armazenamento")
        case .about: tr("Sobre")
        }
    }
    var symbol: String {
        switch self {
        case .general: "globe"
        case .transcription: "waveform"
        case .summary: "sparkles"
        case .storage: "internaldrive"
        case .about: "info.circle"
        }
    }
}

/// Settings window, styled like the rest of the app: side navigation and grouped cards.
struct SettingsView: View {
    @State private var pane: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    AppMark(size: 20)
                    Text(tr("Ajustes")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
                ForEach(SettingsPane.allCases) { item in
                    Button { withAnimation(Motion.snappy) { pane = item } } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(pane == item ? Theme.accentBright : Theme.textTertiary)
                                .frame(width: 18)
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(pane == item ? Theme.textPrimary : Theme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(pane == item ? Theme.control : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.top, 46)
            .padding(.horizontal, 10)
            .frame(width: 190)
            .background(Theme.base)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(pane.title)
                        .font(.audraTitle)
                        .tracking(-0.3)
                        .foregroundStyle(Theme.textPrimary)
                    switch pane {
                    case .general: GeneralPane()
                    case .transcription: TranscriptionPane()
                    case .summary: SummaryPane()
                    case .storage: StoragePane()
                    case .about: AboutPane()
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(pane)
                .transition(.opacity)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 720)
        .frame(minHeight: 552, maxHeight: .infinity)
        .background(Theme.canvas)
        .background(SettingsWindowStyler())
        .ignoresSafeArea()
    }
}

/// Makes the settings window's title bar transparent so the custom layout runs edge to edge.
private struct SettingsWindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { StylerView() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class StylerView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            style(window)
            // SwiftUI finishes configuring the settings window after this; style it again then.
            DispatchQueue.main.async { [weak self] in self?.window.map(self!.style) }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let window = self?.window { self?.style(window) } }
            }
        }

        private func style(_ window: NSWindow) {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(Theme.canvas)
            window.toolbar = nil
            window.titlebarSeparatorStyle = .none
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionLabel(title).padding(.leading, 2) }
            VStack(spacing: 0) { content }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.stroke))
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var divider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 14) }
        }
    }
}

private struct StatusText: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Theme.success : Theme.warning).frame(width: 6, height: 6)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @State private var localization = Localization.shared
    @State private var initialCode = Localization.shared.code

    var body: some View {
        Card(title: tr("Idioma da interface"),
             footer: tr("Por padrão, o Audra usa o idioma do macOS (português, inglês ou espanhol; outros idiomas usam inglês). O idioma da transcrição é escolhido separadamente.")) {
            ForEach(InterfaceLanguage.allCases) { option in
                Button {
                    localization.preference = option
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: localization.preference == option ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(localization.preference == option ? Theme.accentBright : Theme.textQuaternary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.nativeName).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                            if option == .system {
                                Text(tr("Atualmente: %@", InterfaceLanguage(rawValue: Localization.resolve(.system))?.nativeName ?? "English"))
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if option != InterfaceLanguage.allCases.last {
                            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 14)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        if localization.code != initialCode {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(Theme.accentBright)
                Text(tr("A interface já mudou. Os menus padrão do macOS (como Editar e Janela) mudam ao reabrir o app."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(tr("Reabrir")) { Relauncher.relaunch() }
                    .buttonStyle(AudraButtonStyle(kind: .secondary))
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// Restarts the app (used after changing the interface language so system menus follow).
enum Relauncher {
    @MainActor static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        AppDelegate.model?.editor?.flushSave()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Transcription

private struct TranscriptionPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PrefKey.language) private var language = "auto"
    @State private var languages = SpeechLanguages.shared
    @State private var changed = false

    var body: some View {
        Card(title: tr("Idioma"),
             footer: tr("Vale para as próximas transcrições. Para refazer uma transcrição já pronta em outro idioma, abra-a e use o seletor de idioma no cabeçalho.")) {
            Row(title: tr("Idioma falado"),
                detail: language == "auto" ? tr("Detecta automaticamente, priorizando o português do Brasil") : nil,
                divider: false) {
                Menu {
                    Button(tr("Detectar automaticamente")) { set("auto") }
                    Divider()
                    ForEach(languages.featuredAvailable, id: \.self) { id in
                        Button(label(id)) { set(id) }
                    }
                    if !languages.others.isEmpty {
                        Menu(tr("Outros idiomas")) {
                            ForEach(languages.others, id: \.self) { id in Button(label(id)) { set(id) } }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(language == "auto" ? tr("Automático") : LanguageNames.name(for: language))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.stroke))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        if changed {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                Text(language == "auto"
                     ? tr("Pronto. Novos arquivos terão o idioma detectado automaticamente.")
                     : tr("Pronto. Novos arquivos serão transcritos em %@.", LanguageNames.name(for: language)))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let recording = model.selectedRecording, recording.status == .completed,
                   recording.localeIdentifier != language, language != "auto" {
                    Button(tr("Aplicar a “%@”", recording.title)) { model.retranscribe(recording, language: language) }
                        .buttonStyle(AudraButtonStyle(kind: .secondary))
                }
            }
            .font(.system(size: 12))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        Card(title: tr("Reconhecimento"),
             footer: tr("O áudio nunca sai do seu Mac. Na primeira vez que um idioma é usado, o macOS baixa o modelo de fala; depois, tudo funciona offline. A identificação de participantes ainda não é suportada pelo motor nativo.")) {
            Row(title: tr("Motor"), detail: tr("Apple SpeechAnalyzer, no dispositivo")) {
                StatusText(ok: SpeechEngine.isAvailable, text: SpeechEngine.isAvailable ? tr("Disponível") : tr("Indisponível"))
            }
            Row(title: tr("Idiomas instalados"), divider: false) {
                Text(languages.installed.isEmpty ? tr("Nenhum ainda") : languages.installed.sorted().map { LanguageNames.name(for: $0) }.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .task { await languages.load() }
    }

    private func set(_ id: String) {
        language = id
        withAnimation(Motion.snappy) { changed = true }
    }

    private func label(_ id: String) -> String {
        LanguageNames.name(for: id) + (languages.installed.contains(id) ? " ✓" : "")
    }
}

// MARK: - Summary

private struct SummaryPane: View {
    @AppStorage(PrefKey.autoSummarize) private var autoSummarize = true
    @AppStorage(PrefKey.summaryProvider) private var provider = SummaryProvider.apple.rawValue
    @AppStorage(PrefKey.summaryDetail) private var detail = SummaryDetail.standard.rawValue
    @AppStorage(PrefKey.claudeConsent) private var consent = false
    @AppStorage(PrefKey.claudeModel) private var claudeModel = ClaudeSummarizer.defaultModel
    @State private var apiKey = ""
    @State private var keySaved = false

    var body: some View {
        Card {
            Row(title: tr("Gerar resumo automaticamente"), detail: tr("Ao terminar cada transcrição")) {
                Toggle("", isOn: $autoSummarize).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            Row(title: tr("Nível de detalhe"), divider: false) {
                PillTabs(selection: $detail, items: SummaryDetail.allCases.map { .init(value: $0.rawValue, title: $0.label) })
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(tr("Modelo de linguagem")).padding(.leading, 2)
            HStack(spacing: 10) {
                ProviderCard(selected: provider == SummaryProvider.apple.rawValue, symbol: "apple.logo",
                             title: tr("Apple Intelligence"), detail: tr("No dispositivo · privado · offline"),
                             status: AppleIntelligenceSummarizer.availabilityMessage == nil ? nil : tr("Indisponível")) {
                    provider = SummaryProvider.apple.rawValue
                }
                ProviderCard(selected: provider == SummaryProvider.claude.rawValue, symbol: "cloud",
                             title: tr("Claude"), detail: tr("Anthropic API · envia só o texto"),
                             status: consent && keySaved ? nil : tr("Requer chave")) {
                    provider = SummaryProvider.claude.rawValue
                }
            }
            if provider == SummaryProvider.apple.rawValue, let message = AppleIntelligenceSummarizer.availabilityMessage {
                Text(message).font(.system(size: 11.5)).foregroundStyle(Theme.warning).padding(.horizontal, 2)
            }
        }

        if provider == SummaryProvider.claude.rawValue {
            Card(title: tr("Anthropic"),
                 footer: tr("Somente o texto transcrito é enviado, e apenas com a permissão acima ativada. A chave fica no Keychain do macOS.")) {
                Row(title: tr("Permitir envio das transcrições"), detail: tr("Necessário para usar o Claude")) {
                    Toggle("", isOn: $consent).toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                Row(title: tr("Chave da API")) {
                    HStack(spacing: 6) {
                        SecureField("sk-ant-…", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .padding(.horizontal, 8)
                            .frame(width: 200, height: 28)
                            .background(Theme.base, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.stroke))
                            .onSubmit(saveKey)
                        Button(keySaved ? tr("Salva") : tr("Salvar"), action: saveKey)
                            .buttonStyle(AudraButtonStyle(kind: keySaved ? .secondary : .primary))
                            .disabled(apiKey.isEmpty || keySaved)
                    }
                }
                Row(title: tr("Modelo"), divider: false) {
                    TextField("", text: $claudeModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 200)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        Color.clear.frame(height: 0)
            .onAppear { if let key = Keychain.read() { apiKey = key; keySaved = true } }
            .onChange(of: apiKey) { keySaved = false }
            .animation(Motion.snappy, value: provider)
    }

    private func saveKey() {
        keySaved = Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct ProviderCard: View {
    let selected: Bool
    let symbol: String
    let title: String
    let detail: String
    let status: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selected ? Theme.accentBright : Theme.textSecondary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Theme.accentBright : Theme.textQuaternary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                }
                if let status {
                    Text(status).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.warning)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(selected ? Theme.accentSoft : hovering ? Theme.elevated : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.7) : Theme.stroke))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: selected)
    }
}

// MARK: - Storage

private struct StoragePane: View {
    @State private var audioCache: Int64 = 0
    @State private var editorCache: Int64 = 0
    @State private var projects: Int64 = 0

    var body: some View {
        Card(title: tr("Biblioteca"), footer: tr("Os vídeos originais nunca são copiados nem alterados. Ficam guardados apenas transcrições, resumos, projetos e, para formatos como MKV, uma cópia compatível para reprodução.")) {
            Row(title: tr("Transcrições e projetos"), detail: AppPaths.support.path) {
                Button(tr("Mostrar no Finder")) { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.support]) }
                    .buttonStyle(AudraButtonStyle(kind: .secondary))
            }
            Row(title: tr("Projetos de edição"), divider: false) {
                Text(size(projects)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
        }
        Card(title: tr("Cache"), footer: tr("Áudio temporário, miniaturas e formas de onda são recriados quando necessário.")) {
            Row(title: tr("Áudio temporário")) {
                cacheControls(audioCache) { try? FileManager.default.removeItem(at: AppPaths.audioCache) }
            }
            Row(title: tr("Miniaturas e formas de onda"), divider: false) {
                cacheControls(editorCache) {
                    let files = (try? FileManager.default.contentsOfDirectory(at: AppPaths.editorCache, includingPropertiesForKeys: nil)) ?? []
                    for file in files where !file.lastPathComponent.hasPrefix("base-") { try? FileManager.default.removeItem(at: file) }
                }
            }
        }
        Card(title: tr("Formatos extras")) {
            Row(title: tr("FFmpeg"), detail: tr("Usado apenas para MKV, WebM, AVI e similares"), divider: false) {
                StatusText(ok: FFmpegBridge.isAvailable, text: FFmpegBridge.isAvailable ? tr("Encontrado") : tr("Não instalado"))
            }
        }
        Color.clear.frame(height: 0).onAppear(perform: refresh)
    }

    private func cacheControls(_ bytes: Int64, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(size(bytes)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textSecondary)
            Button(tr("Limpar")) { clear(); refresh() }
                .buttonStyle(AudraButtonStyle(kind: .secondary))
                .disabled(bytes == 0)
        }
    }

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    private func refresh() {
        audioCache = folderSize(AppPaths.audioCache)
        editorCache = folderSize(AppPaths.editorCache)
        projects = folderSize(AppPaths.projects)
    }

    private func folderSize(_ url: URL) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        HStack(spacing: 16) {
            AppMark(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Audra")).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(tr("Versão %@", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        Card(title: tr("Privacidade")) {
            Row(title: tr("Transcrição"), detail: tr("No dispositivo, com o motor de fala do macOS")) { StatusText(ok: true, text: tr("Local")) }
            Row(title: tr("Resumo"), detail: tr("Apple Intelligence no dispositivo; Claude só com sua permissão")) { StatusText(ok: true, text: tr("Local por padrão")) }
            Row(title: tr("Edição e exportação"), detail: tr("AVFoundation, Core Image e VideoToolbox"), divider: false) { StatusText(ok: true, text: tr("Local")) }
        }
    }
}
