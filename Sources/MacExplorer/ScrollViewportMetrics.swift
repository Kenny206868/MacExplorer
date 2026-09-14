import SwiftUI
import AppKit

/// Measures the viewport consumed by native non-overlay scrollbars. No scroller
/// preferences are changed. SwiftUI receives a coalesced width-gutter value only
/// after the native layout pass, avoiding mutation while it is laying out rows.
struct ScrollViewportMetrics: NSViewRepresentable {
    let changed: (CGFloat) -> Void
    func makeNSView(context: Context) -> ScrollViewportMetricView {
        let view = ScrollViewportMetricView(); view.changed = changed; return view
    }
    func updateNSView(_ view: ScrollViewportMetricView, context: Context) { view.changed = changed; view.observeViewport() }
    static func dismantleNSView(_ view: ScrollViewportMetricView, coordinator: ()) { view.invalidate() }
}
@MainActor final class ScrollViewportMetricView: NSView {
    var changed: ((CGFloat) -> Void)?
    private weak var observed: NSScrollView?
    private var tokens: [NSObjectProtocol] = []
    private var queued = false
    private var last: CGFloat = -1
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); observeViewport() }
    override func layout() { super.layout(); observeViewport(); schedule() }
    func observeViewport() {
        guard let scroll = enclosingScrollView else { return }
        if observed !== scroll {
            invalidate(); observed = scroll
            scroll.contentView.postsFrameChangedNotifications = true
            tokens.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
            tokens.append(NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        schedule()
    }
    static func gutter(in scroll: NSScrollView) -> CGFloat {
        let width = scroll.bounds.width - scroll.contentSize.width
        return width.isFinite ? min(80, max(0, width)) : 0
    }
    private func schedule() {
        guard !queued else { return }; queued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.queued = false
            guard let scroll = self.observed else { return }
            let value = Self.gutter(in: scroll)
            guard abs(value - self.last) > 0.25 else { return }
            self.last = value; self.changed?(value)
        }
    }
    func invalidate() {
        tokens.forEach(NotificationCenter.default.removeObserver); tokens = []; observed = nil; last = -1
    }
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}
