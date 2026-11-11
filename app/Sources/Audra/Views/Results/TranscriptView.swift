import SwiftUI

struct TranscriptView: View {
    @Environment(AppModel.self) private var model
    let document: TranscriptDocument
    let player: PlayerController

    @State private var follow = true
    @State private var showFind = false
    @State private var query = ""
    @State private var matchIndex = 0
    @State private var editingID: UUID?
    @FocusState private var findFocused: Bool

    private var activeID: UUID? { document.activeSegmentID(at: player.currentTime) }

    private var matches: [UUID] {
        guard query.count >= 2 else { return [] }
        return document.segments.filter { $0.text.matches(query) }.map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(document.segments) { segment in
                            SegmentRow(
                                segment: segment,
                                isActive: segment.id == activeID,
                                isCurrentMatch: !matches.isEmpty && matches[safe: matchIndex] == segment.id,
                                query: query.count >= 2 ? query : "",
                                isEditing: editingID == segment.id,
                                onSeek: { player.seek(to: segment.start, play: true); follow = true },
                                onEdit: { editingID = segment.id },
                                onCommit: { text in document.update(segment.id, text: text); editingID = nil },
                                onCancelEdit: { editingID = nil }
                            )
                            .id(segment.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { follow = false }
                }
                .onChange(of: activeID) { _, id in
                    guard follow, editingID == nil, let id else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.35)) }
                }
                .onChange(of: matchIndex) { _, _ in scrollToMatch(proxy) }
                .onChange(of: query) { _, _ in matchIndex = 0; scrollToMatch(proxy) }
                .onChange(of: follow) { _, on in
                    if on, let id = activeID { withAnimation { proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.35)) } }
                }
            }
        }
        .onChange(of: model.findRequest) { _, _ in
            showFind = true
            findFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if showFind {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(tr("Buscar na transcrição"), text: $query)
                        .textFieldStyle(.plain)
                        .focused($findFocused)
                        .onSubmit { next(1) }
                        .onKeyPress(.escape) { closeFind(); return .handled }
                    if !query.isEmpty {
                        Text(matches.isEmpty ? tr("Nenhum") : tr("%@ de %@", matchIndex + 1, matches.count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Button { next(-1) } label: { Image(systemName: "chevron.up") }
                            .disabled(matches.isEmpty)
                            .accessibilityLabel(tr("Resultado anterior"))
                        Button { next(1) } label: { Image(systemName: "chevron.down") }
                            .disabled(matches.isEmpty)
                            .accessibilityLabel(tr("Próximo resultado"))
                    }
                    Button(tr("OK")) { closeFind() }
                        .accessibilityLabel(tr("Fechar busca"))
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Text(tr("Transcrição"))
                    .font(.headline)
                Text(tr("%@ trechos", document.segments.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showFind = true; findFocused = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help(tr("Buscar (⌘F)"))
                    .accessibilityLabel(tr("Buscar na transcrição"))
            }

            Button {
                follow.toggle()
            } label: {
                Label(follow ? tr("Seguindo") : tr("Seguir"), systemImage: follow ? "dot.radiowaves.left.and.right" : "arrow.down.to.line")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(follow ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help(tr("Acompanhar a reprodução automaticamente"))
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func next(_ step: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + step + matches.count) % matches.count
    }

    private func scrollToMatch(_ proxy: ScrollViewProxy) {
        guard let id = matches[safe: matchIndex] else { return }
        follow = false
        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
    }

    private func closeFind() {
        showFind = false
        query = ""
    }
}

private struct SegmentRow: View {
    let segment: TranscriptSegment
    let isActive: Bool
    let isCurrentMatch: Bool
    let query: String
    let isEditing: Bool
    let onSeek: () -> Void
    let onEdit: () -> Void
    let onCommit: (String) -> Void
    let onCancelEdit: () -> Void

    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Button(action: onSeek) {
                Text(TimeFormat.clock(segment.start))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .help(tr("Ir para %@", TimeFormat.clock(segment.start)))
            .frame(minWidth: 52, alignment: .leading)

            if isEditing {
                TextField(tr("Texto do trecho"), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineSpacing(3)
                    .focused($focused)
                    .onAppear { draft = segment.text; focused = true }
                    .onSubmit { onCommit(draft) }
                    .onKeyPress(.escape) { onCancelEdit(); return .handled }
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.tint.opacity(0.6)))
            } else {
                Text(highlighted)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.82)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if segment.edited {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help(tr("Editado manualmente"))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onSeek() } }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: isActive)
        .contextMenu {
            Button(tr("Ir para Este Momento")) { onSeek() }
            Button(tr("Editar Trecho")) { onEdit() }
            Divider()
            Button(tr("Copiar Trecho")) { Exporter.copy(segment.text) }
            Button(tr("Copiar com Timestamp")) { Exporter.copy("[\(TimeFormat.clock(segment.start))] \(segment.text)") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TimeFormat.clock(segment.start)): \(segment.text)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAction(named: Text(tr("Ir para este momento")), onSeek)
        .accessibilityAction(named: Text(tr("Editar")), onEdit)
    }

    private var background: Color {
        if isEditing { return .clear }
        if isActive { return Theme.accent.opacity(0.18) }
        if isCurrentMatch { return Theme.highlight.opacity(0.14) }
        return hovering ? .primary.opacity(0.04) : .clear
    }

    private var highlighted: AttributedString {
        var text = AttributedString(segment.text)
        guard !query.isEmpty else { return text }
        for range in segment.text.ranges(of: query) {
            guard let lower = AttributedString.Index(range.lowerBound, within: text),
                  let upper = AttributedString.Index(range.upperBound, within: text) else { continue }
            text[lower..<upper].backgroundColor = Theme.highlight.opacity(0.4)
            text[lower..<upper].foregroundColor = .primary
        }
        return text
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
