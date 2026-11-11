import AppKit
import SwiftUI

extension EditorSession {
    /// Two-way binding to a clip property; slider drags coalesce into one undo step.
    func clipBinding<T: Equatable>(_ id: UUID, _ keyPath: WritableKeyPath<EditClip, T>, fallback: T, name: String) -> Binding<T> {
        Binding(
            get: { self.project.clip(id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.update(id, name, coalesce: name) { $0[keyPath: keyPath] = value } }
        )
    }

    func textBinding<T: Equatable>(_ id: UUID, _ keyPath: WritableKeyPath<TextStyle, T>, fallback: T, name: String) -> Binding<T> {
        Binding(
            get: { self.project.clip(id)?.text?[keyPath: keyPath] ?? fallback },
            set: { value in self.update(id, name, coalesce: name) { $0.text?[keyPath: keyPath] = value } }
        )
    }
}

extension RGBAColor {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// Right-hand panel: properties of the selection, or of the project when nothing is selected.
struct InspectorView: View {
    @Bindable var session: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
                .id(session.selection.count == 1 ? session.selection.first : nil)
                .transition(.opacity)
            }
            .scrollIndicators(.never)
        }
        .background(Theme.panel)
        .animation(Motion.fade, value: session.selection)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentBright)
            Text(headerTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var headerTitle: String {
        switch session.selection.count {
        case 0: tr("Projeto")
        case 1:
            if let clip = session.singleSelectedClip {
                clip.isText ? tr("Texto") : session.project.track(containing: clip.id)?.kind == .audio ? tr("Clipe de áudio") : tr("Clipe de vídeo")
            } else { tr("Clipe") }
        default: tr("%@ clipes", session.selection.count)
        }
    }

    private var headerSymbol: String {
        guard let clip = session.singleSelectedClip else { return session.selection.isEmpty ? "film.stack" : "square.stack.3d.up" }
        if clip.isText { return "textformat" }
        return session.project.track(containing: clip.id)?.kind == .audio ? "waveform" : "film"
    }

    @ViewBuilder
    private var content: some View {
        if let clip = session.singleSelectedClip, let track = session.project.track(containing: clip.id) {
            if track.isLocked {
                Label(tr("Faixa bloqueada — desbloqueie para editar."), systemImage: "lock.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.warning)
                    .padding(.vertical, 12)
            }
            if clip.isText {
                TextInspector(session: session, clip: clip)
            } else {
                ClipInspector(session: session, clip: clip, kind: track.kind)
            }
        } else if session.selection.count > 1 {
            MultiInspector(session: session)
        } else {
            ProjectInspector(session: session)
        }
    }
}

// MARK: - Project

private struct ProjectInspector: View {
    @Bindable var session: EditorSession
    @State private var name = ""

    private struct FormatPreset: Hashable {
        let title: String
        let width: Int
        let height: Int
    }

    private let presets = [
        FormatPreset(title: tr("Paisagem 16:9 · 1080p"), width: 1920, height: 1080),
        FormatPreset(title: tr("Paisagem 16:9 · 4K"), width: 3840, height: 2160),
        FormatPreset(title: tr("Paisagem 16:9 · 720p"), width: 1280, height: 720),
        FormatPreset(title: tr("Vertical 9:16 · Reels/Shorts"), width: 1080, height: 1920),
        FormatPreset(title: tr("Quadrado 1:1"), width: 1080, height: 1080),
        FormatPreset(title: tr("Retrato 4:5"), width: 1080, height: 1350),
    ]

    var body: some View {
        InspectorGroup(title: tr("Informações"), symbol: "doc.richtext") {
            TextField(tr("Nome do projeto"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { session.rename(name) }
                .onAppear { name = session.project.name }
                .onChange(of: session.project.name) { _, new in name = new }
            stat(tr("Duração"), TimeFormat.timecode(session.duration, fps: session.fps))
            stat(tr("Clipes"), "\(session.project.tracks.reduce(0) { $0 + $1.clips.count })")
            stat(tr("Mídias"), "\(session.project.media.count)")
        }

        InspectorGroup(title: tr("Formato"), symbol: "aspectratio") {
            Picker(tr("Formato"), selection: formatBinding) {
                ForEach(presets, id: \.self) { Text($0.title).tag(Optional($0)) }
                if !presets.contains(where: { $0.width == session.project.canvas.width && $0.height == session.project.canvas.height }) {
                    Text(tr("Personalizado · %@×%@", session.project.canvas.width, session.project.canvas.height)).tag(FormatPreset?.none)
                }
            }
            .labelsHidden()
            Picker(tr("Quadros por segundo"), selection: Binding(
                get: { session.project.canvas.fps },
                set: { fps in session.perform(tr("Alterar FPS")) { $0.canvas.fps = fps } })) {
                ForEach([24.0, 25, 30, 50, 60], id: \.self) { Text(tr("%@ fps", Int($0))).tag($0) }
            }
            ColorPicker(tr("Cor de fundo"), selection: Binding(
                get: { session.project.canvas.background.color },
                set: { color in session.perform(tr("Cor de fundo"), coalesce: "bg") { $0.canvas.background = RGBAColor(color) } }),
                supportsOpacity: false)
                .font(.system(size: 11.5))
        }

        Text(tr("Todos os atalhos estão nos menus Clipe e Reprodução, na barra de menus."))
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
    }

    private var formatBinding: Binding<FormatPreset?> {
        Binding(
            get: { presets.first { $0.width == session.project.canvas.width && $0.height == session.project.canvas.height } },
            set: { preset in
                guard let preset else { return }
                session.perform(tr("Alterar formato")) {
                    $0.canvas.width = preset.width
                    $0.canvas.height = preset.height
                }
            })
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .font(.system(size: 11.5))
    }

}

// MARK: - Video & audio clips

private struct ClipInspector: View {
    @Bindable var session: EditorSession
    let clip: EditClip
    let kind: TrackKind

    private var media: MediaItem? { session.project.mediaItem(clip.mediaID) }
    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    private func secs(_ v: Double) -> String { String(format: tr("%.2f s"), v) }

    var body: some View {
        InspectorGroup(title: tr("Clipe"), symbol: "info.circle") {
            Text(clip.label ?? media?.name ?? tr("Mídia"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            row(tr("Na timeline"), "\(TimeFormat.timecode(clip.start, fps: session.fps)) → \(TimeFormat.timecode(clip.end, fps: session.fps))")
            row(tr("Duração"), secs(clip.duration))
            row(tr("Trecho original"), "\(TimeFormat.clock(clip.sourceIn)) – \(TimeFormat.clock(clip.sourceOut))")
            if let media, !media.isAvailable {
                Label(tr("Arquivo original não encontrado"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(Theme.warning)
            }
            Button(tr("Ir para o início do clipe")) { session.seek(to: clip.start) }
                .buttonStyle(AudraButtonStyle(kind: .ghost))
        }

        InspectorGroup(title: tr("Velocidade"), symbol: "gauge.with.dots.needle.67percent") {
            ValueSlider(title: tr("Velocidade"), value: Binding(get: { clip.speed }, set: { session.setSpeed(clip.id, $0) }),
                        range: 0.25...4, format: { String(format: tr("%.2f×"), $0) }, resetValue: 1)
            HStack(spacing: 4) {
                ForEach([0.5, 1, 1.5, 2], id: \.self) { speed in
                    Button(speed.formatted() + tr("×")) { session.setSpeed(clip.id, speed) }
                        .buttonStyle(AudraButtonStyle(kind: abs(clip.speed - speed) < 0.001 ? .primary : .secondary))
                }
            }
        }

        if kind == .video {
            InspectorGroup(title: tr("Transformar"), symbol: "arrow.up.and.down.and.arrow.left.and.right") {
                ValueSlider(title: tr("Escala"), value: session.clipBinding(clip.id, \.transform.scale, fallback: 1, name: tr("Escala")),
                            range: 0.1...3, format: pct, resetValue: 1)
                ValueSlider(title: tr("Posição X"), value: session.clipBinding(clip.id, \.transform.x, fallback: 0, name: tr("Posição")),
                            range: -1...1, format: pct, resetValue: 0)
                ValueSlider(title: tr("Posição Y"), value: session.clipBinding(clip.id, \.transform.y, fallback: 0, name: tr("Posição")),
                            range: -1...1, format: pct, resetValue: 0)
                ValueSlider(title: tr("Rotação"), value: session.clipBinding(clip.id, \.transform.rotation, fallback: 0, name: tr("Rotação")),
                            range: -180...180, format: { "\(Int($0.rounded()))°" }, resetValue: 0)
                HStack(spacing: 4) {
                    Button { rotate(-90) } label: { Label("90°", systemImage: "rotate.left") }
                    Button { rotate(90) } label: { Label("90°", systemImage: "rotate.right") }
                    Spacer()
                    Button(tr("Redefinir")) { session.update(clip.id, tr("Redefinir transformação")) { $0.transform = ClipTransform() } }
                        .disabled(clip.transform.isIdentity)
                }
                .buttonStyle(AudraButtonStyle(kind: .secondary))
            }

            InspectorGroup(title: tr("Recortar"), symbol: "crop") {
                ValueSlider(title: tr("Esquerda"), value: session.clipBinding(clip.id, \.crop.left, fallback: 0, name: tr("Recorte")),
                            range: 0...0.45, format: pct, resetValue: 0)
                ValueSlider(title: tr("Direita"), value: session.clipBinding(clip.id, \.crop.right, fallback: 0, name: tr("Recorte")),
                            range: 0...0.45, format: pct, resetValue: 0)
                ValueSlider(title: tr("Topo"), value: session.clipBinding(clip.id, \.crop.top, fallback: 0, name: tr("Recorte")),
                            range: 0...0.45, format: pct, resetValue: 0)
                ValueSlider(title: tr("Base"), value: session.clipBinding(clip.id, \.crop.bottom, fallback: 0, name: tr("Recorte")),
                            range: 0...0.45, format: pct, resetValue: 0)
            }

            InspectorGroup(title: tr("Opacidade e fades"), symbol: "circle.lefthalf.filled") {
                ValueSlider(title: tr("Opacidade"), value: session.clipBinding(clip.id, \.opacity, fallback: 1, name: tr("Opacidade")),
                            range: 0...1, format: pct, resetValue: 1)
                ValueSlider(title: tr("Fade de entrada"), value: session.clipBinding(clip.id, \.fadeIn, fallback: 0, name: tr("Fade de entrada")),
                            range: 0...min(5, clip.duration / 2), format: secs, resetValue: 0)
                ValueSlider(title: tr("Fade de saída"), value: session.clipBinding(clip.id, \.fadeOut, fallback: 0, name: tr("Fade de saída")),
                            range: 0...min(5, clip.duration / 2), format: secs, resetValue: 0)
            }

            InspectorGroup(title: tr("Transição de entrada"), symbol: "rectangle.2.swap") {
                TransitionPicker(session: session, clip: clip)
            }
        }

        if media?.hasAudio == true {
            InspectorGroup(title: tr("Áudio"), symbol: "speaker.wave.2") {
                Toggle(tr("Silenciar áudio deste clipe"), isOn: session.clipBinding(clip.id, \.audioMuted, fallback: false, name: tr("Silenciar")))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5))
                Group {
                    ValueSlider(title: tr("Volume"), value: session.clipBinding(clip.id, \.volume, fallback: 1, name: tr("Volume")),
                                range: 0...2, format: pct, resetValue: 1)
                    ValueSlider(title: tr("Fade in"), value: session.clipBinding(clip.id, \.audioFadeIn, fallback: 0, name: tr("Fade de áudio")),
                                range: 0...min(10, clip.duration / 2), format: secs, resetValue: 0)
                    ValueSlider(title: tr("Fade out"), value: session.clipBinding(clip.id, \.audioFadeOut, fallback: 0, name: tr("Fade de áudio")),
                                range: 0...min(10, clip.duration / 2), format: secs, resetValue: 0)
                }
                .disabled(clip.audioMuted)
                if kind == .video {
                    HStack(spacing: 6) {
                        Button(tr("Separar áudio")) { session.selection = [clip.id]; session.detachAudio() }
                            .disabled(clip.audioMuted)
                        Button(tr("Substituir…")) { session.replaceAudio(of: clip.id) }
                    }
                    .buttonStyle(AudraButtonStyle(kind: .secondary))
                }
            }
        }
    }

    private func rotate(_ degrees: Double) {
        session.update(clip.id, tr("Girar")) { clip in
            var value = clip.transform.rotation + degrees
            if value > 180 { value -= 360 }
            if value < -180 { value += 360 }
            clip.transform.rotation = value
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11))
    }
}

private struct TransitionPicker: View {
    let session: EditorSession
    let clip: EditClip

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 74), spacing: 6)]
        LazyVGrid(columns: columns, spacing: 6) {
            tile(nil, title: tr("Nenhuma"), symbol: "square")
            ForEach(TransitionKind.allCases) { kind in tile(kind, title: kind.label, symbol: kind.symbol) }
        }
        if clip.transition != nil {
            ValueSlider(title: tr("Duração"),
                        value: Binding(get: { clip.transition?.duration ?? 0.75 },
                                       set: { value in session.update(clip.id, tr("Duração da transição"), coalesce: "transition") { $0.transition?.duration = value } }),
                        range: 0.2...min(3, max(0.25, clip.duration / 2)), format: { String(format: tr("%.2f s"), $0) }, resetValue: 0.75)
            Text(tr("Usa a sobra de mídia do clipe anterior quando existe; sem sobra, a transição passa pelo preto."))
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile(_ kind: TransitionKind?, title: String, symbol: String) -> some View {
        let selected = clip.transition?.kind == kind
        return Button {
            session.update(clip.id, kind == nil ? tr("Remover transição") : tr("Transição")) { c in
                c.transition = kind.map { ClipTransition(kind: $0, duration: c.transition?.duration ?? 0.75) }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 9.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.accentBright : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .hoverHighlight(radius: 8, isSelected: selected)
            .background(Theme.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Text

private struct TextInspector: View {
    @Bindable var session: EditorSession
    let clip: EditClip
    @State private var draft = ""

    private var style: TextStyle { clip.text ?? TextStyle(content: "") }

    var body: some View {
        InspectorGroup(title: tr("Conteúdo"), symbol: "character.cursor.ibeam") {
            TextEditor(text: $draft)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 64, maxHeight: 120)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke))
                .onAppear { draft = style.content }
                .onChange(of: clip.id) { _, _ in draft = style.content }
                .onChange(of: draft) { _, new in
                    if new != style.content { session.update(clip.id, tr("Editar texto"), coalesce: "text") { $0.text?.content = new } }
                }
            ValueSlider(title: tr("Duração"), value: Binding(get: { clip.duration }, set: { value in
                session.perform(tr("Duração do texto"), coalesce: "textdur-\(clip.id)") { $0.trimEnd(clip.id, to: clip.start + value) }
            }), range: 0.3...30, format: { String(format: tr("%.1f s"), $0) })
        }

        InspectorGroup(title: tr("Estilo"), symbol: "textformat.size") {
            Picker(tr("Fonte"), selection: session.textBinding(clip.id, \.fontName, fallback: tr("SF Pro Display"), name: tr("Fonte"))) {
                ForEach(TextFonts.families, id: \.self) { Text($0).tag($0) }
            }
            .font(.system(size: 11.5))
            ValueSlider(title: tr("Tamanho"), value: session.textBinding(clip.id, \.size, fallback: 0.07, name: tr("Tamanho")),
                        range: 0.02...0.25, format: { tr("%@ pt", Int(($0 * 1080).rounded())) })
            HStack(spacing: 4) {
                Toggle(isOn: session.textBinding(clip.id, \.bold, fallback: true, name: tr("Negrito"))) { Image(systemName: "bold") }
                Toggle(isOn: session.textBinding(clip.id, \.italic, fallback: false, name: tr("Itálico"))) { Image(systemName: "italic") }
                Toggle(isOn: session.textBinding(clip.id, \.shadow, fallback: true, name: tr("Sombra"))) { Image(systemName: "shadow") }
                Spacer()
                Picker(tr("Alinhamento"), selection: session.textBinding(clip.id, \.alignment, fallback: .center, name: tr("Alinhamento"))) {
                    Image(systemName: "text.alignleft").tag(TextAlignmentOption.leading)
                    Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                    Image(systemName: "text.alignright").tag(TextAlignmentOption.trailing)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 96)
            }
            .toggleStyle(.button)
            ColorPicker(tr("Cor do texto"), selection: Binding(get: { style.color.color }, set: { color in
                session.update(clip.id, tr("Cor do texto"), coalesce: "color") { $0.text?.color = RGBAColor(color) }
            }))
            .font(.system(size: 11.5))
            Toggle(tr("Caixa de fundo"), isOn: session.textBinding(clip.id, \.showBackground, fallback: false, name: tr("Fundo")))
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 11.5))
            if style.showBackground {
                ColorPicker(tr("Cor do fundo"), selection: Binding(get: { style.background.color }, set: { color in
                    session.update(clip.id, tr("Cor do fundo"), coalesce: "bgcolor") { $0.text?.background = RGBAColor(color) }
                }))
                .font(.system(size: 11.5))
            }
        }

        InspectorGroup(title: tr("Posição"), symbol: "move.3d") {
            HStack(spacing: 4) {
                ForEach([(tr("Topo"), 0.14), (tr("Centro"), 0.5), (tr("Base"), 0.86)], id: \.0) { item in
                    Button(item.0) { session.update(clip.id, tr("Posição do texto")) { $0.text?.y = item.1; $0.text?.x = 0.5 } }
                        .buttonStyle(AudraButtonStyle(kind: abs(style.y - item.1) < 0.01 && abs(style.x - 0.5) < 0.01 ? .primary : .secondary))
                }
            }
            ValueSlider(title: tr("Horizontal"), value: session.textBinding(clip.id, \.x, fallback: 0.5, name: tr("Posição")),
                        range: 0...1, format: { "\(Int(($0 * 100).rounded()))%" }, resetValue: 0.5)
            ValueSlider(title: tr("Vertical"), value: session.textBinding(clip.id, \.y, fallback: 0.5, name: tr("Posição")),
                        range: 0...1, format: { "\(Int(($0 * 100).rounded()))%" }, resetValue: 0.5)
            ValueSlider(title: tr("Largura máxima"), value: session.textBinding(clip.id, \.maxWidth, fallback: 0.86, name: tr("Largura")),
                        range: 0.2...1, format: { "\(Int(($0 * 100).rounded()))%" })
        }

        InspectorGroup(title: tr("Animação"), symbol: "sparkles") {
            Picker(tr("Entrada"), selection: session.textBinding(clip.id, \.animationIn, fallback: .fade, name: tr("Animação"))) {
                ForEach(TextAnimation.allCases) { Text($0.label).tag($0) }
            }
            .font(.system(size: 11.5))
            Picker(tr("Saída"), selection: session.textBinding(clip.id, \.animationOut, fallback: .fade, name: tr("Animação"))) {
                ForEach(TextAnimation.allCases.filter { $0 != .typewriter }) { Text($0.label).tag($0) }
            }
            .font(.system(size: 11.5))
            ValueSlider(title: tr("Duração da animação"), value: session.textBinding(clip.id, \.animationDuration, fallback: 0.4, name: tr("Animação")),
                        range: 0.1...2, format: { String(format: tr("%.2f s"), $0) }, resetValue: 0.4)
        }
    }
}

// MARK: - Multiple

private struct MultiInspector: View {
    @Bindable var session: EditorSession

    var body: some View {
        let clips = session.selectedClips
        InspectorGroup(title: tr("Seleção"), symbol: "square.stack.3d.up") {
            Text(tr("%@ clipes · %@ s no total", clips.count, String(format: "%.1f", clips.reduce(0) { $0 + $1.duration })))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                Button(tr("Duplicar")) { session.duplicateSelection() }
                Button(tr("Excluir")) { session.deleteSelection() }
            }
            .buttonStyle(AudraButtonStyle(kind: .secondary))
        }
        let mediaClips = clips.filter { !$0.isText }
        if !mediaClips.isEmpty {
            InspectorGroup(title: tr("Áudio"), symbol: "speaker.wave.2") {
                ValueSlider(title: tr("Volume"), value: Binding(
                    get: { mediaClips.map(\.volume).reduce(0, +) / Double(mediaClips.count) },
                    set: { value in
                        session.perform(tr("Volume"), coalesce: "multi-volume") { project in
                            for clip in mediaClips {
                                guard let loc = project.location(of: clip.id), !project.tracks[loc.track].isLocked else { continue }
                                project.tracks[loc.track].clips[loc.clip].volume = value
                            }
                        }
                    }), range: 0...2, format: { "\(Int(($0 * 100).rounded()))%" }, resetValue: 1)
                let allMuted = mediaClips.allSatisfy(\.audioMuted)
                Button(allMuted ? tr("Ativar áudio") : tr("Silenciar todos")) {
                    session.perform(allMuted ? tr("Ativar áudio") : tr("Silenciar clipes")) { project in
                        for clip in mediaClips {
                            guard let loc = project.location(of: clip.id), !project.tracks[loc.track].isLocked else { continue }
                            project.tracks[loc.track].clips[loc.clip].audioMuted = !allMuted
                        }
                    }
                }
                .buttonStyle(AudraButtonStyle(kind: .secondary))
            }
        }
    }
}
