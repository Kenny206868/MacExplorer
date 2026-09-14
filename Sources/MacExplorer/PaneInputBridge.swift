import SwiftUI
import AppKit
import ExplorerCore

struct PaneInputBridge: NSViewRepresentable {
    let workspace: ExplorerWorkspace
    func makeNSView(context: Context) -> PaneInputRegion {
        let view = PaneInputRegion(); view.workspace = workspace; PaneInputRouter.shared.register(view); return view
    }
    func updateNSView(_ view: PaneInputRegion, context: Context) { view.workspace = workspace }
    static func dismantleNSView(_ view: PaneInputRegion, coordinator: ()) { PaneInputRouter.shared.unregister(view) }
}
@MainActor final class PaneInputRegion: NSView {
    weak var workspace: ExplorerWorkspace?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); workspace?.fileViewportHeight = max(1, bounds.height) }
}
@MainActor final class PaneInputRouter {
    static let shared = PaneInputRouter()
    private let regions = NSHashTable<PaneInputRegion>.weakObjects()
    private var monitor: Any?
    private var pinch = PinchAccumulator()
    private weak var gestureOwner: ExplorerWorkspace?
    private var pressureTriggered = false
    func register(_ view: PaneInputRegion) {
        regions.add(view); guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .swipe, .magnify, .smartMagnify, .pressure]) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.handle(event) == nil }; return consumed ? nil : event
        }
    }
    func unregister(_ view: PaneInputRegion) {
        regions.remove(view)
        if regions.allObjects.isEmpty, let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil; pinch.reset(); gestureOwner = nil }
    }
    func workspace(at point: NSPoint, in window: NSWindow?) -> ExplorerWorkspace? {
        guard let window else { return nil }
        return regions.allObjects.first { view in
            view.window === window && !view.isHiddenOrHasHiddenAncestor && view.visibleRect.contains(view.convert(point, from: nil))
        }?.workspace
    }
    func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window?.attachedSheet == nil else { return event }
        guard let workspace = workspace(at: event.locationInWindow, in: event.window) else {
            if event.type == .leftMouseDown { AppRouter.shared.active?.fileSurfaceFocused = false }; return event
        }
        guard workspace.sheet == nil, workspace.conflict == nil, workspace.message == nil, workspace.windowRoot.pendingPaneTransfer == nil else { return event }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            let wasEditingLocation = workspace.addressFocused || workspace.searchFocused
            workspace.activatePane(); workspace.fileSurfaceFocused = true
            if event.type == .leftMouseDown && wasEditingLocation { workspace.focusFileSurface() }
            if event.type == .otherMouseDown && (event.buttonNumber == 3 || event.buttonNumber == 4) {
                if event.buttonNumber == 3 { workspace.current.back() } else { workspace.current.forward() }; return nil
            }
            return event
        }
        guard InputPreferences.shared.gesturesEnabled else { pinch.reset(); pressureTriggered = false; return event }
        if gestureOwner !== workspace { pinch.reset(); pressureTriggered = false; gestureOwner = workspace }
        workspace.activatePane()
        switch event.type {
        case .swipe:
            if abs(event.deltaX) > abs(event.deltaY), event.deltaX != 0 {
                if event.deltaX > 0 { workspace.current.back() } else { workspace.current.forward() }; return nil
            }
        case .magnify where workspace.current.options.view != .gallery:
            let direction = pinch.consume(Double(event.magnification), owner: workspace.id,
                began: event.phase.contains(.began), ended: event.phase.contains(.ended), cancelled: event.phase.contains(.cancelled))
            if direction != 0 { workspace.zoomFileView(direction) }; return nil
        case .smartMagnify: workspace.quickLook(); return nil
        case .pressure:
            if event.stage >= 2, !pressureTriggered { pressureTriggered = true; workspace.quickLook() }
            if event.stage < 2 || event.phase.contains(.ended) { pressureTriggered = false }
        default: break
        }
        return event
    }
}
