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
/// Sendable, immutable I/O result. Construction and revalidation are read work;
/// neither belongs in a toolbar callback or on the main actor.
struct PaneTransferSnapshot: Sendable {
    let job: FileJob
    let sourceIdentities: [(URL, FileFingerprint)]
    let destinationIdentity: FileFingerprint
    init(sources: [URL], destination: URL, move: Bool, cancellation: FileReadCancellation) throws {
        guard !sources.isEmpty else { throw ExplorerError.message("Select files in the source pane first.") }
        try cancellation.check()
        job = FileJob(move ? .move : .copy, sources: sources, destination: destination)
        sourceIdentities = try job.sources.map { url in try cancellation.check(); return (url, try FileFingerprint(url)) }
        try cancellation.check(); destinationIdentity = try FileFingerprint(destination)
    }
    func validate(_ cancellation: FileReadCancellation = FileReadCancellation()) throws {
        try cancellation.check()
        guard let destination = job.destination, destinationIdentity.matchesIdentity(destination),
              (try? FileEntry(url: destination).canBrowse) == true else { throw changed() }
        for (url, identity) in sourceIdentities { try cancellation.check(); guard identity.matches(url) else { throw changed() } }
    }
    private func changed() -> ExplorerError {
        .message("A source or destination changed after the transfer was requested. Select the items again.")
    }
}
struct PaneTransferRequest: Identifiable {
    let snapshot: PaneTransferSnapshot
    var id: UUID { snapshot.job.id }
    var job: FileJob { snapshot.job }
    weak var owner: ExplorerWorkspace?
    @MainActor static func prepare(source: ExplorerWorkspace, destination: URL, move: Bool) async throws -> Self {
        let sources = source.selectedURLs
        let snapshot = try await FileReadExecutor.metadata.run {
            try PaneTransferSnapshot(sources: sources, destination: destination, move: move, cancellation: $0)
        }
        return Self(snapshot: snapshot, owner: source)
    }
}
@MainActor final class DualPaneController: ObservableObject {
    weak var primary: ExplorerWorkspace?
    let secondary: ExplorerWorkspace
    @Published var geometry: PaneGeometry { didSet { primary?.objectWillChange.send(); primary?.saveSession() } }
    @Published private(set) var preparingTransfer = false
    @Published private(set) var transferNotice: String?
    private let transferReads: FileReadExecutor
    private var transferTask: Task<Void, Never>?
    private var transferID: UUID?
    private var observation: AnyCancellable?
    var active: ExplorerWorkspace { geometry.focused == .secondary ? secondary : primary ?? secondary }
    init(primary: ExplorerWorkspace, session: CompanionSession? = nil, transferReads: FileReadExecutor = .metadata) {
        self.primary = primary; self.transferReads = transferReads
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
        guard !preparingTransfer, source === active, WorkspaceCommandScope.target(source) === source else { return }
        guard let target = other(than: source), let destination = target.destination else {
            source.fail("Choose a destination", "Open a writable folder in the other pane first."); return
        }
        let sources = source.selectedURLs, selection = source.current.selection
        guard !sources.isEmpty, !source.current.location.isArchive else { return }
        let sourceID = source.activeID, targetID = target.activeID
        let sourceLocation = source.current.location, targetLocation = target.current.location
        let revision = source.current.dataRevision, token = UUID(), executor = transferReads
        transferID = token; transferNotice = nil; preparingTransfer = true
        transferTask = Task { [weak self, weak source, weak target] in
            defer { self?.finishPreparation(token) }
            do {
                let snapshot = try await executor.run { cancellation in
                    let value = try PaneTransferSnapshot(sources: sources, destination: destination, move: move, cancellation: cancellation)
                    try value.validate(cancellation); return value
                }
                guard let self, self.transferID == token, !Task.isCancelled, let source, let target,
                      source.windowRoot.dualPane === self else { return }
                guard source.activeID == sourceID, source.current.location == sourceLocation,
                      source.current.selection == selection, source.current.dataRevision == revision,
                      target.activeID == targetID, target.current.location == targetLocation,
                      WorkspaceCommandScope.target(source) === source else {
                    self.transferNotice = "Transfer not started: the selection, pane or dialog changed."; return
                }
                let request = PaneTransferRequest(snapshot: snapshot, owner: source)
                if move { self.primary?.pendingPaneTransfer = request }
                else { source.operations.submit(request.job, owner: source) }
            } catch is CancellationError { }
            catch { if let self, self.transferID == token { source?.fail("Transfer unavailable", error.localizedDescription) } }
        }
    }
    func confirm(_ request: PaneTransferRequest) {
        guard !preparingTransfer, let owner = request.owner, owner.windowRoot.dualPane === self else { return }
        let token = UUID(), snapshot = request.snapshot, executor = transferReads
        transferID = token; transferNotice = nil; preparingTransfer = true
        transferTask = Task { [weak self, weak owner] in
            defer { self?.finishPreparation(token) }
            do {
                try await executor.run { try snapshot.validate($0) }
                guard let self, self.transferID == token, !Task.isCancelled, let owner,
                      owner.windowRoot.dualPane === self else { return }
                guard WorkspaceCommandScope.target(owner) != nil else {
                    self.transferNotice = "Move not started: another dialog is open."; return
                }
                owner.operations.submit(snapshot.job, owner: owner)
            } catch is CancellationError { }
            catch { if let self, self.transferID == token { owner?.fail("Transfer stopped", error.localizedDescription) } }
        }
    }
    func cancelTransferPreparation() {
        guard preparingTransfer else { return }
        transferID = nil; transferTask?.cancel(); transferTask = nil; preparingTransfer = false
        transferNotice = "Transfer preparation cancelled. No files were changed."
    }
    private func finishPreparation(_ token: UUID) {
        guard transferID == token else { return }
        transferID = nil; transferTask = nil; preparingTransfer = false
    }
    deinit { transferTask?.cancel() }
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
            dual.cancelTransferPreparation(); root.pendingPaneTransfer = nil
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
        let root = windowRoot
        guard let request = root.pendingPaneTransfer, let controller = root.dualPane, let source = request.owner else {
            root.pendingPaneTransfer = nil; return
        }
        // Accept the user's decision, but do not race the confirmation's
        // AppKit dismissal. The existing handoff observes real window focus
        // and sheet removal, rejects a replacement modal, and runs only once.
        DeferredSheetAction.shared.enqueue(for: source, validate: { [weak source, weak controller] in
            guard let source, let controller, source.windowRoot.dualPane === controller else {
                throw ExplorerError.message("The source pane closed before the move could start.")
            }
        }) { [weak controller] _ in controller?.confirm(request) }
        root.pendingPaneTransfer = nil
        DeferredSheetAction.shared.didDismiss(source)
    }
}
