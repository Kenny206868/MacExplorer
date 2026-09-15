import SwiftUI
import ExplorerCore

/// The model owns an immutable archive index. No view getter enumerates, sorts
/// or filters the complete archive; search projection runs on a bounded lane.
@MainActor final class ArchiveLocationModel: ObservableObject {
    private static let reads = FileReadExecutor(name: "archive-navigation", concurrency: 2, quality: .userInitiated)
    let source: URL
    let engine: FileOperationEngine
    @Published private(set) var catalog: ArchiveCatalog?
    @Published private(set) var listing = ArchiveDirectoryListing.empty
    @Published private(set) var listingRevision: UInt64 = 0
    @Published var selection = Set<String>() { didSet { cachedSelection = nil } }
    @Published var password = ""
    @Published var loading = false
    @Published var busy = false
    @Published private(set) var filtering = false
    @Published var notice: String?
    @Published var prompt: ArchiveEditPrompt?
    @Published var pending: ArchiveMutation?
    private(set) var fingerprint: FileFingerprint?
    private(set) var editable = false
    private(set) var encrypted = false
    private(set) var indexBuilds = 0
    private(set) var projectionBuilds = 0
    private var index: ArchiveDirectoryIndex?
    private var folder = "", query = ""
    private var cachedSelection: [ArchiveMember]?
    private var scanControl = OperationControl()
    private var projection: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(source: URL, engine: FileOperationEngine = .shared) { self.source = source; self.engine = engine }
    var selected: [ArchiveMember] {
        if let cachedSelection { return cachedSelection }
        let result = listing.selected(selection); cachedSelection = result; return result
    }
    func show(folder: String, query: String) {
        guard folder != self.folder || query != self.query else { return }
        if folder != self.folder { selection = [] }
        self.folder = folder; self.query = query; project()
    }
    func scan(force: Bool = false) async {
        scanControl.cancel(); let control = OperationControl(); scanControl = control
        loading = true
        let source = source, options = ArchiveReadOptions(passphrase: password)
        let cached = !force && index != nil ? fingerprint : nil
        do {
            let prepared: (ArchiveCatalog, FileFingerprint, ArchiveDirectoryIndex)? = try await withTaskCancellationHandler {
                try await Self.reads.run { cancellation in
                    let identity = try FileFingerprint(source)
                    if let cached, cached.inode == identity.inode, cached.device == identity.device,
                       cached.size == identity.size, cached.modified == identity.modified { return nil }
                    let catalog = try ArchiveCatalog.read(source, options: options, control: control)
                    let index = try ArchiveDirectoryIndex(members: catalog.members) {
                        try control.checkpoint(); try cancellation.check()
                    }
                    guard identity.matches(source) else { throw ExplorerError.message("Archive changed while reading. Reload it.") }
                    return (catalog, identity, index)
                }
            } onCancel: { control.cancel() }
            guard !Task.isCancelled, scanControl === control else { return }
            if let prepared { install(catalog: prepared.0, fingerprint: prepared.1, index: prepared.2) }
            else { loading = false }
        } catch {
            guard !Task.isCancelled, scanControl === control else { return }
            loading = false; catalog = nil; fingerprint = nil; index = nil; editable = false; encrypted = false
            notice = error.localizedDescription; project()
        }
    }
    private func install(catalog: ArchiveCatalog, fingerprint: FileFingerprint, index: ArchiveDirectoryIndex) {
        self.index = index; self.fingerprint = fingerprint; indexBuilds += 1
        encrypted = index.hasEncryption
        let format = catalog.format.lowercased()
        editable = !encrypted && !index.hasUnsupportedMembers && (format.hasPrefix("zip") || format.contains("tar") || format.contains("pax"))
        self.catalog = catalog; loading = false; project()
    }
    private func project() {
        projection?.cancel(); projection = nil; generation &+= 1
        guard let index else { installListing(.empty); return }
        let unfiltered = index.listing(in: folder)
        if query.isEmpty { installListing(unfiltered); return }
        let query = query, token = generation
        filtering = true
        projection = Task { [weak self] in
            do {
                let result = try await FileReadExecutor.presentation.run { cancellation in
                    try unfiltered.filtered(by: query, checkingCancellation: cancellation.check)
                }
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.installListing(result); self.projection = nil
            } catch {
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.notice = error.localizedDescription; self.filtering = false; self.projection = nil
            }
        }
    }
    private func installListing(_ value: ArchiveDirectoryListing) {
        cachedSelection = nil; listing = value; projectionBuilds += 1
        let retained = selection.filter(value.contains)
        if retained != selection { selection = retained }
        filtering = false; listingRevision &+= 1
    }
    func stop() {
        scanControl.cancel(); projection?.cancel(); projection = nil; generation &+= 1
        password = ""; filtering = false
    }
    func apply(_ mutation: ArchiveMutation, center: OperationCenter) async {
        guard !busy, !loading, !filtering, editable, let fingerprint else { return }
        busy = true; notice = nil
        let row = OperationRow(title: "Edit " + source.lastPathComponent); center.jobs.insert(row, at: 0)
        row.status = "Rebuilding archive"
        let result = await engine.editArchive(source, expected: fingerprint, mutation: mutation, control: row.control)
        row.cancelled = result.cancelled; row.errors = result.errors; row.finished = true
        row.status = result.cancelled ? "Cancelled — original retained" : result.errors.isEmpty ? "Archive saved" : "Archive edit stopped"
        if !result.receipt.steps.isEmpty { center.undoStack.append(result.receipt); center.redoStack.removeAll() }
        selection = []; busy = false; center.revision += 1
        notice = result.errors.isEmpty ? (result.cancelled ? "Edit cancelled." : "Saved. The previous archive is retained in Recovery & history.") : result.errors.joined(separator: "\n")
        await scan()
    }
}
