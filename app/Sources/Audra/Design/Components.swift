import SwiftUI

// MARK: - Buttons

enum AudraButtonKind { case primary, secondary, ghost, destructive }

/// Text buttons with hover, press and disabled states shared across the app.
struct AudraButtonStyle: ButtonStyle {
    var kind: AudraButtonKind = .secondary
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        AudraButtonBody(configuration: configuration, kind: kind, large: large)
    }
}

private struct AudraButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: AudraButtonKind
    let large: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(.system(size: large ? 14 : 12.5, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, large ? 18 : 12)
            .frame(height: large ? 38 : 28)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(alignment: .top) {
                if kind == .primary {
                    // Hairline top highlight gives the button a pressed-metal edge without glow.
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                }
            }
            .shadow(color: kind == .primary && enabled ? Theme.accentDeep.opacity(hovering ? 0.55 : 0.35) : .clear,
                    radius: hovering ? 8 : 4, y: 2)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.04 : hovering && enabled ? 0.04 : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.snappy, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .destructive: Theme.danger
        case .secondary, .ghost: Theme.textPrimary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            Theme.accentGradient
        case .secondary:
            hovering ? Theme.controlHover : Theme.control.opacity(0.7)
        case .ghost:
            Color.white.opacity(hovering ? 0.06 : 0)
        case .destructive:
            Theme.danger.opacity(hovering ? 0.16 : 0.1)
        }
    }

    private var border: Color {
        switch kind {
        case .primary: .black.opacity(0.25)
        case .secondary: Theme.stroke
        case .ghost: .clear
        case .destructive: Theme.danger.opacity(0.25)
        }
    }
}

/// Square icon button used in toolbars, the monitor and the timeline.
struct IconButtonStyle: ButtonStyle {
    var isActive = false
    var size: CGFloat = 28
    var tint: Color = Theme.accentBright

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, isActive: isActive, size: size, tint: tint)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool
    let size: CGFloat
    let tint: Color
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(.system(size: size * 0.46, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isActive ? tint : hovering ? Theme.textPrimary : Theme.textSecondary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small + 1, style: .continuous)
                    .fill(isActive ? tint.opacity(0.16) : Color.white.opacity(hovering && enabled ? 0.07 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(enabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.snappy, value: configuration.isPressed)
            .animation(Motion.snappy, value: isActive)
    }
}

extension View {
    func iconButton(_ isActive: Bool = false, size: CGFloat = 28) -> some View {
        buttonStyle(IconButtonStyle(isActive: isActive, size: size))
    }
}

// MARK: - Surfaces

extension View {
    /// Raised surface with a hairline border and soft depth.
    func panelSurface(radius: CGFloat = Theme.Radius.large, fill: Color = Theme.elevated, shadow: Bool = true) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .shadow(color: .black.opacity(shadow ? 0.35 : 0), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    /// Hover tint for list rows and clickable regions.
    func hoverHighlight(radius: CGFloat = Theme.Radius.medium, isSelected: Bool = false) -> some View {
        modifier(HoverHighlight(radius: radius, isSelected: isSelected))
    }
}

private struct HoverHighlight: ViewModifier {
    let radius: CGFloat
    let isSelected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isSelected ? Theme.accentSoft : Color.white.opacity(hovering ? 0.045 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.45) : .clear, lineWidth: 1)
            )
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.snappy, value: isSelected)
    }
}

// MARK: - Labels

struct SectionLabel: View {
    let title: String
    var trailing: AnyView? = nil

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Theme.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct Badge: View {
    let text: String
    var color: Color = Theme.accentBright
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Segmented tabs

/// Pill-shaped segmented control with a sliding selection indicator.
struct PillTabs<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        var symbol: String? = nil
        var id: Value { value }
    }

    @Binding var selection: Value
    let items: [Item]
    var compact = false
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item.value == selection
                Button {
                    withAnimation(Motion.snappy) { selection = item.value }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                        }
                        if !compact || item.symbol == nil || selected { Text(item.title).lineLimit(1).fixedSize() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, compact ? 9 : 12)
                    .frame(height: 24)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.controlHover)
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.strokeStrong))
                                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.base, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
    }
}

// MARK: - Progress

struct AudraProgressBar: View {
    let value: Double
    var height: CGFloat = 6
    var animated = true
    @State private var phase: CGFloat = -0.4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * CGFloat(min(1, max(0, value)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accentDeep, Theme.accent, Theme.accentBright],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, width))
                    .overlay {
                        if animated {
                            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: 60)
                                .offset(x: phase * max(width, 1))
                                .blendMode(.plusLighter)
                        }
                    }
                    .clipShape(Capsule())
                    .shadow(color: Theme.accent.opacity(0.5), radius: 6)
                    .animation(Motion.smooth, value: value)
            }
        }
        .frame(height: height)
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1.2 }
        }
        .accessibilityElement()
        .accessibilityValue(tr("%@ por cento", Int(value * 100)))
    }
}

/// Indeterminate activity indicator: three bars pulsing like a level meter.
struct PulseBars: View {
    var color: Color = Theme.accentBright
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: animate ? 12 : 4)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.15), value: animate)
            }
        }
        .frame(height: 12)
        .onAppear { animate = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Empty states

struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 64, height: 64)
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.accentBright)
            }
            VStack(spacing: 5) {
                Text(title).font(.audraHeadline).foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320)
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Inspector controls

/// Labeled slider with a live value readout, used throughout the inspector.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { String(format: "%.2f", $0) }
    var onEditingChanged: (Bool) -> Void = { _ in }
    var resetValue: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(format(value))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if let resetValue, abs(value - resetValue) > 0.0001 {
                    Button {
                        onEditingChanged(true)
                        withAnimation(Motion.snappy) { value = resetValue }
                        onEditingChanged(false)
                    } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(IconButtonStyle(size: 18))
                        .help(tr("Restaurar valor padrão"))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            if let step {
                Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
                    .controlSize(.small)
            } else {
                Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                    .controlSize(.small)
            }
        }
        .animation(Motion.snappy, value: resetValue.map { abs(value - $0) > 0.0001 })
        .accessibilityElement(children: .combine)
    }
}

/// Collapsible inspector group.
struct InspectorGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentBright)
                        .frame(width: 16)
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 12) { content }
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .clipped()
    }
}
