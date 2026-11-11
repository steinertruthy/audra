import AVFoundation
import SwiftUI

/// The editor's program monitor: plays the edited composition, not the source file.
struct MonitorView: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let size = fittedSize(in: CGSize(width: geo.size.width - 32, height: geo.size.height - 28))
                ZStack {
                    Theme.canvas
                    ZStack {
                        Color.black
                        PlayerLayerView(player: session.player)
                        if session.duration < 0.01 {
                            emptyCanvas
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                    .overlay(alignment: .topTrailing) { statusBadges.padding(10) }
                    .onTapGesture(count: 2) { toggleTheater() }
                    .onTapGesture { session.togglePlayback() }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            TransportBar(session: session, toggleTheater: toggleTheater)
        }
        .background(Theme.canvas)
    }

    private func fittedSize(in bounds: CGSize) -> CGSize {
        let aspect = session.project.canvas.aspect
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        if bounds.width / bounds.height > aspect {
            return CGSize(width: bounds.height * aspect, height: bounds.height)
        }
        return CGSize(width: bounds.width, height: bounds.width / aspect)
    }

    private var emptyCanvas: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(Theme.accentBright.opacity(0.8))
            Text(tr("Arraste mídias para a timeline"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Button(tr("Adicionar Mídia…")) { session.presentImporter() }
                .buttonStyle(AudraButtonStyle(kind: .primary))
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        HStack(spacing: 6) {
            if let error = session.buildError {
                Badge(text: tr("Erro na pré-visualização"), color: Theme.danger, symbol: "exclamationmark.triangle.fill")
                    .help(error)
            }
            if session.project.media.contains(where: { !$0.isAvailable }) {
                Badge(text: tr("Mídia ausente"), color: Theme.warning, symbol: "questionmark.folder.fill")
                    .help(tr("Um ou mais arquivos originais foram movidos ou excluídos."))
            }
        }
    }

    private func toggleTheater() {
        withAnimation(Motion.smooth) { session.theaterMode.toggle() }
    }
}

private struct TransportBar: View {
    @Bindable var session: EditorSession
    let toggleTheater: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(TimeFormat.timecode(session.currentTime, fps: session.fps))
                    .foregroundStyle(Theme.textPrimary)
                Text("/").foregroundStyle(Theme.textQuaternary)
                Text(TimeFormat.timecode(session.duration, fps: session.fps))
                    .foregroundStyle(Theme.textTertiary)
            }
            .font(.audraTimecode)
            .monospacedDigit()
            .frame(minWidth: 210, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button { session.seek(to: 0) } label: { Image(systemName: "backward.end.fill") }
                    .iconButton(size: 30).help(tr("Ir para o início (Home)"))
                Button { session.step(frames: -1) } label: { Image(systemName: "backward.frame.fill") }
                    .iconButton(size: 30).help(tr("Quadro anterior (←)"))
                PlayButton(isPlaying: session.isPlaying) { session.togglePlayback() }
                    .padding(.horizontal, 6)
                Button { session.step(frames: 1) } label: { Image(systemName: "forward.frame.fill") }
                    .iconButton(size: 30).help(tr("Próximo quadro (→)"))
                Button { session.seek(to: session.duration) } label: { Image(systemName: "forward.end.fill") }
                    .iconButton(size: 30).help(tr("Ir para o fim (End)"))
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button {
                            session.playbackRate = Float(rate)
                        } label: {
                            if Float(rate) == session.playbackRate { Label(tr("%@×", rate.formatted()), systemImage: "checkmark") }
                            else { Text(tr("%@×", rate.formatted())) }
                        }
                    }
                } label: {
                    Text(tr("%@×", Double(session.playbackRate).formatted()))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(session.playbackRate == 1 ? Theme.textSecondary : Theme.accentBright)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("Velocidade de reprodução da pré-visualização"))

                Button { session.monitorMuted.toggle() } label: {
                    Image(systemName: session.monitorMuted || session.monitorVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .iconButton(session.monitorMuted)
                .help(session.monitorMuted ? tr("Ativar som") : tr("Silenciar pré-visualização"))
                Slider(value: Binding(get: { Double(session.monitorVolume) }, set: { session.monitorVolume = Float($0) }), in: 0...1)
                    .controlSize(.mini)
                    .frame(width: 72)
                    .accessibilityLabel(tr("Volume da pré-visualização"))
                Button(action: toggleTheater) {
                    Image(systemName: session.theaterMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .iconButton(session.theaterMode)
                .help(session.theaterMode ? tr("Sair da tela cheia (Esc)") : tr("Tela cheia (F)"))
            }
            .frame(minWidth: 210, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Theme.base)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct PlayButton: View {
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .offset(x: isPlaying ? 0 : 1.5)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.accentGradient))
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                .shadow(color: Theme.accent.opacity(hovering ? 0.65 : 0.4), radius: hovering ? 12 : 8)
                .scaleEffect(hovering ? 1.05 : 1)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Motion.bouncy, value: hovering)
        .help(isPlaying ? tr("Pausar (Espaço)") : tr("Reproduzir (Espaço)"))
        .accessibilityLabel(isPlaying ? tr("Pausar") : tr("Reproduzir"))
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// AVPlayerLayer host without AVKit's own controls.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerHostView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerHostView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
