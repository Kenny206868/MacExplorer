import SwiftUI
import AppKit
import ExplorerCore

struct FileDragAnchor: NSViewRepresentable {
    let url: URL
    let workspace: ExplorerWorkspace
    let tab: BrowserTab
    func makeNSView(context: Context) -> FileDragAnchorView {
        let view = FileDragAnchorView(); updateNSView(view, context: context); FileDragRouter.shared.register(view); return view
    }
    func updateNSView(_ view: FileDragAnchorView, context: Context) { view.url = url; view.workspace = workspace; view.tab = tab }
    static func dismantleNSView(_ view: FileDragAnchorView, coordinator: ()) { FileDragRouter.shared.unregister(view) }
}
@MainActor final class FileDragAnchorView: NSView, NSDraggingSource {
    var url: URL?
    weak var workspace: ExplorerWorkspace?
    weak var tab: BrowserTab?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }
    var isEditingFilename: Bool {
        guard let tab, let url else { return false }
        return FilenameEditorRegistry.shared.editor(for: tab).session?.source == url
    }
    func prepareEntries() -> [FileEntry] {
        guard let url, let tab, let workspace, workspace.current.id == tab.id, !isEditingFilename,
              tab.navigation.order.contains(url) else { return [] }
        workspace.activatePane(files: true)
        if !tab.selection.contains(url) { workspace.select(url, extend: false, range: false) }
        return tab.selectedEntries
    }
    func begin(_ event: NSEvent) -> Bool {
        guard let url, let tab, let workspace, workspace.current.id == tab.id else { return false }
        let entries = prepareEntries(); guard !entries.isEmpty else { return false }
        let point = convert(event.locationInWindow, from: nil), fallbackIcon = NSWorkspace.shared.icon(forFile: url.path)
        let providers: [ExplorerFilePromiseProvider]
        do { providers = try entries.map { try ExplorerFilePromiseProvider.make(for: $0) } }
        catch { workspace.fail("Drag unavailable", error.localizedDescription); return false }
        let items = providers.enumerated().map { index, provider -> NSDraggingItem in
            let url = entries[index].url, item = NSDraggingItem(pasteboardWriter: provider), offset = CGFloat(min(index, 5)) * 3
            item.setDraggingFrame(CGRect(x: point.x + offset, y: point.y + offset, width: 36, height: 36), contents: index < 8 ? NSWorkspace.shared.icon(forFile: url.path) : fallbackIcon)
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .pile; session.animatesToStartingPositionsOnCancelOrFail = true; return true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? [.copy, .move, .link] : .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // The receiver commits changes. A Move mask never authorizes the source
        // to delete its files a second time.
        FileDragRouter.shared.endSession(); tab?.refresh()
    }
}
@MainActor final class FileDragRouter {
    static let shared = FileDragRouter()
    private let anchors = NSHashTable<FileDragAnchorView>.weakObjects()
    private var monitor: Any?
    private weak var candidate: FileDragAnchorView?
    private var candidateURL: URL?
    private var downEvent: NSEvent?
    private var activeSource: FileDragAnchorView?
    private var preserveSelectionUntilUp = false
    private let exclusions = NSHashTable<FilePointerExclusionView>.weakObjects()
    var liveAnchorCount: Int { anchors.allObjects.count }
    func exclude(_ view: FilePointerExclusionView) { exclusions.add(view) }
    func removeExclusion(_ view: FilePointerExclusionView) { exclusions.remove(view) }
    func register(_ view: FileDragAnchorView) {
        anchors.add(view); guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            let consumed = MainActor.assumeIsolated { self.handle(event) == nil }; return consumed ? nil : event
        }
    }
    func unregister(_ view: FileDragAnchorView) {
        anchors.remove(view); if candidate === view { candidate = nil; downEvent = nil }
        if anchors.allObjects.isEmpty, activeSource == nil { removeMonitor() }
    }
    func folder(at point: NSPoint, in window: NSWindow?, workspace: ExplorerWorkspace) -> URL? {
        guard let window else { return nil }
        return anchors.allObjects.first { view in
            view.window === window && view.workspace === workspace && !view.isHiddenOrHasHiddenAncestor
                && view.visibleRect.contains(view.convert(point, from: nil))
                && view.url.flatMap { workspace.current.navigation.order.index(of: $0) }.map { workspace.current.navigation.entries[$0].canBrowse } == true
        }?.url
    }
    func endSession() { activeSource = nil; candidate = nil; downEvent = nil; if anchors.allObjects.isEmpty { removeMonitor() } }
    private func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    /// Select before ordinary dispatch, without a double-click recognition
    /// delay. Editors and checkboxes own their input. Multi-drag keeps sources.
    func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            candidate = nil; downEvent = nil; preserveSelectionUntilUp = false
            guard event.window?.attachedSheet == nil,
                  !exclusions.allObjects.contains(where: { $0.window === event.window && !$0.isHiddenOrHasHiddenAncestor && $0.visibleRect.contains($0.convert(event.locationInWindow, from: nil)) }) else { return event }
            candidate = anchors.allObjects.first { view in
                view.window === event.window && !view.isHiddenOrHasHiddenAncestor && !view.isEditingFilename
                    && view.visibleRect.contains(view.convert(event.locationInWindow, from: nil))
            }
            candidateURL = candidate?.url
            if let candidate, let url = candidate.url, let workspace = candidate.workspace,
               WorkspaceCommandScope.target(workspace) != nil, candidate.tab === workspace.current,
               workspace.current.navigation.order.contains(url) {
                downEvent = event
                let modified = !event.modifierFlags.intersection([.command, .control, .shift]).isEmpty || workspace.touchSelecting
                preserveSelectionUntilUp = !modified && workspace.current.selection.contains(url)
                if preserveSelectionUntilUp {
                    workspace.activatePane(files: true)
                    if workspace.current.focusedURL != url { workspace.current.focusedURL = url }
                } else { workspace.tapFile(url, modifiers: event.modifierFlags) }
            } else { self.candidate = nil }
        case .leftMouseDragged:
            guard activeSource == nil, let candidate, let downEvent, candidate.window === event.window,
                  !candidate.isEditingFilename, candidate.url == candidateURL,
                  hypot(event.locationInWindow.x - downEvent.locationInWindow.x, event.locationInWindow.y - downEvent.locationInWindow.y) >= 5 else { return event }
            activeSource = candidate; self.candidate = nil
            if candidate.begin(downEvent) { return nil }; activeSource = nil; self.downEvent = nil
        case .leftMouseUp:
            if let candidate, let downEvent, let workspace = candidate.workspace, let url = candidate.url,
               candidate.url == candidateURL, candidate.window === event.window, !candidate.isEditingFilename,
               candidate.visibleRect.contains(candidate.convert(event.locationInWindow, from: nil)),
               WorkspaceCommandScope.target(workspace) != nil,
               hypot(event.locationInWindow.x - downEvent.locationInWindow.x, event.locationInWindow.y - downEvent.locationInWindow.y) < 5 {
                if preserveSelectionUntilUp { workspace.select(url, extend: false, range: false) }
                if workspace.preferences.value.singleClickOpen && !workspace.touchSelecting && event.clickCount == 1,
                   downEvent.modifierFlags.intersection([.command, .control, .shift]).isEmpty,
                   event.timestamp - downEvent.timestamp < 0.65,
                   let index = workspace.current.navigation.order.index(of: url) { workspace.open(workspace.current.navigation.entries[index]) }
            }
            candidate = nil; downEvent = nil; preserveSelectionUntilUp = false
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
        content.modifier(FileActivation(entry: entry, workspace: workspace))
            .opacity(clipboard.isCut(entry.url) ? 0.5 : 1)
            .background(FileDragAnchor(url: entry.url, workspace: workspace, tab: tab))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(target.highlighted ? Color.accentColor : .clear, lineWidth: 2).allowsHitTesting(false))
            .onDrop(of: ["public.file-url"], delegate: SpringFolderDrop(folder: entry.canBrowse ? entry.url : nil, workspace: workspace, target: target))
            .onDisappear { target.cancel() }
    }
}
