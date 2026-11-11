import SwiftData
import SwiftUI

/// Landing screen: greeting, the two main jobs, and where you left off.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.audraDisplay)
                        .tracking(-0.6)
                        .foregroundStyle(Theme.textPrimary)
                    Text(tr("Transcreva, resuma e edite vídeos. Tudo acontece no seu Mac."))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                }

                HStack(spacing: 14) {
                    QuickAction(symbol: "waveform", title: tr("Transcrever vídeo"),
                                detail: tr("Texto com timestamps e resumo estruturado"),
                                shortcut: "⌘O", tint: Color(hex: 0x6A45D9)) { model.presentImporter() }
                    QuickAction(symbol: "film", title: tr("Novo projeto"),
                                detail: tr("Timeline, textos, legendas e edição pelo texto"),
                                shortcut: "⇧⌘N", tint: Color(hex: 0x3B2C7A)) { model.newProject() }
                }

                if !model.projects.projects.isEmpty {
                    section(title: tr("Projetos recentes"), action: (tr("Ver todos"), { model.selection = .projects })) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                            ForEach(model.projects.projects.prefix(4)) { ProjectCard(summary: $0) }
                        }
                    }
                }

                if !recordings.isEmpty {
                    section(title: tr("Transcrições recentes"), action: (tr("Ver todas"), { model.selection = .transcriptions })) {
                        VStack(spacing: 0) {
                            ForEach(recordings.prefix(5)) { recording in
                                RecentRow(recording: recording)
                            }
                        }
                    }
                }

                if recordings.isEmpty && model.projects.projects.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.to.line")
                            .foregroundStyle(Theme.accentBright)
                        Text(tr("Dica: arraste vídeos para qualquer lugar desta janela para começar a transcrever."))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .font(.system(size: 12.5))
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .background(alignment: .top) {
            // Faint violet light at the top edge, like stage lighting.
            RadialGradient(colors: [Theme.accent.opacity(0.13), .clear], center: .top, startRadius: 0, endRadius: 560)
                .frame(height: 420)
                .allowsHitTesting(false)
        }
        .onAppear { withAnimation(Motion.smooth) { appeared = true } }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: tr("Bom dia")
        case 12..<18: tr("Boa tarde")
        default: tr("Boa noite")
        }
    }

    private func section<Content: View>(title: String, action: (String, () -> Void), @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.audraHeadline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action.0, action: action.1)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            content()
        }
    }
}

private struct QuickAction: View {
    let symbol: String
    let title: String
    let detail: String
    let shortcut: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textQuaternary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textQuaternary)
                    .offset(x: hovering ? 2 : 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(hovering ? Theme.elevated : Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(hovering ? Theme.strokeStrong : Theme.stroke)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
    }
}

private struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let recording: Recording
    @State private var hovering = false

    var body: some View {
        Button { model.selection = .recording(recording.id) } label: {
            HStack(spacing: 12) {
                StatusGlyph(status: recording.status, hasVideo: recording.hasVideo)
                Text(recording.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if recording.status.isActive {
                    StatusChip(status: recording.status, progress: model.processing.job(for: recording.id)?.overallProgress)
                } else {
                    Text(TimeFormat.clock(recording.duration))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(recording.createdAt.formatted(.dateTime.day().month(.abbreviated).locale(Localization.shared.locale)))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Theme.elevated : .clear))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 12).opacity(hovering ? 0 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .contextMenu {
            if recording.status == .completed {
                Button(tr("Editar em Novo Projeto")) { model.editInNewProject(recording) }
            }
            Button(tr("Mostrar no Finder")) { model.revealInFinder(recording) }
        }
    }
}

/// Brand mark: deep violet squircle with waveform bars.
struct AppMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x7653E6), Color(hex: 0x2A1670)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)))
            HStack(spacing: size * 0.06) {
                ForEach([0.35, 0.7, 0.5, 0.85, 0.4], id: \.self) { h in
                    Capsule().fill(.white.opacity(0.95)).frame(width: max(1.5, size * 0.07), height: size * 0.62 * h)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusGlyph: View {
    let status: ProcessingStatus
    let hasVideo: Bool

    var body: some View {
        Group {
            switch status {
            case .completed: Image(systemName: hasVideo ? "play.rectangle" : "waveform").foregroundStyle(Theme.accentBright)
            case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
            case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(Theme.textTertiary)
            case .queued: Image(systemName: "clock").foregroundStyle(Theme.textTertiary)
            default: PulseBars()
            }
        }
        .font(.system(size: 13))
        .frame(width: 20)
    }
}
