import SwiftUI
import AppKit
import ExplorerCore

struct MarqueeScrollBridge: NSViewRepresentable {
    let controller: MarqueeAutoScroller
    let active: Bool
    let changed: (CGPoint) -> Void
    func makeNSView(context: Context) -> MarqueeScrollAnchor {
        let view = MarqueeScrollAnchor(); controller.attach(view)
        controller.configure(active: active, changed: changed); return view
    }
    func updateNSView(_ view: MarqueeScrollAnchor, context: Context) {
        controller.attach(view); controller.configure(active: active, changed: changed)
    }
    static func dismantleNSView(_ view: MarqueeScrollAnchor, coordinator: ()) { view.controller?.stop() }
}
@MainActor final class MarqueeScrollAnchor: NSView {
    weak var controller: MarqueeAutoScroller?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
@MainActor final class MarqueeAutoScroller: ObservableObject {
    private weak var anchor: MarqueeScrollAnchor?
    private var timer: Timer?
    private var lastTime = 0.0
    private var changed: ((CGPoint) -> Void)?
    func attach(_ view: MarqueeScrollAnchor) { anchor = view; view.controller = self }
    func configure(active: Bool, changed: @escaping (CGPoint) -> Void) {
        guard active else { stop(); return }
        self.changed = changed
        guard timer == nil else { return }
        lastTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil; changed = nil }
    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0, let window = anchor?.window else { stop(); return }
        let now = ProcessInfo.processInfo.systemUptime
        _ = step(pointerInWindow: window.convertPoint(fromScreen: NSEvent.mouseLocation), elapsed: now - lastTime)
        lastTime = now
    }
    /// Injectable pointer/time input tests the real NSScrollView path without
    /// synthesizing global events or changing the user's mouse position.
    @discardableResult func step(pointerInWindow: CGPoint, elapsed: TimeInterval) -> CGPoint? {
        guard let anchor, let scroll = anchor.enclosingScrollView, let document = scroll.documentView else { return nil }
        let clip = scroll.contentView
        let visible = anchor.convert(clip.bounds, from: clip)
        let point = anchor.convert(pointerInWindow, from: nil)
        let relative = CGPoint(x: point.x - visible.minX, y: point.y - visible.minY)
        var delta = EdgeAutoScroll.delta(pointer: relative, viewport: visible.size, elapsed: elapsed)
        if document.bounds.width <= clip.bounds.width { delta.x = 0 }
        if document.bounds.height <= clip.bounds.height { delta.y = 0 }
        guard delta != .zero else { return nil }
        // Convert the desired top-left through the document, preserving nested
        // hosting transforms and AppKit's flipped coordinate conventions.
        let desired = document.convert(CGPoint(x: visible.minX + delta.x, y: visible.minY + delta.y), from: anchor)
        let target = EdgeAutoScroll.clampedOrigin(desired, content: document.bounds.size, viewport: clip.bounds.size)
        guard target != clip.bounds.origin else { return nil }
        clip.scroll(to: target); scroll.reflectScrolledClipView(clip)
        let updated = anchor.convert(pointerInWindow, from: nil)
        changed?(updated)
        return updated
    }
    deinit { timer?.invalidate() }
}
