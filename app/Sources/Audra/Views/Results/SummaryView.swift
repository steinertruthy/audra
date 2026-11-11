import SwiftUI

struct SummaryView: View {
    @Environment(AppModel.self) private var model
    let document: TranscriptDocument
    let player: PlayerController
    let compact: Bool

    private var recording: Recording { document.recording }
    private var job: JobState? { model.processing.job(for: recording.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 22 : 30) {
                if let job, job.stage == .summarizing || job.stage == .queued {
                    generating(job)
                } else if let summary = document.summary {
                    content(summary)
                } else if let error = recording.summaryError {
                    unavailable(message: error)
                } else {
                    unavailable(message: nil)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: compact ? .infinity : 720, alignment: .leading)
            .padding(.horizontal, compact ? 22 : 40)
            .padding(.vertical, compact ? 20 : 36)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: States

    private func generating(_ job: JobState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("Gerando resumo…"), systemImage: "sparkles")
                .font(.headline)
            ProgressView(value: job.stage == .summarizing ? job.stageProgress : 0)
                .animation(.linear, value: job.stageProgress)
            Text(job.message ?? tr("Analisando a transcrição."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private func unavailable(message: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message == nil ? tr("Nenhum resumo gerado") : tr("Resumo indisponível"), systemImage: "sparkles")
                .font(.headline)
            Text(message ?? tr("Gere um resumo estruturado a partir da transcrição."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(message == nil ? tr("Gerar Resumo") : tr("Tentar Novamente")) { model.regenerateSummary(recording) }
                    .buttonStyle(.borderedProminent)
                SettingsLink { Text(tr("Ajustes de Resumo…")) }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ summary: VideoSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(tr("Gerado por IA a partir da transcrição · %@", summary.provider))
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(TranscriptRenderer.disclaimer(summary))
            Spacer()
            Menu {
                ForEach(SummaryDetail.allCases) { detail in
                    Button(tr("Regenerar — %@", detail.label)) {
                        UserDefaults.standard.set(detail.rawValue, forKey: PrefKey.summaryDetail)
                        model.regenerateSummary(recording)
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tr("Gerar o resumo novamente"))
            .accessibilityLabel(tr("Gerar o resumo novamente"))
        }

        Section(title: tr("Visão geral")) {
            Text(summary.overview)
                .font(compact ? .body : .title3)
                .lineSpacing(compact ? 3 : 5)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !summary.chapters.isEmpty {
            Section(title: tr("Capítulos")) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(summary.chapters) { chapter in
                        Button {
                            player.seek(to: chapter.start, play: true)
                            if model.resultMode == .summary { model.resultMode = .full }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(TimeFormat.clock(chapter.start))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.tint)
                                    .frame(minWidth: 52, alignment: .leading)
                                Text(chapter.title)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                        .accessibilityLabel(tr("Capítulo %@, em %@", chapter.title, TimeFormat.clock(chapter.start)))
                    }
                }
                .padding(.horizontal, -6)
            }
        }

        BulletSection(title: tr("Principais tópicos"), items: summary.topics, empty: nil)
        BulletSection(title: tr("Pontos importantes"), items: summary.keyPoints, empty: nil)
        BulletSection(title: tr("Decisões e conclusões"), items: summary.decisions, empty: tr("Nenhuma decisão identificada no conteúdo."))
        BulletSection(title: tr("Ações e próximos passos"), items: summary.actionItems, empty: tr("Nenhuma ação mencionada no conteúdo."), checklist: true)
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

private struct BulletSection: View {
    let title: String
    let items: [String]
    let empty: String?
    var checklist = false

    var body: some View {
        if !items.isEmpty || empty != nil {
            Section(title: title) {
                if items.isEmpty, let empty {
                    Text(empty).font(.callout).foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: checklist ? "circle" : "circle.fill")
                                    .font(.system(size: checklist ? 9 : 5))
                                    .foregroundStyle(checklist ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                                    .frame(width: 10)
                                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + (checklist ? 3.5 : 2.5) }
                                    .accessibilityHidden(true)
                                Text(item)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}
