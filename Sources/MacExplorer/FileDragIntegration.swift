import SwiftUI
import AppKit
import ExplorerCore

/// SwiftUI owns the visuals. This transparent adapter supplies AppKit's multi-item
/// dragging session, which a single SwiftUI onDrag item provider cannot express.
struct FileDragAnchor: NSViewRepresentable {
    let url: URL
    let workspace: ExplorerWorkspace
    let tab: BrowserTab
    func makeNSView(context: Context) -> FileDragAnchorView {
        let view = FileDragAnchorView(); updateNSView(view, context: context)
        FileDragRouter.shared.register(view); return view
    }
    func updateNSView(_ view: FileDragAnchorView, context: Context) {
        view.url = url; view.workspace = workspace; view.tab = tab
    }
    static func dismantleNSView(_ view: FileDragAnchorView, coordinator: ()) {
        FileDragRouter.shared.unregister(view)
    }
}

@MainActor final class FileDragAnchorView: NSView, NSDraggingSource {
    var url: URL?
    weak var workspace: ExplorerWorkspace?
    weak var tab: BrowserTab?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }
    func begin(_ event: NSEvent) -> Bool {
        guard let url, let tab, let workspace, workspace.current.id == tab.id else { return false }
        if !tab.selection.contains(url) { workspace.select(url, extend: false, range: false) }
        let urls = tab.displayEntries.lazy.filter { tab.selection.contains($0.url) }.map(\.url)
        guard !urls.isEmpty else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let fallbackIcon = NSWorkspace.shared.icon(forFile: url.path)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 5)) * 3
            item.setDraggingFrame(CGRect(x: point.x + offset, y: point.y + offset, width: 36, height: 36),
                                  contents: index < 8 ? NSWorkspace.shared.icon(forFile: url.path) : fallbackIcon)
            return item
        }
        let session = beginDraggingSession(with: Array(items), event: event, source: self)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
        return true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .link]
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // A URL drop destination performs the transaction. Never remove a source
        // based only on a reported drag operation: that risks a double deletion.
        FileDragRouter.shared.endSession(); tab?.refresh()
    }
}

@MainActor final class FileDragRouter {
    static let shared = FileDragRouter()
    private let anchors = NSHashTable<FileDragAnchorView>.weakObjects()
    private var monitor: Any?
    private weak var candidate: FileDragAnchorView?
    private var candidateURL: URL?
    private var origin = NSPoint.zero
    private var activeSource: FileDragAnchorView?
    func register(_ view: FileDragAnchorView) {
        anchors.add(view)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            MainActor.assumeIsolated { self.handle(event) }
        }
    }
    func unregister(_ view: FileDragAnchorView) {
        anchors.remove(view)
        if candidate === view { candidate = nil }
        if anchors.allObjects.isEmpty, activeSource == nil { removeMonitor() }
    }
    func endSession() {
        activeSource = nil; candidate = nil
        if anchors.allObjects.isEmpty { removeMonitor() }
    }
    private func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            candidate = nil
            guard event.window?.attachedSheet == nil,
                  !(event.window?.firstResponder is NSTextView) else { return event }
            origin = event.locationInWindow
            candidate = anchors.allObjects.first { view in
                guard view.window === event.window, !view.isHiddenOrHasHiddenAncestor else { return false }
                return view.visibleRect.contains(view.convert(origin, from: nil))
            }
            candidateURL = candidate?.url
        case .leftMouseDragged:
            guard activeSource == nil, let candidate, candidate.window === event.window,
                  candidate.url == candidateURL, hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) >= 5 else { return event }
            activeSource = candidate; self.candidate = nil
            if candidate.begin(event) { return nil }
            activeSource = nil
        case .leftMouseUp: candidate = nil
        default: break
        }
        return event
    }
}

@MainActor final class SpringFolderTarget: ObservableObject {
    @Published var highlighted = false
    private var task: Task<Void, Never>?
    func enter(_ folder: URL, workspace: ExplorerWorkspace) {
        task?.cancel(); highlighted = true
        let tab = workspace.current, original = tab.location
        task = Task { [weak workspace, weak tab] in
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            guard !Task.isCancelled, let workspace, let tab, tab.location == original,
                  workspace.current.id == tab.id, FileNames.exists(folder) else { return }
            workspace.navigate(.folder(folder))
        }
    }
    func cancel() { task?.cancel(); task = nil; highlighted = false }
    deinit { task?.cancel() }
}

struct SpringFolderDrop: DropDelegate {
    let folder: URL?
    let workspace: ExplorerWorkspace
    let target: SpringFolderTarget
    func validateDrop(info: DropInfo) -> Bool { folder != nil && info.hasItemsConforming(to: ["public.file-url"]) }
    func dropEntered(info: DropInfo) { if let folder { target.enter(folder, workspace: workspace) } }
    func dropExited(info: DropInfo) { target.cancel() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: NSEvent.modifierFlags.contains(.shift) ? .move : .copy) }
    func performDrop(info: DropInfo) -> Bool {
        target.cancel(); guard let folder else { return false }
        return workspace.drop(info.itemProviders(for: ["public.file-url"]), to: folder, move: NSEvent.modifierFlags.contains(.shift))
    }
}

struct FileInteractionModifier: ViewModifier {
    let entry: FileEntry
    let workspace: ExplorerWorkspace
    let tab: BrowserTab
    @StateObject private var target = SpringFolderTarget()
    @ObservedObject private var clipboard = FileClipboard.shared
    func body(content: Content) -> some View {
        content.opacity(clipboard.isCut(entry.url) ? 0.5 : 1)
            .background(FileDragAnchor(url: entry.url, workspace: workspace, tab: tab))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(target.highlighted ? Color.accentColor : .clear, lineWidth: 2).allowsHitTesting(false))
            .onDrop(of: ["public.file-url"], delegate: SpringFolderDrop(folder: entry.canBrowse ? entry.url : nil, workspace: workspace, target: target))
            .onDisappear { target.cancel() }
    }
}
