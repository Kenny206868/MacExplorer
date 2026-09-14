import SwiftUI
import AppKit

extension Notification.Name { static let explorerDetachTab = Notification.Name("MacExplorer.detachTab") }

/// Tabs are live objects, not filesystem payloads. Random in-process tickets
/// never contain paths and can be consumed only once by this coordinator.
@MainActor final class TabTransferCoordinator {
    static let shared = TabTransferCoordinator()
    static let type = "com.wieslawsoltes.macexplorer.tab"
    private struct Ticket {
        let id: UUID
        weak var source: ExplorerWorkspace?
        let tabID: UUID
        let created: TimeInterval
    }
    struct Detachment {
        let session: BrowserSession
        let sourceWindowID: UUID
        weak var source: ExplorerWorkspace?
        let tabID: UUID
        let point: CGPoint?
    }
    private var ticket: Ticket?
    private var detachments: [UUID: Detachment] = [:]
    private var arrivals: [UUID: UUID] = [:]
    func begin(tab: BrowserTab, source: ExplorerWorkspace) -> Data? {
        guard source.tabs.contains(where: { $0 === tab }) else { return nil }
        let id = UUID(); ticket = Ticket(id: id, source: source, tabID: tab.id, created: ProcessInfo.processInfo.systemUptime)
        return Data(id.uuidString.utf8)
    }
    @discardableResult func accept(_ data: Data, into target: ExplorerWorkspace, before tab: UUID?) -> Bool {
        guard data.count <= 64, let value = String(data: data, encoding: .utf8), let ticket,
              value == ticket.id.uuidString, ProcessInfo.processInfo.systemUptime - ticket.created < 120,
              let source = ticket.source, source.tabs.contains(where: { $0.id == ticket.tabID }),
              source.window?.attachedSheet == nil, target.window?.attachedSheet == nil,
              source.conflict == nil, target.conflict == nil else { return false }
        self.ticket = nil
        target.receiveTab(from: source, id: ticket.tabID, before: tab); target.activatePane()
        return true
    }
    func drop(_ providers: [NSItemProvider], into target: ExplorerWorkspace, before tab: UUID?) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(Self.type) }), ticket != nil else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: Self.type) { data, _ in
            guard let data else { return }
            Task { @MainActor in _ = self.accept(data, into: target, before: tab) }
        }
        return true
    }
    func end(operation: NSDragOperation, released: Bool, outside: Bool, point: CGPoint) {
        // Only an unambiguous mouse release outside app windows requests a new
        // window. Escape, failed internal drops and unknown end causes cancel.
        guard operation.isEmpty else { return }
        defer { ticket = nil }
        guard released, outside, let ticket, let source = ticket.source,
              let tab = source.tabs.first(where: { $0.id == ticket.tabID }) else { return }
        _ = detach(tab, from: source, at: point)
    }
    @discardableResult func detach(_ tab: BrowserTab, from source: ExplorerWorkspace, at point: CGPoint? = nil) -> BrowserSession? {
        guard source.tabs.contains(where: { $0 === tab }), source.window?.attachedSheet == nil, source.conflict == nil else { return nil }
        let session = tab.session()
        let request = Detachment(session: session, sourceWindowID: source.windowRoot.id, source: source, tabID: tab.id, point: point)
        detachments[session.id] = request
        NotificationCenter.default.post(name: .explorerDetachTab, object: request)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            self.detachments.removeValue(forKey: session.id)
            self.arrivals = self.arrivals.filter { $0.value != session.id }
        }
        return session
    }
    func restored(_ session: UUID, as tab: BrowserTab) {
        if detachments[session] != nil { arrivals[tab.id] = session }
    }
    /// The source is removed only after the new native window has arrived.
    /// Failed window creation leaves the original tab and all its state intact.
    func completeArrival(in target: ExplorerWorkspace) {
        guard let placeholder = target.tabs.first(where: { arrivals[$0.id] != nil }),
              let id = arrivals.removeValue(forKey: placeholder.id), let request = detachments.removeValue(forKey: id),
              let source = request.source, source !== target,
              source.tabs.contains(where: { $0.id == request.tabID }) else { return }
        let closeEmptySource = source.tabs.count == 1 && source.paneController == nil && source.operations.runningCount == 0
        target.receiveTab(from: source, id: request.tabID, before: nil)
        placeholder.stop(); target.tabs.removeAll { $0.id == placeholder.id }; target.saveSession()
        if let point = request.point, let window = target.window {
            let size = source.window?.frame.size ?? CGSize(width: 1260, height: 800)
            window.restoreExplorerFrame(CGRect(x: point.x - 100, y: point.y - size.height + 24, width: size.width, height: size.height))
        }
        if closeEmptySource { source.window?.performClose(nil) }
    }
    func cancel() { ticket = nil }
}

struct TabDetachmentHost: ViewModifier {
    @ObservedObject var workspace: ExplorerWorkspace
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .explorerDetachTab)) { notification in
            guard let request = notification.object as? TabTransferCoordinator.Detachment,
                  request.sourceWindowID == workspace.id else { return }
            openWindow(id: "detached", value: request.session)
        }.onAppear {
            Task { @MainActor in await Task.yield(); TabTransferCoordinator.shared.completeArrival(in: workspace) }
        }
    }
}

struct TabDragAnchor: NSViewRepresentable {
    let tab: BrowserTab
    let workspace: ExplorerWorkspace
    func makeNSView(context: Context) -> TabDragAnchorView {
        let view = TabDragAnchorView(); view.tab = tab; view.workspace = workspace; TabDragRouter.shared.register(view); return view
    }
    func updateNSView(_ view: TabDragAnchorView, context: Context) { view.tab = tab; view.workspace = workspace }
    static func dismantleNSView(_ view: TabDragAnchorView, coordinator: ()) { TabDragRouter.shared.unregister(view) }
}
@MainActor final class TabDragAnchorView: NSView, NSDraggingSource {
    weak var tab: BrowserTab?
    weak var workspace: ExplorerWorkspace?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }
    func begin(_ event: NSEvent) -> Bool {
        guard let tab, let workspace, let data = TabTransferCoordinator.shared.begin(tab: tab, source: workspace) else { return false }
        let writer = NSPasteboardItem(); writer.setData(data, forType: NSPasteboard.PasteboardType(TabTransferCoordinator.type))
        let item = NSDraggingItem(pasteboardWriter: writer)
        let icon = NSImage(systemSymbolName: tab.location.symbol, accessibilityDescription: tab.location.title)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28), contents: icon)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true; return true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
        let released = NSApp.currentEvent?.type == .leftMouseUp && NSEvent.pressedMouseButtons & 1 == 0
        let outside = !NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.frame.contains(point) }
        TabTransferCoordinator.shared.end(operation: operation, released: released, outside: outside, point: point)
        TabDragRouter.shared.end()
    }
}
@MainActor final class TabDragRouter {
    static let shared = TabDragRouter()
    private let anchors = NSHashTable<TabDragAnchorView>.weakObjects()
    private var monitor: Any?
    private weak var candidate: TabDragAnchorView?
    private var down: NSEvent?
    private var active: TabDragAnchorView?
    func register(_ view: TabDragAnchorView) {
        anchors.add(view); guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]) { event in
            let handled = MainActor.assumeIsolated { self.handle(event) }; return handled ? nil : event
        }
    }
    func unregister(_ view: TabDragAnchorView) {
        anchors.remove(view); if candidate === view { candidate = nil; down = nil }; clean()
    }
    func end() { active = nil; candidate = nil; down = nil; clean() }
    private func clean() {
        if anchors.allObjects.isEmpty, active == nil, let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            candidate = nil; down = nil
            guard event.window?.attachedSheet == nil else { return false }
            candidate = anchors.allObjects.first { $0.window === event.window && !$0.isHiddenOrHasHiddenAncestor && $0.visibleRect.contains($0.convert(event.locationInWindow, from: nil)) }
            if candidate != nil { down = event }
        case .leftMouseDragged:
            guard active == nil, let candidate, let down, candidate.window === event.window,
                  hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y) > 7 else { return false }
            active = candidate; self.candidate = nil
            if candidate.begin(down) { return true }; end()
        case .leftMouseUp: candidate = nil; down = nil
        case .keyDown where event.keyCode == 53: TabTransferCoordinator.shared.cancel(); candidate = nil; down = nil
        default: break
        }
        return false
    }
}

struct TabDropTarget: ViewModifier {
    let workspace: ExplorerWorkspace
    let before: UUID?
    @State private var targeted = false
    func body(content: Content) -> some View {
        content.onDrop(of: [TabTransferCoordinator.type], isTargeted: $targeted) {
            TabTransferCoordinator.shared.drop($0, into: workspace, before: before)
        }.overlay(alignment: .leading) {
            if targeted { Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 5).allowsHitTesting(false) }
        }
    }
}
