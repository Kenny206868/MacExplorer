import SwiftUI
import AppKit
import Combine
import ExplorerCore

struct CompanionSession: Codable, Sendable {
    let tabs: [BrowserSession]
    let activeIndex: Int
    let geometry: PaneGeometry
    let closedTabs: [BrowserSession]?
    @MainActor init(workspace: ExplorerWorkspace, geometry: PaneGeometry) {
        tabs = Array(workspace.tabs.prefix(100)).map { WindowSession.bounded($0.session()) }
        activeIndex = max(0, min(tabs.count - 1, workspace.tabs.firstIndex { $0.id == workspace.activeID } ?? 0))
        self.geometry = geometry; closedTabs = Array(workspace.closedTabs.suffix(30)).map(WindowSession.bounded)
    }
    func validated() throws -> CompanionSession {
        guard !tabs.isEmpty, tabs.count <= 100, tabs.indices.contains(activeIndex), geometry.ratio.isFinite,
              (0.2...0.8).contains(geometry.ratio), (closedTabs?.count ?? 0) <= 30,
              (tabs + (closedTabs ?? [])).allSatisfy({ !$0.history.locations.isEmpty && $0.history.locations.count <= 128 && $0.history.locations.indices.contains($0.history.index) && $0.query.utf8.count <= 32_768 && $0.selection.count <= 2048 }) else {
            throw ExplorerError.message("Invalid companion-pane session.")
        }
        return self
    }
}
struct PaneTransferRequest: Identifiable {
    let id = UUID()
    let job: FileJob
    let sourceIdentities: [(URL, FileFingerprint)]
    let destinationIdentity: FileFingerprint
    weak var owner: ExplorerWorkspace?
    @MainActor init(source: ExplorerWorkspace, destination: URL, move: Bool) throws {
        guard !source.selectedURLs.isEmpty else { throw ExplorerError.message("Select files in the source pane first.") }
        job = FileJob(move ? .move : .copy, sources: source.selectedURLs, destination: destination)
        sourceIdentities = try job.sources.map { ($0, try FileFingerprint($0)) }
        destinationIdentity = try FileFingerprint(destination); owner = source
    }
    func validate() throws {
        guard let destination = job.destination, destinationIdentity.matchesIdentity(destination),
              (try? FileEntry(url: destination).canBrowse) == true, sourceIdentities.allSatisfy({ $0.1.matches($0.0) }) else {
            throw ExplorerError.message("A source or destination changed after the transfer was requested. Select the items again.")
        }
    }
}
@MainActor final class DualPaneController: ObservableObject {
    weak var primary: ExplorerWorkspace?
    let secondary: ExplorerWorkspace
    @Published var geometry: PaneGeometry { didSet { primary?.objectWillChange.send(); primary?.saveSession() } }
    private var observation: AnyCancellable?
    var active: ExplorerWorkspace { geometry.focused == .secondary ? secondary : primary ?? secondary }
    init(primary: ExplorerWorkspace, session: CompanionSession? = nil) {
        self.primary = primary
        if let session {
            secondary = ExplorerWorkspace(windowSession: WindowSession(tabs: session.tabs, activeIndex: session.activeIndex, closedTabs: session.closedTabs ?? []))
            geometry = session.geometry
        } else {
            let location = primary.destination.map(Location.folder) ?? .folder(FileManager.default.homeDirectoryForCurrentUser)
            secondary = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(location), options: primary.current.options, query: "", allLocations: false, selection: []))
            geometry = PaneGeometry()
        }
        secondary.parentWorkspace = primary; secondary.window = primary.window
        observation = secondary.objectWillChange.sink { [weak primary] _ in primary?.objectWillChange.send() }
    }
    func focus(_ side: PaneSide, files: Bool = false) {
        if geometry.focused != side { active.addressFocused = false; active.searchFocused = false; geometry.focused = side }
        active.window = primary?.window; AppRouter.shared.active = active
        if files { active.focusFileSurface() }
    }
    func other(than workspace: ExplorerWorkspace) -> ExplorerWorkspace? { workspace === secondary ? primary : secondary }
    func refreshVisible() { primary?.current.refresh(); secondary.current.refresh() }
    func requestTransfer(from source: ExplorerWorkspace, move: Bool) {
        guard let destination = other(than: source)?.destination else {
            source.fail("Choose a destination", "Open a writable folder in the other pane first."); return
        }
        do {
            let request = try PaneTransferRequest(source: source, destination: destination, move: move)
            if move { primary?.pendingPaneTransfer = request }
            else { try request.validate(); source.operations.submit(request.job, owner: source) }
        } catch { source.fail("Transfer unavailable", error.localizedDescription) }
    }
    func copyLocation(from source: ExplorerWorkspace) { other(than: source)?.navigate(source.current.location) }
    func swapLocations() {
        guard let primary else { return }
        let left = primary.current.session(), right = secondary.current.session()
        primary.current.stop(); secondary.current.stop(); primary.current.restore(right); secondary.current.restore(left)
        refreshVisible(); primary.saveSession()
    }
    func snapshot() -> CompanionSession { CompanionSession(workspace: secondary, geometry: geometry) }
}
@MainActor extension ExplorerWorkspace {
    var windowRoot: ExplorerWorkspace { parentWorkspace ?? self }
    var paneController: DualPaneController? { windowRoot.dualPane }
    var routedWorkspace: ExplorerWorkspace { dualPane?.active ?? self }
    func toggleDualPane() {
        let root = windowRoot
        if let dual = root.dualPane {
            guard operations.runningCount == 0 else { root.routedWorkspace.fail("Transfers are running", "Finish or cancel active file operations before closing a pane."); return }
            root.retainedCompanion = dual.snapshot(); dual.secondary.answerCollision(.cancel)
            dual.secondary.tabs.forEach { $0.stop() }; root.dualPane = nil; AppRouter.shared.active = root
        } else {
            root.dualPane = DualPaneController(primary: root, session: root.retainedCompanion)
            root.dualPane?.secondary.current.refresh()
        }
        root.saveSession()
    }
    func activatePane(files: Bool = false) {
        if let controller = paneController { controller.focus(parentWorkspace == nil ? .primary : .secondary, files: files) }
        else { AppRouter.shared.active = self; if files { focusFileSurface() } }
    }
    func confirmPaneTransfer() {
        let root = windowRoot; guard let request = root.pendingPaneTransfer else { return }; root.pendingPaneTransfer = nil
        do { try request.validate(); if let owner = request.owner { owner.operations.submit(request.job, owner: owner) } }
        catch { root.routedWorkspace.fail("Transfer stopped", error.localizedDescription) }
    }
}
