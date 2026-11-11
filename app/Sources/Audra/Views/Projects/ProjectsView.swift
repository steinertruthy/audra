import SwiftUI

/// Grid of saved editing projects.
struct ProjectsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.projects.projects.isEmpty {
                EmptyStateView(symbol: "film.stack", title: tr("Nenhum projeto ainda"),
                               message: tr("Crie um projeto para editar vídeos com timeline, textos, legendas e cortes pela transcrição.")) {
                    Button(tr("Novo Projeto")) { model.newProject() }
                        .buttonStyle(AudraButtonStyle(kind: .primary, large: true))
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        PageTitle(title: tr("Projetos"),
                                  subtitle: tr("Salvos automaticamente · os arquivos originais nunca são alterados")) {
                            Button { model.newProject() } label: { Label(tr("Novo projeto"), systemImage: "plus") }
                                .buttonStyle(AudraButtonStyle(kind: .secondary))
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(model.projects.projects) { ProjectCard(summary: $0) }
                        }
                        .animation(Motion.smooth, value: model.projects.projects.map(\.id))
                    }
                    .frame(maxWidth: 1180)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Theme.canvas)
        .onAppear { model.projects.refresh() }
    }
}

struct ProjectCard: View {
    @Environment(AppModel.self) private var model
    let summary: ProjectSummary
    @State private var hovering = false
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        Button { model.openProject(summary.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x1C1530), Color(hex: 0x0D0B12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let poster = summary.poster, let image = MediaCache.shared.poster(for: poster) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "film.stack")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(Theme.accentBright.opacity(0.7))
                    }
                    if hovering {
                        Color.black.opacity(0.35)
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.accentGradient, in: Circle())
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    Text(TimeFormat.clock(summary.duration))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(8)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(tr("Editado %@ · %@ clipes", summary.modifiedAt.formatted(.relative(presentation: .named).locale(Localization.shared.locale)), summary.clipCount))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                .padding(12)
            }
            .background(hovering ? Theme.elevated : Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(hovering ? Theme.strokeStrong : Theme.stroke)
            )
            .shadow(color: .black.opacity(hovering ? 0.5 : 0), radius: 16, y: 8)
            .offset(y: hovering ? -2 : 0)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .contextMenu {
            Button(tr("Abrir")) { model.openProject(summary.id) }
            Button(tr("Renomear…")) { newName = summary.name; renaming = true }
            Button(tr("Duplicar")) { _ = model.projects.duplicate(summary.id) }
            Divider()
            Button(tr("Mover para o Lixo…"), role: .destructive) { model.confirmDeleteProject(summary) }
        }
        .alert(tr("Renomear projeto"), isPresented: $renaming) {
            TextField(tr("Nome"), text: $newName)
            Button(tr("Renomear")) { model.projects.rename(summary.id, to: newName) }
            Button(tr("Cancelar"), role: .cancel) {}
        }
        .accessibilityLabel(tr("Projeto %@, %@", summary.name, TimeFormat.clock(summary.duration)))
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .hoverHighlight(radius: 6)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
