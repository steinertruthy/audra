import AppKit
import SwiftUI

/// Window state the chrome reacts to.
@MainActor
@Observable
final class WindowState {
    static let shared = WindowState()
    /// In full screen the traffic lights are hidden, so the top bar reclaims their space.
    var isFullScreen = false
}

/// Custom window top bar. Sits under the traffic lights, drags the window, and zooms on double-click.
struct TopBar<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var center: Center
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 12)
                trailing
            }
            center
        }
        .padding(.leading, WindowState.shared.isFullScreen ? 16 : Theme.trafficLightInset)
        .padding(.trailing, 14)
        .transaction { $0.animation = nil }
        .frame(height: Theme.topBarHeight)
        .frame(maxWidth: .infinity)
        .background {
            Theme.canvas
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .onTapGesture(count: 2) { NSApp.keyWindow?.zoom(nil) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

extension TopBar where Center == EmptyView {
    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.center = EmptyView()
        self.trailing = trailing()
    }
}

/// Text navigation tabs with a sliding indicator (Linear-style).
struct NavTabs<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        var count: Int? = nil
        var id: Value { value }
    }

    let selection: Value?
    let items: [Item]
    let onSelect: (Value) -> Void
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item.value == selection
                Button { onSelect(item.value) } label: {
                    HStack(spacing: 6) {
                        Text(item.title)
                        if let count = item.count, count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(selected ? Theme.textSecondary : Theme.textQuaternary)
                        }
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.control)
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.stroke))
                                .matchedGeometryEffect(id: "nav", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(Motion.snappy, value: selection)
    }
}

/// Compact search field with a keyboard hint.
struct SearchField: View {
    @Binding var text: String
    var prompt = tr("Buscar")
    var width: CGFloat = 240
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(focus)
                .onExitCommand { text = ""; focus.wrappedValue = false }
            if text.isEmpty {
                Text("⌘K")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textQuaternary)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.stroke))
            } else {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel(tr("Limpar busca"))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 30)
        .background(Theme.base, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focus.wrappedValue ? Theme.accent.opacity(0.7) : Theme.stroke)
        )
        .animation(Motion.hover, value: focus.wrappedValue)
    }
}

/// Small rounded status label.
struct StatusChip: View {
    let status: ProcessingStatus
    var progress: Double? = nil

    var body: some View {
        HStack(spacing: 5) {
            switch status {
            case .completed:
                Circle().fill(Theme.success).frame(width: 6, height: 6)
                Text(tr("Concluído"))
            case .failed:
                Circle().fill(Theme.danger).frame(width: 6, height: 6)
                Text(tr("Falhou"))
            case .cancelled:
                Circle().fill(Theme.textTertiary).frame(width: 6, height: 6)
                Text(tr("Cancelado"))
            case .queued:
                Circle().strokeBorder(Theme.textTertiary, lineWidth: 1.2).frame(width: 7, height: 7)
                Text(tr("Na fila"))
            default:
                PulseBars(color: Theme.accentBright).scaleEffect(0.7)
                Text(progress.map { "\(status.label) · \(Int($0 * 100))%" } ?? status.label)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Theme.control.opacity(0.7), in: Capsule())
    }
}

/// Page title row used by every library screen.
struct PageTitle<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.audraTitle)
                    .tracking(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension PageTitle where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// Vertically centers the window's traffic lights in the custom top bar, and keeps them there
/// across resizes and full-screen transitions.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.apply() }

    final class ChromeView: NSView {
        private var observers: [NSObjectProtocol] = []
        private var applying = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                         NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification, NSWindow.didChangeScreenNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            let fullScreen: [(Notification.Name, Bool)] = [
                (NSWindow.willEnterFullScreenNotification, true), (NSWindow.willExitFullScreenNotification, false),
                (NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false),
            ]
            for (name, value) in fullScreen {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { WindowState.shared.isFullScreen = value }
                    }
                })
            }
            WindowState.shared.isFullScreen = window.styleMask.contains(.fullScreen)

            // AppKit re-lays out the title bar on its own (launch, focus changes); follow every move.
            if let close = window.standardWindowButton(.closeButton) {
                for view in [close, close.superview, close.superview?.superview].compactMap({ $0 }) {
                    view.postsFrameChangedNotifications = true
                    observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.apply() }
                    })
                }
            }
            apply()
            DispatchQueue.main.async { self.apply() }
        }

        override func layout() {
            super.layout()
            apply()
        }

        func apply() {
            guard !applying, let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let container = close.superview?.superview else { return }
            applying = true
            defer { applying = false }
            let height = Theme.topBarHeight
            let target = NSRect(x: container.frame.minX, y: window.frame.height - height,
                                width: container.frame.width, height: height)
            if container.frame != target { container.frame = target }
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (index, type) in buttons.enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                let origin = NSPoint(x: 20 + CGFloat(index) * 20, y: (height - button.frame.height) / 2)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
