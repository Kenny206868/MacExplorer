import AppKit
import SwiftUI
import ExplorerCore

/// Retains receivers until their asynchronous callbacks and our copy transaction
/// complete. All pasteboard reads happen on MainActor, never on a worker queue.
@MainActor final class FilePromiseInbox {
    static let shared = FilePromiseInbox()
    private var batches: [UUID: PromiseImportBatch] = [:]
    private let engine: FileOperationEngine
    private let center: OperationCenter
    var activeCount: Int { batches.count }
    init(engine: FileOperationEngine = .shared, center: OperationCenter = .shared) {
        self.engine = engine; self.center = center
    }

    @discardableResult func accept(_ pasteboard: NSPasteboard, into destination: URL, owner: ExplorerWorkspace) -> Bool {
        guard let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
              !receivers.isEmpty else { return false }
        return enqueue(receivers.map(AppKitPromiseSource.init), into: destination, owner: owner) != nil
    }
    @discardableResult func enqueue(_ sources: [any PromisedFileSource], into destination: URL,
                                   owner: ExplorerWorkspace, timeout: Duration = .seconds(600)) -> OperationRow? {
        guard !sources.isEmpty else { return nil }
        do {
            let batch = try PromiseImportBatch(sources: sources, destination: destination, owner: owner,
                                               engine: engine, center: center, timeout: timeout)
            batches[batch.id] = batch
            let id = batch.id
            batch.onFinish = { [weak self] in self?.batches.removeValue(forKey: id) }
            batch.start()
            return batch.row
        } catch { owner.fail("Cannot receive dragged files", error.localizedDescription); return nil }
    }
}

@MainActor private final class PromiseImportBatch {
    let id = UUID()
    var onFinish: (() -> Void)?
    private let sources: [any PromisedFileSource]
    private let engine: FileOperationEngine
    private let center: OperationCenter
    private let deadline: Duration
    private let queue: OperationQueue
    private let staging: URL
    private let stagingIdentity: FileFingerprint
    private let destination: URL
    private let destinationIdentity: FileFingerprint
    private weak var owner: ExplorerWorkspace?
    private weak var origin: BrowserTab?
    private let originLocation: Location
    let row = OperationRow(title: "Receive promised files")
    private var expected: [Int]
    private var received: [Int]
    private var urls: [URL] = []
    private var errors: [String] = []
    private var started = false
    private var installing = false
    private var ended = false
    private var operationID: UUID?
    private var timeout: Task<Void, Never>?

    init(sources: [any PromisedFileSource], destination: URL, owner: ExplorerWorkspace,
         engine: FileOperationEngine, center: OperationCenter, timeout: Duration) throws {
        self.sources = sources; self.destination = destination
        self.engine = engine; self.center = center; deadline = timeout
        destinationIdentity = try FileFingerprint(destination)
        self.owner = owner; origin = owner.current; originLocation = owner.current.location
        expected = sources.map { max(1, $0.expectedCount) }; received = sources.map { _ in 0 }
        queue = OperationQueue(); queue.name = "MacExplorer.file-promise-receive"; queue.maxConcurrentOperationCount = 2
        staging = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorer-Incoming-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        stagingIdentity = try FileFingerprint(staging)
    }
    func start() {
        center.jobs.insert(row, at: 0)
        row.progress = FileProgress(completed: 0, total: expected.reduce(0, +), name: "Waiting for the source application", phase: .waiting)
        row.status = "Receiving files from another application"
        row.cancellationAction = { [weak self] in self?.cancel() }
        let deadline = deadline
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: deadline) } catch { return }
            guard let self, !self.installing, !self.ended else { return }
            self.row.control.cancel(); self.row.cancelled = true
            self.row.errors.append("The source application did not finish its file promises. No unfinished file was installed. Temporary data is retained at \(self.staging.path).")
            self.row.status = "Source application timed out"; self.row.finished = true
            // A faulty provider might still be writing: never delete its active directory.
            self.finish(cleanup: false)
        }
        for (index, source) in sources.enumerated() {
            source.receive(into: staging, queue: queue) { [weak self] url, failure in
                Task { @MainActor in self?.didReceive(url, error: failure, receiver: index) }
            }
            expected[index] = max(expected[index], source.expectedCount)
        }
        started = true
        installIfReady()
    }
    private func cancel() {
        if let operationID, owner?.conflict?.operationID == operationID { owner?.answerCollision(.cancel) }
        if !installing {
            row.cancelled = true; row.finished = true
            row.status = "Cancelled — the source application may finish writing temporary data"
        }
    }
    private func didReceive(_ url: URL, error: String?, receiver index: Int) {
        guard !ended, received.indices.contains(index) else { return }
        received[index] += 1
        if let error { errors.append(error) }
        else {
            do {
                try PromisedImportFile.validate(url, in: staging, expectedInbox: stagingIdentity)
                if !urls.contains(where: { $0.path == url.path }) { urls.append(url) }
            } catch { errors.append(error.localizedDescription) }
        }
        if !row.finished {
            row.progress = FileProgress(completed: received.reduce(0, +), total: expected.reduce(0, +), name: url.lastPathComponent, phase: .waiting)
        }
        installIfReady()
    }
    private func installIfReady() {
        guard started, !ended, !installing, zip(received, expected).allSatisfy({ $0.0 >= $0.1 }) else { return }
        timeout?.cancel()
        guard !row.control.isCancelled, let owner, !urls.isEmpty else {
            row.errors += errors; row.finished = true; row.cancelled = row.control.isCancelled
            row.status = row.cancelled ? "Cancelled" : "No promised files could be received"
            finish(cleanup: true); return
        }
        guard destinationIdentity.matchesIdentity(destination) else {
            row.errors = errors + ["The receiving folder changed identity before the promised files arrived. Received files remain at \(staging.path)."]
            row.finished = true; row.status = "Receiving folder changed"
            finish(cleanup: false); return
        }
        installing = true
        let job = FileJob(.copy, sources: urls, destination: destination)
        operationID = job.id
        let control = row.control
        row.progress = FileProgress(completed: 0, total: urls.count, name: "Preparing received files")
        Task { [self, weak owner] in
            let result = await engine.run(job, control: control, progress: { [weak row] value in
                Task { @MainActor in row?.acceptProgress(value) }
            }, resolve: { [weak owner] collision in
                guard let owner else { return CollisionAnswer(.cancel) }
                return await owner.resolve(collision, operationID: job.id, control: control)
            })
            if let final = result.finalProgress { row.acceptProgress(final) }
            row.errors = errors + result.errors
            row.cancelled = result.cancelled || control.isCancelled
            row.finished = true; row.paused = false
            row.status = row.cancelled ? "Cancelled — completed imports retained" : row.errors.isEmpty ? "Imported \(result.outputs.count) files" : "Import finished with errors"
            if !result.receipt.steps.isEmpty { center.undoStack.append(result.receipt); center.redoStack.removeAll() }
            center.revision += 1
            if let origin, origin.location == originLocation { origin.refresh(selecting: result.outputs) }
            // A failed/skipped import remains recoverable; successful imports have
            // ordinary Copy receipts, never move-back destinations in a temp tree.
            let clean = !row.cancelled && row.errors.isEmpty && result.skippedSources.isEmpty
            if !clean { row.errors.append("Received originals are retained at \(staging.path).") }
            finish(cleanup: clean)
        }
    }
    private func finish(cleanup: Bool) {
        guard !ended else { return }; ended = true
        timeout?.cancel(); timeout = nil; row.cancellationAction = nil
        if cleanup {
            let path = staging, identity = stagingIdentity
            Task.detached(priority: .utility) {
                guard identity.matchesIdentity(path) else { return }
                try? FileManager.default.removeItem(at: path)
            }
        }
        let callback = onFinish; onFinish = nil; callback?()
    }
}

/// SwiftUI remains the visual implementation. The hosting boundary only adds
/// the AppKit file-promise destination protocol, forwarding ordinary URL drops.
struct FilePromiseDropHost<Content: View>: NSViewRepresentable {
    let workspace: ExplorerWorkspace
    let content: Content
    init(workspace: ExplorerWorkspace, @ViewBuilder content: () -> Content) {
        self.workspace = workspace; self.content = content()
    }
    func makeNSView(context: Context) -> PromiseDropHostingView {
        let view = PromiseDropHostingView(rootView: AnyView(content.environment(\.self, context.environment).environment(\.colorScheme, context.environment.colorScheme)))
        view.sizingOptions = []; view.workspace = workspace
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        view.registerPromises()
        return view
    }
    func updateNSView(_ view: PromiseDropHostingView, context: Context) {
        view.workspace = workspace
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        view.rootView = AnyView(content.environment(\.self, context.environment).environment(\.colorScheme, context.environment.colorScheme))
        view.registerPromises()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PromiseDropHostingView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 350, height: proposal.height ?? 400)
    }
}

@MainActor final class PromiseDropHostingView: NSHostingView<AnyView> {
    weak var workspace: ExplorerWorkspace?
    func registerPromises() { registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); registerPromises() }
    private func accepts(_ info: NSDraggingInfo) -> Bool {
        guard workspace?.destination != nil, !(info.draggingSource is FileDragAnchorView) else { return false }
        return info.draggingPasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .copy : super.draggingEntered(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .copy : super.draggingUpdated(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) || super.prepareForDragOperation(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard accepts(sender), let workspace, let fallback = workspace.destination else { return super.performDragOperation(sender) }
        let folder = FileDragRouter.shared.folder(at: sender.draggingLocation, in: window, workspace: workspace) ?? fallback
        return FilePromiseInbox.shared.accept(sender.draggingPasteboard, into: folder, owner: workspace)
    }
}
