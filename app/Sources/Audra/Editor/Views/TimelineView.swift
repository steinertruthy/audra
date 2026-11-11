import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Multi-track timeline. Only the visible time range is drawn, so very long projects stay fast;
/// drags and trims are previewed live and committed as a single undoable edit when released.
struct TimelinePanel: View {
    @Bindable var session: EditorSession
    @State private var drag: TimelineDrag?
    @State private var laneWidth: CGFloat = 800
    @State private var magnifyStart: Double?
    @State private var hoverTime: Double?

    private var metrics: TimelineMetrics {
        TimelineMetrics(pixelsPerSecond: session.pixelsPerSecond, scrollX: session.scrollX)
    }

    private var tracks: [EditTrack] { session.project.displayTracks }

    var body: some View {
        VStack(spacing: 0) {
            TimelineToolbar(session: session, laneWidth: laneWidth)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            GeometryReader { geo in
                let width = max(120, geo.size.width - TrackLayout.headerWidth)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        TimelineCorner(session: session)
                            .frame(width: TrackLayout.headerWidth, height: TrackLayout.rulerHeight)
                        RulerView(session: session, metrics: metrics, width: width)
                            .frame(width: width, height: TrackLayout.rulerHeight)
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 1) {
                                ForEach(tracks) { track in
                                    TrackHeader(session: session, track: track)
                                        .frame(height: TrackLayout.height(track.kind))
                                }
                                addTrackRow
                            }
                            .frame(width: TrackLayout.headerWidth)

                            lanes(width: width)
                        }
                    }
                    .scrollIndicators(.automatic)
                }
                .overlay(alignment: .topLeading) {
                    PlayheadOverlay(session: session, metrics: metrics, height: geo.size.height, snapTime: drag?.snapTime)
                        .frame(width: width, height: geo.size.height, alignment: .topLeading)
                        .clipped()
                        .offset(x: TrackLayout.headerWidth)
                        .allowsHitTesting(false)
                }
                .background(
                    ScrollEventCatcher { event, point in handleScroll(event, at: point) }
                        .padding(.leading, TrackLayout.headerWidth)
                )
                .onAppear { laneWidth = width }
                .onChange(of: width) { _, new in laneWidth = new }
            }
        }
        .background(Theme.panel)
        .onChange(of: session.revealRequest?.id) { _, _ in
            if let t = session.revealRequest?.time { reveal(t, centered: true) }
        }
        .background(PlayheadFollower(session: session, laneWidth: laneWidth))
    }

    // MARK: Lanes

    private func lanes(width: CGFloat) -> some View {
        VStack(spacing: 1) {
            ForEach(tracks) { track in
                TrackLane(session: session, track: track, metrics: metrics, width: width, tracks: tracks, drag: $drag)
                    .frame(width: width, height: TrackLayout.height(track.kind))
            }
            Color.clear.frame(width: width, height: 30)
                .contentShape(Rectangle())
                .onTapGesture { session.selection = [] }
        }
        .coordinateSpace(name: "lanes")
        .frame(width: width)
        .clipped()
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    if magnifyStart == nil { magnifyStart = session.pixelsPerSecond }
                    zoom(to: (magnifyStart ?? session.pixelsPerSecond) * value.magnification, anchorX: nil)
                }
                .onEnded { _ in magnifyStart = nil }
        )
    }

    private var addTrackRow: some View {
        Menu {
            Button(tr("Faixa de Vídeo"), systemImage: "film") { session.perform(tr("Adicionar faixa")) { $0.addTrack(.video) } }
            Button(tr("Faixa de Áudio"), systemImage: "waveform") { session.perform(tr("Adicionar faixa")) { $0.addTrack(.audio) } }
            Button(tr("Faixa de Texto"), systemImage: "textformat") { session.perform(tr("Adicionar faixa")) { $0.addTrack(.text) } }
        } label: {
            Label(tr("Adicionar faixa"), systemImage: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    // MARK: Scrolling & zoom

    private func handleScroll(_ event: NSEvent, at point: CGPoint) -> Bool {
        let flags = event.modifierFlags
        if flags.contains(.command) || flags.contains(.option) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 6
            zoom(to: session.pixelsPerSecond * exp(delta * 0.012), anchorX: point.x)
            return true
        }
        if event.hasPreciseScrollingDeltas {
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 0.6 else { return false }
            scroll(by: -event.scrollingDeltaX)
            return true
        }
        let delta = abs(event.scrollingDeltaX) > 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        scroll(by: -delta * 10)
        return true
    }

    private func maxScroll() -> Double {
        max(0, (session.duration + 10) * session.pixelsPerSecond - Double(laneWidth) * 0.6)
    }

    private func scroll(by dx: CGFloat) {
        session.scrollX = min(max(0, session.scrollX + Double(dx)), maxScroll())
    }

    private func zoom(to pps: Double, anchorX: CGFloat?) {
        let clamped = min(max(pps, TimelineMetrics.minPPS), TimelineMetrics.maxPPS)
        let anchor = anchorX.map(Double.init) ?? min(max(0, metrics.x(session.currentTime)), laneWidth)
        let time = (Double(anchor) + session.scrollX) / session.pixelsPerSecond
        session.pixelsPerSecond = clamped
        session.scrollX = min(max(0, time * clamped - Double(anchor)), maxScroll())
    }

    private func reveal(_ t: Double, centered: Bool) {
        let x = metrics.x(t)
        if x < 0 || x > laneWidth || centered {
            session.scrollX = min(max(0, t * session.pixelsPerSecond - Double(laneWidth) * 0.3), maxScroll())
        }
    }
}

// MARK: - Toolbar

private struct TimelineToolbar: View {
    @Bindable var session: EditorSession
    let laneWidth: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Group {
                Button { session.splitAtPlayhead() } label: { Image(systemName: "scissors") }
                    .help(tr("Dividir no cursor (⌘B)"))
                Button { session.deleteSelection() } label: { Image(systemName: "trash") }
                    .help(tr("Excluir seleção (⌫)"))
                    .disabled(session.selection.isEmpty)
                Button { session.deleteSelection(ripple: true) } label: { Image(systemName: "arrow.left.to.line.compact") }
                    .help(tr("Excluir e fechar espaço (⇧⌫)"))
                    .disabled(session.selection.isEmpty)
                Button { session.duplicateSelection() } label: { Image(systemName: "plus.square.on.square") }
                    .help(tr("Duplicar (⌘D)"))
                    .disabled(session.selection.isEmpty)
                Button { session.detachAudio() } label: { Image(systemName: "waveform.badge.minus") }
                    .help(tr("Separar áudio do vídeo"))
                    .disabled(session.singleSelectedClip?.mediaID == nil)
            }
            .iconButton()

            Rectangle().fill(Theme.stroke).frame(width: 1, height: 16).padding(.horizontal, 6)

            Button { session.snapping.toggle() } label: { Image(systemName: "arrow.left.and.line.vertical.and.arrow.right") }
                .iconButton(session.snapping)
                .help(session.snapping ? tr("Ímã ativado (N)") : tr("Ímã desativado (N)"))
            Button { session.addMarker() } label: { Image(systemName: "bookmark") }
                .iconButton()
                .help(tr("Adicionar marcador (M)"))

            Spacer()

            if session.isBuilding {
                PulseBars().transition(.opacity)
            }
            if !session.selection.isEmpty {
                Text(session.selection.count == 1 ? tr("1 clipe selecionado") : tr("%@ clipes selecionados", session.selection.count))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .transition(.opacity)
            }

            Rectangle().fill(Theme.stroke).frame(width: 1, height: 16).padding(.horizontal, 6)

            Button { zoom(by: 1 / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                .iconButton().help(tr("Diminuir zoom (⌘−)"))
            Slider(value: zoomBinding, in: 0...1)
                .controlSize(.mini)
                .frame(width: 110)
                .accessibilityLabel(tr("Zoom da timeline"))
            Button { zoom(by: 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                .iconButton().help(tr("Aumentar zoom (⌘+)"))
            Button { fit() } label: { Image(systemName: "arrow.left.and.right.square") }
                .iconButton().help(tr("Ajustar à janela (⇧Z)"))
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .animation(Motion.fade, value: session.selection.isEmpty)
        .animation(Motion.fade, value: session.isBuilding)
    }

    private var zoomBinding: Binding<Double> {
        Binding {
            log(session.pixelsPerSecond / TimelineMetrics.minPPS) / log(TimelineMetrics.maxPPS / TimelineMetrics.minPPS)
        } set: { value in
            let pps = TimelineMetrics.minPPS * pow(TimelineMetrics.maxPPS / TimelineMetrics.minPPS, value)
            apply(pps)
        }
    }

    private func zoom(by factor: Double) { withAnimation(Motion.snappy) { apply(session.pixelsPerSecond * factor) } }

    private func apply(_ pps: Double) {
        let clamped = min(max(pps, TimelineMetrics.minPPS), TimelineMetrics.maxPPS)
        let anchor = min(max(0, session.currentTime * session.pixelsPerSecond - session.scrollX), Double(laneWidth))
        session.pixelsPerSecond = clamped
        session.scrollX = max(0, session.currentTime * clamped - anchor)
    }

    private func fit() {
        guard session.duration > 0 else { return }
        withAnimation(Motion.smooth) {
            session.pixelsPerSecond = min(max(Double(laneWidth) * 0.94 / session.duration, TimelineMetrics.minPPS), TimelineMetrics.maxPPS)
            session.scrollX = 0
        }
    }
}

// MARK: - Corner, ruler and playhead

private struct TimelineCorner: View {
    let session: EditorSession

    var body: some View {
        Text(TimeFormat.timecode(session.currentTime, fps: session.fps))
            .font(.audraTimecode)
            .foregroundStyle(Theme.accentBright)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .accessibilityLabel(tr("Posição atual %@", TimeFormat.clock(session.currentTime)))
    }
}

private struct RulerView: View {
    let session: EditorSession
    let metrics: TimelineMetrics
    let width: CGFloat
    @State private var scrubbing = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                draw(in: context, size: size)
            }
            ForEach(session.project.markers) { marker in
                let x = metrics.x(marker.time)
                if x > -10, x < width + 10 {
                    MarkerFlag(marker: marker, session: session)
                        .offset(x: x - 1, y: 2)
                }
            }
        }
        .frame(width: width, height: TrackLayout.rulerHeight)
        .background(Theme.base)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !scrubbing { scrubbing = true; session.pause() }
                    session.seek(to: metrics.time(value.location.x))
                }
                .onEnded { _ in scrubbing = false }
        )
        .accessibilityElement()
        .accessibilityLabel(tr("Régua de tempo"))
        .accessibilityValue(TimeFormat.clock(session.currentTime))
        .accessibilityAdjustableAction { direction in
            session.jump(by: direction == .increment ? 1 : -1)
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let pps = metrics.pixelsPerSecond
        let steps: [Double] = [1.0 / 30, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        let major = steps.first { $0 * pps >= 84 } ?? 3600
        let minorDivisions: Double = major >= 60 ? 6 : major >= 1 ? 5 : 4
        let minor = major / minorDivisions
        let range = metrics.visibleRange(width: size.width)
        var t = (range.lowerBound / minor).rounded(.down) * minor
        while t <= range.upperBound + minor {
            let x = metrics.x(t)
            let isMajor = abs((t / major).rounded() * major - t) < minor / 10
            var path = Path()
            path.move(to: CGPoint(x: x, y: size.height))
            path.addLine(to: CGPoint(x: x, y: size.height - (isMajor ? 11 : 5)))
            context.stroke(path, with: .color(Color.white.opacity(isMajor ? 0.32 : 0.14)), lineWidth: 1)
            if isMajor {
                let label = major < 1 ? String(format: "%@.%d", TimeFormat.ruler(t.rounded(.down)), Int(((t - t.rounded(.down)) * 10).rounded()))
                    : TimeFormat.ruler(t)
                context.draw(Text(label).font(.system(size: 9.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.textTertiary),
                             at: CGPoint(x: x + 4, y: 9), anchor: .leading)
            }
            t += minor
        }
        // Project end marker.
        let endX = metrics.x(session.duration)
        if endX > 0, endX < size.width {
            context.fill(Path(CGRect(x: endX, y: 0, width: 1, height: size.height)), with: .color(Theme.textQuaternary))
        }
    }
}

private struct MarkerFlag: View {
    let marker: TimelineMarker
    let session: EditorSession
    @State private var hovering = false

    var body: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 10))
            .foregroundStyle(hovering ? Theme.accentBright : Theme.warning.opacity(0.85))
            .onHover { hovering = $0 }
            .help(marker.title)
            .onTapGesture { session.seek(to: marker.time) }
            .contextMenu {
                Button(tr("Ir para “%@”", marker.title)) { session.seek(to: marker.time) }
                Button(tr("Remover Marcador"), role: .destructive) {
                    session.perform(tr("Remover marcador")) { $0.markers.removeAll { $0.id == marker.id } }
                }
            }
    }
}

private struct PlayheadOverlay: View {
    let session: EditorSession
    let metrics: TimelineMetrics
    let height: CGFloat
    let snapTime: Double?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(session.highlightedRanges.enumerated()), id: \.offset) { _, range in
                Rectangle()
                    .fill(Theme.highlight.opacity(0.10))
                    .overlay(alignment: .top) { Rectangle().fill(Theme.highlight.opacity(0.8)).frame(height: 2) }
                    .frame(width: max(2, metrics.width(range.upperBound - range.lowerBound)), height: height)
                    .offset(x: metrics.x(range.lowerBound))
            }
            if let snapTime {
                Rectangle()
                    .fill(Theme.highlight)
                    .frame(width: 1, height: height)
                    .offset(x: metrics.x(snapTime))
            }
            let x = metrics.x(session.currentTime)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Theme.accentBright)
                    .frame(width: 1.5, height: height)
                    .shadow(color: Theme.accent.opacity(0.9), radius: 3)
                PlayheadCap()
                    .fill(Theme.accentBright)
                    .frame(width: 13, height: 15)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            }
            .offset(x: x - 6.5)
            .opacity(x < -8 ? 0 : 1)
        }
        .task(id: session.highlightedRanges) {
            guard !session.highlightedRanges.isEmpty else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(Motion.fade) { session.highlightedRanges = [] }
        }
    }
}

private struct PlayheadCap: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 2))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 2, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 2), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 5))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 5))
        path.closeSubpath()
        return path
    }
}

/// Keeps the playhead on screen during playback by paging the timeline.
private struct PlayheadFollower: View {
    let session: EditorSession
    let laneWidth: CGFloat

    var body: some View {
        Color.clear
            .onChange(of: session.currentTime) { _, t in
                guard session.isPlaying else { return }
                let x = t * session.pixelsPerSecond - session.scrollX
                if x > Double(laneWidth) - 40 || x < 0 {
                    withAnimation(Motion.smooth) { session.scrollX = max(0, t * session.pixelsPerSecond - Double(laneWidth) * 0.15) }
                }
            }
    }
}

// MARK: - Track header

private struct TrackHeader: View {
    let session: EditorSession
    let track: EditTrack
    @State private var renaming = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 8)
            Image(systemName: track.role == .subtitles ? "captions.bubble" : track.kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 16)
            if renaming {
                TextField(tr("Nome"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .onSubmit { commitRename() }
                    .onExitCommand { renaming = false }
            } else {
                Text(track.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(track.isHidden ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { draft = track.name; renaming = true }
            }
            Spacer(minLength: 2)
            if track.kind != .text {
                toggle(track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: track.isMuted,
                       help: track.isMuted ? tr("Ativar som da faixa") : tr("Silenciar faixa")) {
                    session.updateTrack(track.id, track.isMuted ? tr("Ativar som da faixa") : tr("Silenciar faixa")) { $0.isMuted.toggle() }
                }
            }
            if track.kind != .audio {
                toggle(track.isHidden ? "eye.slash.fill" : "eye.fill", active: track.isHidden,
                       help: track.isHidden ? tr("Mostrar faixa") : tr("Ocultar faixa")) {
                    session.updateTrack(track.id, track.isHidden ? tr("Mostrar faixa") : tr("Ocultar faixa")) { $0.isHidden.toggle() }
                }
            }
            toggle(track.isLocked ? "lock.fill" : "lock.open.fill", active: track.isLocked,
                   help: track.isLocked ? tr("Desbloquear faixa") : tr("Bloquear faixa")) {
                session.updateTrack(track.id, track.isLocked ? tr("Desbloquear faixa") : tr("Bloquear faixa")) { $0.isLocked.toggle() }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(maxHeight: .infinity)
        .background(Theme.base)
        .contextMenu {
            Button(tr("Renomear Faixa…")) { draft = track.name; renaming = true }
            Divider()
            Button(tr("Remover Faixa"), role: .destructive) { session.removeTrack(track.id) }
                .disabled(session.project.tracks.filter { $0.kind == track.kind }.count <= 1 && track.kind != .text)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Faixa %@", track.name))
    }

    private var accent: Color {
        switch track.kind {
        case .video: Theme.videoClipEdge
        case .audio: Theme.audioClipEdge
        case .text: Theme.textClipEdge
        }
    }

    private func toggle(_ symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(IconButtonStyle(isActive: active, size: 22, tint: Theme.warning))
            .help(help)
            .accessibilityLabel(help)
    }

    private func commitRename() {
        renaming = false
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != track.name else { return }
        session.updateTrack(track.id, tr("Renomear faixa")) { $0.name = name }
    }
}

// MARK: - Lane

private struct TrackLane: View {
    let session: EditorSession
    let track: EditTrack
    let metrics: TimelineMetrics
    let width: CGFloat
    let tracks: [EditTrack]
    @Binding var drag: TimelineDrag?
    @State private var dropTargeted = false

    var body: some View {
        let height = TrackLayout.height(track.kind)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(track.isLocked ? Theme.canvas.opacity(0.9) : Theme.canvas)
                .overlay {
                    if track.isLocked {
                        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.textQuaternary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { location in
                    session.selection = []
                    session.seek(to: metrics.time(location.x))
                }

            ForEach(visibleClips, id: \.clip.id) { item in
                ClipView(session: session, clip: item.clip, track: track, displayStart: item.start, displayEnd: item.end,
                         metrics: metrics, laneWidth: width, isGhost: item.ghost, isValid: drag?.isValid ?? true,
                         tracks: tracks, drag: $drag)
                    .frame(height: height - 6)
                    // Clips wider than the lane must stay leading-aligned, not centered.
                    .frame(width: width, alignment: .leading)
                    .offset(y: 3)
            }

            if dropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .background(Theme.accent.opacity(0.08))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .animation(Motion.fade, value: dropTargeted)
        .dropDestination(for: String.self) { items, location in
            let time = metrics.time(location.x)
            var handled = false
            for item in items {
                if let id = UUID(uuidString: item), session.project.mediaItem(id) != nil {
                    session.addToTimeline(id, at: time, trackID: track.id)
                    handled = true
                } else if let url = URL(string: item), url.isFileURL {
                    session.importMedia([url], at: time, trackID: track.id)
                    handled = true
                }
            }
            return handled
        } isTargeted: { dropTargeted = $0 }
    }

    private struct Item {
        let clip: EditClip
        let start: Double
        let end: Double
        let ghost: Bool
    }

    /// Clips to draw, with drag/trim previews applied.
    private var visibleClips: [Item] {
        let range = metrics.visibleRange(width: width)
        var items: [Item] = []
        var clips = track.clips.map { ($0, false) }
        if let drag, drag.mode == .move, let target = drag.targetTrack, target == track.id,
           let anchor = session.project.clip(drag.anchor), !track.clips.contains(where: { $0.id == anchor.id }) {
            clips.append((anchor, true))
        }
        for (clip, ghost) in clips {
            var start = clip.start, end = clip.end
            if let drag, drag.clipIDs.contains(clip.id) {
                switch drag.mode {
                case .move:
                    if let target = drag.targetTrack, target != track.id, !ghost { continue }
                    start += drag.delta
                    end += drag.delta
                case .trimStart:
                    var preview = session.project
                    preview.trimStart(clip.id, to: clip.start + drag.delta)
                    if let updated = preview.clip(clip.id) { start = updated.start }
                case .trimEnd:
                    var preview = session.project
                    preview.trimEnd(clip.id, to: clip.end + drag.delta)
                    if let updated = preview.clip(clip.id) { end = updated.end }
                }
            }
            guard end >= range.lowerBound - 1, start <= range.upperBound + 1 else { continue }
            items.append(Item(clip: clip, start: start, end: end, ghost: ghost))
        }
        return items
    }
}

// MARK: - Clip

private struct ClipView: View {
    let session: EditorSession
    let clip: EditClip
    let track: EditTrack
    let displayStart: Double
    let displayEnd: Double
    let metrics: TimelineMetrics
    let laneWidth: CGFloat
    let isGhost: Bool
    let isValid: Bool
    let tracks: [EditTrack]
    @Binding var drag: TimelineDrag?
    @State private var hovering = false

    private var isSelected: Bool { session.selection.contains(clip.id) }
    private var media: MediaItem? { session.project.mediaItem(clip.mediaID) }
    private var isDragging: Bool { drag?.clipIDs.contains(clip.id) == true }

    var body: some View {
        let fullX = metrics.x(displayStart)
        let fullWidth = max(2, metrics.width(displayEnd - displayStart))
        // Only the on-screen part is laid out, so hour-long clips never create huge layers.
        let visibleX = max(fullX, -24)
        let visibleEnd = min(fullX + fullWidth, laneWidth + 24)
        let width = max(2, visibleEnd - visibleX)
        let hiddenLeading = visibleX - fullX

        content(width: width, hiddenLeading: hiddenLeading)
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .leading) { if fullX >= -24 { trimHandle(.trimStart) } }
            .overlay(alignment: .trailing) { if fullX + fullWidth <= laneWidth + 24 { trimHandle(.trimEnd) } }
            .shadow(color: isSelected ? Theme.accent.opacity(0.45) : .black.opacity(0.25), radius: isSelected ? 6 : 2, y: 1)
            .opacity(isGhost || (isDragging && drag?.mode == .move) ? 0.85 : 1)
            .scaleEffect(isDragging && drag?.mode == .move ? 1.01 : 1)
            .offset(x: visibleX)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.snappy, value: isSelected)
            .gesture(moveGesture)
            .simultaneousGesture(TapGesture().onEnded { select() })
            .contextMenu { contextMenu }
            .help(helpText)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { select() }
    }

    // MARK: Drawing

    @ViewBuilder
    private func content(width: CGFloat, hiddenLeading: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            fill
            if track.kind == .video, let media {
                Canvas { context, size in
                    drawThumbnails(context, size: size, media: media, hiddenLeading: hiddenLeading)
                    if media.hasAudio, !clip.audioMuted {
                        drawWave(context, rect: CGRect(x: 0, y: size.height * 0.7, width: size.width, height: size.height * 0.3),
                                 media: media, hiddenLeading: hiddenLeading, color: .white.opacity(0.55))
                    }
                }
            } else if track.kind == .audio, let media {
                Canvas { context, size in
                    drawWave(context, rect: CGRect(x: 0, y: 3, width: size.width, height: size.height - 6), media: media,
                             hiddenLeading: hiddenLeading, color: Theme.audioWave.opacity(clip.audioMuted ? 0.3 : 0.9))
                }
            }
            if drag?.isValid == false, isDragging {
                Theme.danger.opacity(0.35)
            }
            if hovering || isSelected {
                Color.white.opacity(0.05)
            }
            labels
            if clip.transition != nil, hiddenLeading < 1 {
                TransitionBadge(kind: clip.transition!.kind)
                    .padding(3)
            }
        }
    }

    private var fill: some View {
        let base: Color = switch track.kind {
        case .video: Theme.videoClip
        case .audio: Theme.audioClip
        case .text: Theme.textClip
        }
        return LinearGradient(colors: [base.opacity(0.98), base.opacity(0.78)], startPoint: .top, endPoint: .bottom)
            .opacity(track.isHidden && track.kind != .audio ? 0.4 : 1)
    }

    private var labels: some View {
        HStack(spacing: 4) {
            if track.kind == .text {
                Image(systemName: clip.text?.showBackground == true ? "captions.bubble.fill" : "textformat")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(title)
                .lineLimit(1)
            if abs(clip.speed - 1) > 0.001 {
                Text(clip.speed.formatted(.number.precision(.fractionLength(0...2))) + tr("×"))
                    .padding(.horizontal, 4)
                    .background(Color.black.opacity(0.35), in: Capsule())
            }
            if clip.audioMuted, track.kind != .text, media?.hasAudio == true {
                Image(systemName: "speaker.slash.fill").font(.system(size: 8.5))
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.92))
        .shadow(color: .black.opacity(0.6), radius: 2)
        .padding(.leading, clip.transition != nil ? 22 : 10)
        .padding(.trailing, 8)
        .padding(.top, track.kind == .text ? 0 : 4)
        .frame(maxHeight: track.kind == .text ? .infinity : nil, alignment: .center)
    }

    private var title: String {
        if let text = clip.text { return text.content.replacingOccurrences(of: "\n", with: " ") }
        return clip.label ?? media?.name ?? tr("Mídia ausente")
    }

    private var borderColor: Color {
        if isSelected { return Theme.accentBright }
        switch track.kind {
        case .video: return Theme.videoClipEdge.opacity(0.7)
        case .audio: return Theme.audioClipEdge.opacity(0.7)
        case .text: return Theme.textClipEdge.opacity(0.7)
        }
    }

    private func drawThumbnails(_ context: GraphicsContext, size: CGSize, media: MediaItem, hiddenLeading: CGFloat) {
        guard let strip = MediaCache.shared.thumbnails(for: media) else { return }
        let thumbHeight = size.height * 0.7
        let aspect = media.height > 0 ? Double(media.width) / Double(media.height) : 16 / 9
        let tileWidth = max(24, thumbHeight * aspect)
        let pps = metrics.pixelsPerSecond
        var x = -hiddenLeading.truncatingRemainder(dividingBy: tileWidth)
        while x < size.width {
            let center = Double(x + hiddenLeading + tileWidth / 2)
            let source = clip.sourceIn + center / pps * clip.speed
            if let image = strip.image(at: min(source, clip.sourceOut)) {
                context.draw(Image(decorative: image, scale: 1), in: CGRect(x: x, y: 0, width: tileWidth, height: thumbHeight))
            }
            x += tileWidth
        }
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: thumbHeight)),
                     with: .linearGradient(Gradient(colors: [.black.opacity(0.35), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 18)))
    }

    private func drawWave(_ context: GraphicsContext, rect: CGRect, media: MediaItem, hiddenLeading: CGFloat, color: Color) {
        guard let wave = MediaCache.shared.waveform(for: media) else { return }
        let pps = metrics.pixelsPerSecond
        let step: CGFloat = 2
        var path = Path()
        var x: CGFloat = 0
        let mid = rect.midY
        let gain = clip.volume
        while x < rect.width {
            let t0 = clip.sourceIn + Double(x + hiddenLeading) / pps * clip.speed
            let t1 = t0 + Double(step) / pps * clip.speed
            let peak = CGFloat(min(1, Double(wave.peak(from: t0, to: t1)) * gain))
            let h = max(0.5, peak * rect.height / 2)
            path.addRect(CGRect(x: x, y: mid - h, width: step * 0.7, height: h * 2))
            x += step
        }
        context.fill(path, with: .color(color))
    }

    // MARK: Interaction

    private func select() {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.shift) {
            if isSelected { session.selection.remove(clip.id) } else { session.selection.insert(clip.id) }
        } else {
            session.selection = [clip.id]
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("lanes"))
            .onChanged { value in
                guard !track.isLocked else { return }
                if drag == nil {
                    if !isSelected { session.selection = [clip.id] }
                    let ids = session.selection.contains(clip.id) ? session.selection : [clip.id]
                    drag = TimelineDrag(mode: .move, anchor: clip.id, clipIDs: ids)
                    session.pause()
                }
                guard var current = drag, current.mode == .move else { return }
                var delta = Double(value.translation.width) / metrics.pixelsPerSecond
                let movers = current.clipIDs.compactMap { session.project.clip($0) }
                let earliest = movers.map(\.start).min() ?? 0
                delta = max(delta, -earliest)
                current.snapTime = nil
                if session.snapping, let snap = snapDelta(for: movers, delta: delta, excluding: current.clipIDs) {
                    delta = snap.delta
                    current.snapTime = snap.time
                }
                current.delta = delta
                current.targetTrack = current.clipIDs.count == 1 ? trackAt(y: value.location.y) : nil
                var preview = session.project
                current.isValid = preview.move(current.clipIDs, by: delta, toTrack: current.targetTrack)
                drag = current
            }
            .onEnded { _ in
                guard let current = drag, current.mode == .move else { drag = nil; return }
                drag = nil
                guard abs(current.delta) > 1e-4 || (current.targetTrack != nil && current.targetTrack != track.id) else { return }
                var moved = false
                session.perform(current.clipIDs.count == 1 ? tr("Mover clipe") : tr("Mover clipes")) {
                    moved = $0.move(current.clipIDs, by: current.delta, toTrack: current.targetTrack)
                }
                if !moved {
                    NSSound.beep()
                }
            }
    }

    private func trimHandle(_ mode: TimelineDrag.Mode) -> some View {
        TrimHandle(isLeading: mode == .trimStart, visible: hovering || isSelected)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("lanes"))
                    .onChanged { value in
                        guard !track.isLocked else { return }
                        if drag == nil {
                            session.selection = [clip.id]
                            drag = TimelineDrag(mode: mode, anchor: clip.id, clipIDs: [clip.id])
                            session.pause()
                        }
                        guard var current = drag else { return }
                        var delta = Double(value.translation.width) / metrics.pixelsPerSecond
                        current.snapTime = nil
                        if session.snapping {
                            let edge = (mode == .trimStart ? clip.start : clip.end) + delta
                            if let target = snapTarget(near: edge, excluding: [clip.id]) {
                                delta = target - (mode == .trimStart ? clip.start : clip.end)
                                current.snapTime = target
                            }
                        }
                        current.delta = delta
                        drag = current
                    }
                    .onEnded { _ in
                        guard let current = drag else { return }
                        drag = nil
                        let clipID = clip.id
                        if mode == .trimStart {
                            let target = clip.start + current.delta
                            session.perform(tr("Aparar início")) { $0.trimStart(clipID, to: target) }
                        } else {
                            let target = clip.end + current.delta
                            session.perform(tr("Aparar fim")) { $0.trimEnd(clipID, to: target) }
                        }
                    }
            )
    }

    private func trackAt(y: CGFloat) -> UUID? {
        var top: CGFloat = 0
        for item in tracks {
            let height = TrackLayout.height(item.kind) + 1
            if y >= top && y < top + height { return item.id }
            top += height
        }
        return nil
    }

    private func snapCandidates(excluding: Set<UUID>) -> [Double] {
        var candidates: [Double] = [0, session.currentTime]
        for track in session.project.tracks {
            for clip in track.clips where !excluding.contains(clip.id) {
                candidates.append(clip.start)
                candidates.append(clip.end)
            }
        }
        candidates += session.project.markers.map(\.time)
        return candidates
    }

    private func snapTarget(near t: Double, excluding: Set<UUID>) -> Double? {
        let threshold = 8 / metrics.pixelsPerSecond
        return snapCandidates(excluding: excluding)
            .map { ($0, abs($0 - t)) }
            .filter { $0.1 < threshold }
            .min { $0.1 < $1.1 }?.0
    }

    private func snapDelta(for movers: [EditClip], delta: Double, excluding: Set<UUID>) -> (delta: Double, time: Double)? {
        let threshold = 8 / metrics.pixelsPerSecond
        let candidates = snapCandidates(excluding: excluding)
        var best: (delta: Double, time: Double, distance: Double)?
        for clip in movers {
            for edge in [clip.start + delta, clip.end + delta] {
                for candidate in candidates {
                    let distance = abs(candidate - edge)
                    if distance < threshold, distance < (best?.distance ?? .infinity) {
                        best = (delta + (candidate - edge), candidate, distance)
                    }
                }
            }
        }
        return best.map { ($0.delta, $0.time) }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(tr("Dividir no Cursor")) { session.selection = [clip.id]; session.splitAtPlayhead() }
        Button(tr("Duplicar")) { session.selection = [clip.id]; session.duplicateSelection() }
        if track.kind == .video, media?.hasAudio == true {
            Button(tr("Separar Áudio")) { session.selection = [clip.id]; session.detachAudio() }
            Button(tr("Substituir Áudio…")) { session.replaceAudio(of: clip.id) }
        }
        if track.kind != .text {
            Button(clip.audioMuted ? tr("Ativar Áudio do Clipe") : tr("Silenciar Clipe")) {
                session.update(clip.id, clip.audioMuted ? tr("Ativar áudio") : tr("Silenciar clipe")) { $0.audioMuted.toggle() }
            }
            Menu(tr("Velocidade")) {
                ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4], id: \.self) { speed in
                    Button(speed.formatted() + tr("×")) { session.setSpeed(clip.id, speed) }
                }
            }
        }
        if track.kind == .video {
            Menu(tr("Transição de Entrada")) {
                ForEach(TransitionKind.allCases) { kind in
                    Button(kind.label) {
                        session.update(clip.id, tr("Adicionar transição")) { $0.transition = ClipTransition(kind: kind, duration: $0.transition?.duration ?? 0.75) }
                    }
                }
                if clip.transition != nil {
                    Divider()
                    Button(tr("Remover Transição")) { session.update(clip.id, tr("Remover transição")) { $0.transition = nil } }
                }
            }
        }
        Divider()
        Button(tr("Excluir"), role: .destructive) { session.selection = [clip.id]; session.deleteSelection() }
        Button(tr("Excluir e Fechar Espaço"), role: .destructive) { session.selection = [clip.id]; session.deleteSelection(ripple: true) }
    }

    private var helpText: String {
        tr("%@\nInício %@ · Duração %@ s", title, TimeFormat.clock(clip.start), String(format: "%.1f", clip.duration))
    }

    private var accessibilityText: String {
        tr("%@: %@, de %@ a %@", track.kind.label, title, TimeFormat.clock(clip.start), TimeFormat.clock(clip.end))
    }
}

private struct TrimHandle: View {
    let isLeading: Bool
    let visible: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.white.opacity(hovering ? 0.95 : 0.6))
                .frame(width: 3, height: 16)
                .opacity(visible || hovering ? 1 : 0)
        }
        .frame(width: 9)
        .frame(maxHeight: .infinity)
        .background(hovering ? Theme.accent.opacity(0.55) : .clear)
        .contentShape(Rectangle())
        .pointerStyle(.frameResize(position: isLeading ? .leading : .trailing))
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .accessibilityHidden(true)
    }
}

private struct TransitionBadge: View {
    let kind: TransitionKind
    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .help(tr("Transição: %@", kind.label))
    }
}
