import SwiftUI

/// Locales offered by the on-device recognizer, most common first.
@MainActor
@Observable
final class SpeechLanguages {
    static let shared = SpeechLanguages()
    private(set) var supported: [String] = []
    private(set) var installed: Set<String> = []
    private var loaded = false

    static let featured = ["pt-BR", "en-US", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-PT", "en-GB", "ja-JP", "zh-CN"]

    func load() async {
        guard !loaded else { return }
        loaded = true
        let all = await SpeechEngine.supportedLocales().map { $0.identifier(.bcp47) }
        let local = await SpeechEngine.installedLocales().map { $0.identifier(.bcp47) }
        installed = Set(local)
        supported = all.sorted { LanguageNames.name(for: $0) < LanguageNames.name(for: $1) }
    }

    var featuredAvailable: [String] { Self.featured.filter { supported.isEmpty || supported.contains($0) } }
    var others: [String] { supported.filter { !Self.featured.contains($0) } }
}

/// Header control: shows the transcript's language and re-transcribes in another one.
struct LanguageMenu: View {
    @Environment(AppModel.self) private var model
    let recording: Recording
    @State private var languages = SpeechLanguages.shared

    var body: some View {
        Menu {
            Section(tr("Transcrever novamente em")) {
                Button(tr("Detectar automaticamente")) { model.retranscribe(recording, language: "auto") }
                ForEach(languages.featuredAvailable, id: \.self) { id in
                    Button(label(id)) { model.retranscribe(recording, language: id) }
                        .disabled(id == recording.localeIdentifier && recording.status == .completed)
                }
                if !languages.others.isEmpty {
                    Menu(tr("Outros idiomas")) {
                        ForEach(languages.others, id: \.self) { id in
                            Button(label(id)) { model.retranscribe(recording, language: id) }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                Text(recording.localeIdentifier.map { LanguageNames.name(for: $0) } ?? tr("Idioma"))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Theme.control.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(recording.status.isActive || !recording.sourceExists)
        .help(tr("Idioma da transcrição. Escolha outro para transcrever o arquivo novamente."))
        .task { await languages.load() }
    }

    private func label(_ id: String) -> String {
        LanguageNames.name(for: id) + (languages.installed.contains(id) ? "" : tr(" (baixa o modelo)"))
    }
}
