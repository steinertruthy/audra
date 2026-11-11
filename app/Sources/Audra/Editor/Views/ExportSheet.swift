import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Bindable var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ExportSettings()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                    .frame(width: 36, height: 36)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Exportar vídeo")).font(.audraHeadline).foregroundStyle(Theme.textPrimary)
                    Text("\(session.project.name) · \(TimeFormat.clock(session.duration))")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(20)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ZStack {
                if let job = session.exportJob {
                    ExportProgressView(job: job, onDone: { session.exportJob = nil; dismiss() },
                                       onRetry: { session.exportJob = nil })
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    form.transition(.opacity)
                }
            }
            .animation(Motion.smooth, value: session.exportJob == nil)
        }
        .frame(width: 480)
        .background(Theme.elevated)
        .onAppear { settings.fps = session.project.canvas.fps }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Picker(tr("Formato"), selection: $settings.container) {
                    ForEach(ExportSettings.Container.allCases) { Text($0.label).tag($0) }
                }
                if !settings.container.isAudioOnly {
                    Picker(tr("Codificação"), selection: $settings.codec) {
                        ForEach(ExportSettings.Codec.allCases) { Text($0.label).tag($0) }
                    }
                    Picker(tr("Resolução"), selection: $settings.resolution) {
                        ForEach(ExportSettings.Resolution.allCases) { resolution in
                            let size = ExportSettings(resolution: resolution).renderSize(for: session.project.canvas)
                            Text(tr("%@ — %@×%@", resolution.label, Int(size.width), Int(size.height))).tag(resolution)
                        }
                    }
                    Picker(tr("Qualidade"), selection: $settings.quality) {
                        ForEach(ExportSettings.Quality.allCases) { Text($0.label).tag($0) }
                    }
                    Picker(tr("Quadros por segundo"), selection: $settings.fps) {
                        ForEach([24.0, 25, 30, 50, 60], id: \.self) { Text(tr("%@ fps", Int($0))).tag($0) }
                    }
                    Toggle(tr("Incluir áudio"), isOn: $settings.includeAudio)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(height: settings.container.isAudioOnly ? 110 : 300)

            HStack(spacing: 6) {
                Image(systemName: "cpu").foregroundStyle(Theme.accentBright)
                Text(tr("Tamanho estimado: %@ · codificação por hardware (VideoToolbox)", ByteCountFormatter.string(fromByteCount: settings.estimatedBytes(duration: session.duration, canvas: session.project.canvas), countStyle: .file)))
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 20)

            HStack {
                Button(tr("Cancelar")) { dismiss() }
                    .buttonStyle(AudraButtonStyle(kind: .ghost))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    chooseDestination()
                } label: {
                    Label(tr("Exportar…"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(AudraButtonStyle(kind: .primary, large: true))
                .keyboardShortcut(.defaultAction)
                .disabled(session.duration < 0.05)
            }
            .padding(20)
        }
        .animation(Motion.snappy, value: settings.container)
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.title = tr("Exportar vídeo")
        panel.nameFieldStringValue = "\(session.project.name).\(settings.container.rawValue)"
        panel.allowedContentTypes = [UTType(filenameExtension: settings.container.rawValue) ?? .movie]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        session.startExport(settings, to: url)
    }
}

private struct ExportProgressView: View {
    let job: ExportJob
    let onDone: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch job.state {
            case .running:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        PulseBars()
                        Text(tr("Renderizando…")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(Int(job.progress * 100))%")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.accentBright)
                            .contentTransition(.numericText())
                    }
                    AudraProgressBar(value: job.progress, height: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = context.date.timeIntervalSince(job.startedAt)
                        HStack {
                            Text(tr("Decorrido %@", TimeFormat.clock(elapsed)))
                            if job.progress > 0.05, elapsed > 2 {
                                Text(tr("· restam cerca de %@", TimeFormat.spoken(elapsed / job.progress * (1 - job.progress))))
                            }
                            Spacer()
                        }
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    }
                    Text(job.destination.lastPathComponent)
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Spacer()
                    Button(tr("Cancelar Exportação")) { job.cancel() }
                        .buttonStyle(AudraButtonStyle(kind: .destructive))
                }
            case .finished:
                result(symbol: "checkmark.circle.fill", color: Theme.success, title: tr("Exportação concluída"),
                       message: tr("%@ · %@ · em %@", job.destination.lastPathComponent, fileSize, TimeFormat.spoken(job.finishedAt.map { $0.timeIntervalSince(job.startedAt) } ?? 0)))
                HStack {
                    Button(tr("Mostrar no Finder")) { NSWorkspace.shared.activateFileViewerSelecting([job.destination]) }
                        .buttonStyle(AudraButtonStyle(kind: .secondary))
                    Button(tr("Abrir")) { NSWorkspace.shared.open(job.destination) }
                        .buttonStyle(AudraButtonStyle(kind: .secondary))
                    Spacer()
                    Button(tr("Concluído"), action: onDone)
                        .buttonStyle(AudraButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                result(symbol: "exclamationmark.triangle.fill", color: Theme.warning, title: tr("A exportação falhou"), message: message)
                HStack {
                    Button(tr("Fechar"), action: onDone).buttonStyle(AudraButtonStyle(kind: .ghost))
                    Spacer()
                    Button(tr("Ajustar e Tentar Novamente"), action: onRetry).buttonStyle(AudraButtonStyle(kind: .primary))
                }
            case .cancelled:
                result(symbol: "xmark.circle", color: Theme.textSecondary, title: tr("Exportação cancelada"),
                       message: tr("Nenhum arquivo incompleto foi deixado no destino."))
                HStack {
                    Button(tr("Fechar"), action: onDone).buttonStyle(AudraButtonStyle(kind: .ghost))
                    Spacer()
                    Button(tr("Exportar Novamente"), action: onRetry).buttonStyle(AudraButtonStyle(kind: .primary))
                }
            }
        }
        .padding(20)
        .animation(Motion.smooth, value: job.state)
    }

    private var fileSize: String {
        let size = (try? job.destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func result(symbol: String, color: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(color)
                .symbolEffect(.bounce, value: title)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(message).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
