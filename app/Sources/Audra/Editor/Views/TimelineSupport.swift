import AppKit
import SwiftUI

/// Converts between timeline seconds and lane pixels.
struct TimelineMetrics: Equatable {
    var pixelsPerSecond: Double
    var scrollX: Double

    func x(_ t: Double) -> CGFloat { CGFloat(t * pixelsPerSecond - scrollX) }
    func time(_ x: CGFloat) -> Double { max(0, (Double(x) + scrollX) / pixelsPerSecond) }
    func width(_ duration: Double) -> CGFloat { CGFloat(duration * pixelsPerSecond) }

    func visibleRange(width: CGFloat) -> ClosedRange<Double> {
        let start = scrollX / pixelsPerSecond
        return start...(start + Double(width) / pixelsPerSecond)
    }

    static let minPPS = 1.5
    static let maxPPS = 720.0
}

enum TrackLayout {
    static let headerWidth: CGFloat = 196
    static let rulerHeight: CGFloat = 28

    static func height(_ kind: TrackKind) -> CGFloat {
        switch kind {
        case .text: 36
        case .video: 64
        case .audio: 52
        }
    }
}

/// In-flight pointer interaction on the timeline (not committed until the gesture ends).
struct TimelineDrag: Equatable {
    enum Mode: Equatable { case move, trimStart, trimEnd }
    var mode: Mode
    var anchor: UUID
    var clipIDs: Set<UUID>
    var delta: Double = 0
    var targetTrack: UUID?
    var snapTime: Double?
    var isValid = true
}

/// Captures scroll-wheel and trackpad events over a region without stealing clicks.
struct ScrollEventCatcher: NSViewRepresentable {
    /// Returns true when the event was consumed.
    var onScroll: (NSEvent, CGPoint) -> Bool

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.stop() }

    final class CatcherView: NSView {
        var onScroll: ((NSEvent, CGPoint) -> Bool)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let local = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(local) else { return event }
                let point = CGPoint(x: local.x, y: self.isFlipped ? local.y : self.bounds.height - local.y)
                return self.onScroll?(event, point) == true ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Editor keyboard shortcuts that must not steal keys from text fields.
@MainActor
final class EditorKeyMonitor {
    private var monitor: Any?

    func start(_ handler: @escaping (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if let responder = event.window?.firstResponder, responder is NSText || responder is NSTextView {
                return event
            }
            if event.window?.attachedSheet != nil { return event }
            return handler(event) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Wrapping layout for transcript words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 3
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(width, maxX), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Thin draggable divider used to resize editor panels.
struct ResizeHandle: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    let onDrag: (CGFloat) -> Void
    var onEnd: () -> Void = {}
    @State private var hovering = false
    @State private var dragging = false
    @State private var last: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.hairline)
                .frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
            if hovering || dragging {
                Capsule().fill(Theme.accent.opacity(dragging ? 0.9 : 0.55))
                    .frame(width: axis == .horizontal ? 3 : 36, height: axis == .vertical ? 3 : 36)
                    .transition(.opacity)
            }
        }
        .frame(width: axis == .horizontal ? 7 : nil, height: axis == .vertical ? 7 : nil)
        .contentShape(Rectangle())
        .pointerStyle(axis == .horizontal ? .columnResize : .rowResize)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let current = axis == .horizontal ? value.translation.width : value.translation.height
                    if !dragging { dragging = true; last = 0 }
                    onDrag(current - last)
                    last = current
                }
                .onEnded { _ in dragging = false; last = 0; onEnd() }
        )
        .accessibilityHidden(true)
    }
}
