import SwiftUI

/// Shows real progress for a queued or running job, with a live preview of recognized speech.
struct ProcessingView: View {
    @Environment(AppModel.self) private var model
    let recording: Recording

    private var job: JobState? { model.processing.job(for: recording.id) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                header
                StageList(current: job?.stage ?? recording.status, summaryEnabled: Preferences.autoSummarize)
                progress
            }
            .frame(maxWidth: 520)
            .padding(28)
            .panelSurface(radius: Theme.Radius.xlarge, fill: Theme.panel)
            .padding(.top, 56)
            .padding(.horizontal, 40)

            if let job, !job.liveSegments.isEmpty {
                LivePreview(segments: job.liveSegments)
                    .frame(maxWidth: 620)
                    .padding(.top, 36)
                    .padding(.horizontal, 40)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Theme.accent.opacity(0.14), .clear], center: .top, startRadius: 0, endRadius: 480)
                .ignoresSafeArea()
        )
        .background(Theme.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if recording.status != .queued { PulseBars() }
                Text(recording.status == .queued ? tr("Aguardando na fila") : tr("Processando"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(job?.message ?? queueMessage)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.default, value: job?.message)
        }
    }

    private var queueMessage: String {
        if let position = model.processing.queuePosition(of: recording.id) {
            return position == 1 ? tr("Será o próximo a ser processado.") : tr("Posição %@ na fila.", position)
        }
        return recording.status.label
    }

    @ViewBuilder
    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let job, job.stage != .queued {
                AudraProgressBar(value: job.overallProgress, height: 8)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Text("\(Int(job.overallProgress * 100))%")
                        Text("·").foregroundStyle(.tertiary)
                        Text(tr("Decorrido %@", TimeFormat.clock(elapsed(job, now: context.date))))
                        if let remaining = remaining(job, now: context.date) {
                            Text("·").foregroundStyle(.tertiary)
                            Text(tr("Restam cerca de %@", TimeFormat.spoken(remaining)))
                        }
                        Spacer()
                    }
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            } else {
                AudraProgressBar(value: 0, height: 8, animated: false)
            }

            HStack {
                Spacer()
                Button(tr("Cancelar"), role: .cancel) { model.processing.cancel(recording.id) }
                    .buttonStyle(AudraButtonStyle(kind: .secondary))
                    .keyboardShortcut(".", modifiers: .command)
            }
            .padding(.top, 6)
        }
    }

    private func elapsed(_ job: JobState, now: Date) -> Double {
        job.startedAt.map { now.timeIntervalSince($0) } ?? 0
    }

    /// Simple linear estimate; only shown once enough progress exists to be meaningful.
    private func remaining(_ job: JobState, now: Date) -> Double? {
        let p = job.overallProgress
        let t = elapsed(job, now: now)
        guard p > 0.08, p < 0.99, t > 5 else { return nil }
        return t / p * (1 - p)
    }
}

private struct StageList: View {
    let current: ProcessingStatus
    let summaryEnabled: Bool

    private var stages: [ProcessingStatus] {
        summaryEnabled ? [.preparing, .detectingLanguage, .transcribing, .summarizing] : [.preparing, .detectingLanguage, .transcribing]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(stages, id: \.self) { stage in
                HStack(spacing: 10) {
                    indicator(for: stage).frame(width: 16)
                    Text(stage.label)
                        .foregroundStyle(state(of: stage) == .pending ? .secondary : .primary)
                        .fontWeight(state(of: stage) == .running ? .medium : .regular)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private enum StageState { case done, running, pending }

    private func state(of stage: ProcessingStatus) -> StageState {
        let order: [ProcessingStatus] = [.queued, .preparing, .detectingLanguage, .transcribing, .summarizing]
        guard let a = order.firstIndex(of: stage), let b = order.firstIndex(of: current) else { return .pending }
        return a < b ? .done : a == b ? .running : .pending
    }

    @ViewBuilder
    private func indicator(for stage: ProcessingStatus) -> some View {
        switch state(of: stage) {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success).transition(.scale.combined(with: .opacity))
        case .running: ProgressView().controlSize(.small).tint(Theme.accentBright)
        case .pending: Image(systemName: "circle").foregroundStyle(Theme.textQuaternary)
        }
    }
}

private struct LivePreview: View {
    let segments: [TranscriptSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("Prévia da transcrição"), systemImage: "text.bubble")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(segments.suffix(5)) { segment in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(TimeFormat.clock(segment.start))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Text(segment.text)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.25), value: segments.count)
            .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
        }
    }
}

/// Failed or cancelled jobs: say clearly what happened and offer a way forward.
struct FailureView: View {
    @Environment(AppModel.self) private var model
    let recording: Recording

    var body: some View {
        ContentUnavailableView {
            Label(recording.status == .cancelled ? tr("Processamento cancelado") : tr("Não foi possível processar este arquivo"),
                  systemImage: recording.status == .cancelled ? "xmark.circle" : "exclamationmark.triangle")
        } description: {
            Text(recording.errorMessage ?? (recording.status == .cancelled ? tr("O processamento foi interrompido antes de terminar.") : tr("Ocorreu um erro desconhecido.")))
                .textSelection(.enabled)
        } actions: {
            HStack {
                Button(tr("Tentar Novamente")) { model.reprocess(recording) }
                    .buttonStyle(AudraButtonStyle(kind: .primary))
                    .disabled(!recording.sourceExists)
                Button(tr("Mostrar no Finder")) { model.revealInFinder(recording) }
                    .disabled(!recording.sourceExists)
                Button(tr("Remover…"), role: .destructive) { model.confirmDelete(recording) }
            }
        }
    }
}
