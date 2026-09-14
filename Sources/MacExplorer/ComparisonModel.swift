import SwiftUI
import AppKit
import ExplorerCore

/// Captures actual pane identities; result actions cannot follow later tab,
/// location, search, hidden-item or companion changes.
@MainActor struct ComparisonContext {
    weak var owner: ExplorerWorkspace?
    weak var controller: DualPaneController?
    weak var left: ExplorerWorkspace?
    weak var right: ExplorerWorkspace?
    let leftTab: UUID, rightTab: UUID
    let leftURL: URL, rightURL: URL
    let hidden: Bool
    static func unavailable(_ owner: ExplorerWorkspace) -> String? {
        guard let controller = owner.paneController, let first = controller.primary,
              first.destination != nil, controller.secondary.destination != nil else {
            return "Open a filesystem folder in each pane."
        }
        guard first.current.query.isEmpty, controller.secondary.current.query.isEmpty else {
            return "Clear searches in both panes before comparing their folders."
        }
        return nil
    }
    init(_ owner: ExplorerWorkspace) throws {
        if let reason = Self.unavailable(owner) { throw ExplorerError.message(reason) }
        guard let controller = owner.paneController, let left = controller.primary,
              let leftURL = left.destination, let rightURL = controller.secondary.destination else {
            throw ExplorerError.message("The comparison panes are unavailable.")
        }
        self.owner = owner; self.controller = controller; self.left = left; right = controller.secondary
        leftTab = left.current.id; rightTab = controller.secondary.current.id
        self.leftURL = leftURL; self.rightURL = rightURL; hidden = owner.preferences.value.showHidden
    }
    func validate() throws {
        guard let owner, let left, let right, let controller, owner.paneController === controller,
              controller.primary === left, controller.secondary === right,
              left.current.id == leftTab, right.current.id == rightTab,
              left.destination == leftURL, right.destination == rightURL,
              left.current.query.isEmpty, right.current.query.isEmpty,
              owner.preferences.value.showHidden == hidden else {
            throw ExplorerError.message("A pane, folder, search or visibility setting changed. Open a new comparison.")
        }
    }
    func request(mode: ComparisonMode, names: ComparisonNamePolicy) -> ComparisonRequest {
        var request = ComparisonRequest(left: leftURL, right: rightURL)
        request.mode = mode; request.namePolicy = names; request.includeHidden = hidden
        return request
    }
}

enum ComparisonFilter: String, CaseIterable, Identifiable {
    case all = "All", differences = "Differences", leftOnly = "First only", rightOnly = "Second only", unverified = "Unverified"
    var id: String { rawValue }
    func includes(_ row: ComparisonRow) -> Bool {
        switch self {
        case .all: return true
        case .differences: return row.status.isDifference
        case .leftOnly: return row.status == .leftOnly
        case .rightOnly: return row.status == .rightOnly
        case .unverified: return row.status.isUnverified
        }
    }
}

@MainActor final class ComparisonModel: ObservableObject {
    let context: ComparisonContext?
    @Published var mode = ComparisonMode.metadata { didSet { if mode != oldValue { invalidate() } } }
    @Published var names = ComparisonNamePolicy.exact { didSet { if names != oldValue { invalidate() } } }
    @Published var filter = ComparisonFilter.all { didSet { updateVisible() } }
    @Published var query = "" { didSet { updateVisible() } }
    @Published var marked: Set<String> = []
    @Published private(set) var report: ComparisonReport?
    @Published private(set) var visible: [ComparisonRow] = []
    @Published private(set) var counts: [ComparisonFilter: Int] = [:]
    @Published private(set) var running = false
    @Published private(set) var cancelling = false
    @Published private(set) var progress: ComparisonProgress?
    @Published private(set) var error: String?
    private var worker: Task<ComparisonReport, Error>?
    private var generation = UUID()
    init(workspace: ExplorerWorkspace) {
        do { context = try ComparisonContext(workspace) }
        catch { context = nil; self.error = error.localizedDescription }
    }
    func compare() async {
        guard let context, !running else { return }
        do { try context.validate() } catch { self.error = error.localizedDescription; return }
        invalidate(); running = true; cancelling = false; error = nil
        let token = UUID(); generation = token
        let request = context.request(mode: mode, names: names)
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            var last = -Double.infinity
            return try DirectoryComparison.compare(request, progress: { value in
                let now = ProcessInfo.processInfo.systemUptime
                guard now - last >= 0.1 || value.completed == value.total else { return }
                last = now
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.running else { return }
                    self.progress = value
                }
            })
        }
        self.worker = worker
        defer { if generation == token { running = false; cancelling = false; self.worker = nil } }
        do {
            let result = try await worker.value
            guard generation == token, !cancelling else { return }
            try context.validate()
            report = result
            counts = Dictionary(uniqueKeysWithValues: ComparisonFilter.allCases.map { filter in (filter, result.rows.filter(filter.includes).count) })
            updateVisible()
        } catch is CancellationError { if generation == token { error = "Comparison cancelled. No files were changed." } }
        catch { if generation == token { self.error = error.localizedDescription } }
    }
    func cancel() { cancelling = true; worker?.cancel() }
    func invalidate() {
        worker?.cancel(); generation = UUID(); worker = nil; running = false; cancelling = false
        report = nil; visible = []; counts = [:]; marked = []; progress = nil
    }
    func markDifferences() { marked = Set(visible.filter { $0.status.isDifference && Self.canMark($0) }.map(\.id)) }
    func toggle(_ row: ComparisonRow) {
        guard Self.canMark(row) else { return }
        if marked.contains(row.id) { marked.remove(row.id) } else { marked.insert(row.id) }
    }
    static func canMark(_ row: ComparisonRow) -> Bool { row.status != .unavailable && row.status != .ambiguous }
    func markedFiles(_ side: PaneSide) -> Int {
        (report?.rows ?? []).filter { marked.contains($0.id) }.reduce(0) { $0 + (side == .primary ? $1.left.count : $1.right.count) }
    }
    func selectInPane(_ side: PaneSide) {
        guard let context, let owner = context.owner, let report else { return }
        let rows = report.rows.filter { marked.contains($0.id) && Self.canMark($0) }
        guard !rows.isEmpty else { return }
        DeferredSheetAction.shared.enqueue(for: owner, validate: context.validate) { owner in
            Task { @MainActor in
                do { try await Self.apply(rows, from: report, context: context, side: side) }
                catch { owner.fail("Selection stopped", error.localizedDescription) }
            }
        }
    }
    static func apply(_ rows: [ComparisonRow], from report: ComparisonReport, context: ComparisonContext, side: PaneSide) async throws {
        try context.validate()
        let files = rows.flatMap { side == .primary ? $0.left : $0.right }
        guard !files.isEmpty, rows.allSatisfy(canMark) else { throw ExplorerError.message("No selectable items for that pane.") }
        // Metadata validation can touch remote filesystems. It does not run on
        // MainActor and cannot redirect to another tab while awaiting I/O.
        let work = Task.detached(priority: .userInitiated) { try report.validate(rows) }
        try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
        try Task.checkCancellation(); try context.validate()
        guard let owner = context.owner, owner.windowRoot.routedWorkspace === owner, WorkspaceCommandScope.target(owner) === owner,
              let pane = side == .primary ? context.left : context.right else {
            throw ExplorerError.message("The window is no longer available for this selection.")
        }
        let urls = files.map(\.url)
        // Existing model reload preserves pending selection and expands any
        // group containing those paths. There is no copy, move or deletion here.
        pane.current.refresh(selecting: urls)
        context.controller?.focus(side, files: true)
    }
    private func updateVisible() {
        let needle = String(query.prefix(256))
        visible = (report?.rows ?? []).filter { filter.includes($0) && (needle.isEmpty || $0.name.localizedStandardContains(needle)) }
    }
    deinit { worker?.cancel() }
}
