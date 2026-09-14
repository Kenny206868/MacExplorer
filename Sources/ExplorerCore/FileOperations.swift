import Foundation
import ExplorerJournal

/// Cooperative control never interrupts an atomic filesystem rename.
public final class OperationControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false
    private var paused = false
    public init() {}
    public var isCancelled: Bool { condition.lock(); defer { condition.unlock() }; return cancelled }
    public func cancel() { condition.lock(); cancelled = true; paused = false; condition.broadcast(); condition.unlock() }
    public func setPaused(_ value: Bool) { condition.lock(); paused = value; condition.broadcast(); condition.unlock() }
    public func checkpoint() throws {
        condition.lock(); defer { condition.unlock() }
        while paused && !cancelled { condition.wait() }
        if cancelled { throw CancellationError() }
    }
}
public enum FileJobKind: String, Codable, Sendable { case copy, move, trash, delete, symbolicLink, createFolder, createFile, compress, extract }
public struct FileJob: Sendable, Identifiable {
    public let id: UUID
    public let kind: FileJobKind
    public let sources: [URL]
    public let destination: URL?
    public let names: [String: String]
    public let archiveOptions: ArchiveReadOptions?
    public init(_ kind: FileJobKind, sources: [URL] = [], destination: URL? = nil, names: [String: String] = [:], archiveOptions: ArchiveReadOptions? = nil) {
        id = UUID(); self.kind = kind; self.sources = FileNames.independentRoots(sources); self.destination = destination; self.names = names; self.archiveOptions = archiveOptions
    }
    public var title: String { kind.rawValue.capitalized }
}
public struct FileCollision: Sendable {
    public let source: URL
    public let destination: URL
    public let canMerge: Bool
    public init(source: URL, destination: URL) {
        self.source = source; self.destination = destination; canMerge = DirectoryMergeGuard.canMerge(source, destination)
    }
}
public enum CollisionChoice: String, CaseIterable, Sendable { case keepBoth = "Keep Both", merge = "Merge", replace = "Replace", skip = "Skip", cancel = "Cancel" }
public struct CollisionAnswer: Sendable {
    public let choice: CollisionChoice
    public let applyToAll: Bool
    public init(_ choice: CollisionChoice, applyToAll: Bool = false) { self.choice = choice; self.applyToAll = applyToAll }
}
public struct FileFingerprint: Codable, Sendable {
    public let inode: UInt64
    public let device: UInt64?
    public let size: UInt64
    public let modified: Date
    public init(_ url: URL) throws {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        device = (a[.systemNumber] as? NSNumber)?.uint64Value
        size = (a[.size] as? NSNumber)?.uint64Value ?? 0
        modified = a[.modificationDate] as? Date ?? .distantPast
    }
    public func matchesIdentity(_ url: URL) -> Bool {
        guard let now = try? FileFingerprint(url) else { return false }
        return inode != 0 && inode == now.inode && (device == nil || device == now.device)
    }
    public func matches(_ url: URL) -> Bool {
        guard let now = try? FileFingerprint(url) else { return false }
        return inode == now.inode && (device == nil || device == now.device) && size == now.size && modified == now.modified
    }
}
public struct UndoStep: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case move, trash }
    public let kind: Kind
    public let source: URL
    public let destination: URL?
    public let expected: FileFingerprint
    /// Our inverse child moves change container mtimes; require identity and
    /// emptiness instead. Optional for compatibility with older receipts.
    public let emptyDirectory: Bool?
    public init(_ kind: Kind, source: URL, destination: URL? = nil, emptyDirectory: Bool = false) throws {
        self.kind = kind; self.source = source; self.destination = destination
        self.emptyDirectory = emptyDirectory ? true : nil; expected = try FileFingerprint(source)
    }
    public func canRestore() -> Bool {
        if emptyDirectory == true {
            return expected.matchesIdentity(source) && DirectoryMergeGuard.isPlainDirectory(source)
                && (try? FileManager.default.contentsOfDirectory(atPath: source.path).isEmpty) == true
        }
        return expected.matches(source)
    }
}
public struct OperationReceipt: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var title: String
    public var steps: [UndoStep]
    public var renameBatch: Bool?
    public init(title: String, steps: [UndoStep] = []) { self.title = title; self.steps = steps }
}
public struct FileJobResult: Sendable {
    public var receipt: OperationReceipt
    public var errors: [String] = []
    public var outputs: [URL] = []
    public var completedSources: [URL] = []
    public var skippedSources: [URL] = []
    public var finalProgress: FileProgress?
    public var remaining: [UndoStep] = []
    public var cancelled = false
    public init(title: String) { receipt = OperationReceipt(title: title) }
}

/// The gate spans actor reentrancy while collision prompts await a decision.
/// All mutation paths share a durable journal and run off MainActor.
public actor FileOperationEngine {
    public static let shared = FileOperationEngine()
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    let recoveryDirectory: URL
    var operationJournal: FileJournal?
    var activeJournal: JournalTransaction?
    var managedStages: [ManagedOperationStage] = []
    let journalFault: (@Sendable (JournalFaultPoint) -> Void)?
    public init(recoveryDirectory: URL? = nil, journalFault: (@Sendable (JournalFaultPoint) -> Void)? = nil) {
        self.recoveryDirectory = recoveryDirectory ?? Self.journalDirectory; self.journalFault = journalFault
    }
    func acquire() async {
        if occupied { await withCheckedContinuation { waiters.append($0) } } else { occupied = true }
    }
    func release() { if waiters.isEmpty { occupied = false } else { waiters.removeFirst().resume() } }
    public static var journalDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacExplorer/Recovery", isDirectory: true)
    }
    func guardSource(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        let protected = ["/", "/System", "/Library", "/Users", "/Volumes", FileManager.default.homeDirectoryForCurrentUser.path]
        guard !protected.contains(standardized.path), standardized.lastPathComponent != ".", standardized.lastPathComponent != ".." else {
            throw ExplorerError.message("This filesystem root cannot be modified: \(url.path)")
        }
        let protectedJournal = recoveryDirectory.resolvingSymlinksInPath()
        let actualSource = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent)
        guard !FileNames.isDescendant(protectedJournal, of: actualSource), !FileNames.isDescendant(actualSource, of: protectedJournal) else {
            throw ExplorerError.message("The active recovery store and its ancestors cannot be modified by a file operation.")
        }
        let values = try? url.resourceValues(forKeys: [.isVolumeKey])
        guard values?.isVolume != true else { throw ExplorerError.message("Eject a volume instead of moving or deleting its root.") }
    }
    private func coordinated<T>(_ source: URL, _ destination: URL, body: () throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?, outcome: Result<T, Error>?
        coordinator.coordinate(readingItemAt: source, options: [], writingItemAt: destination, options: .forReplacing, error: &coordinationError) { _, _ in outcome = Result { try body() } }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw ExplorerError.message("The filesystem did not grant coordinated access.") }
        return try outcome.get()
    }
    func transfer(_ job: FileJob, source: URL, target: URL, replace: Bool, control: OperationControl,
                  reporter: TransferProgressReporter, sourceRecoveryDirectory: URL? = nil) throws -> [UndoStep] {
        try guardSource(source)
        let entry = try FileEntry(url: source)
        if entry.isDirectory && !entry.isSymbolicLink && FileNames.isDescendant(target, of: source) { throw ExplorerError.message("A folder cannot be placed inside itself.") }
        guard source.standardizedFileURL != target.standardizedFileURL else { return [] }
        let original = try FileFingerprint(source)
        let existing = FileNames.exists(target) ? try FileFingerprint(target) : nil
        if let existing, existing.inode == original.inode, existing.device == original.device {
            throw ExplorerError.message("The source and destination identify the same filesystem object. Choose Keep Both.")
        }
        let parent = target.deletingLastPathComponent(), parentIdentity = try FileFingerprint(target.deletingLastPathComponent())
        let crossVolume = job.kind == .move && original.device != parentIdentity.device
        return try coordinated(source, target) {
            try control.checkpoint()
            let container = try newStage(in: parent), stage = container.appendingPathComponent("payload")
            if job.kind == .copy || crossVolume {
                try NativeFileCopy.copy(from: source, to: stage, control: control) { reporter.copy($0) }
                guard original.matches(source) else { throw ExplorerError.message("The source changed during copying. The partial copy was not installed.") }
                try JournalDurability.synchronizeTree(stage) { try control.checkpoint() }
            } else if job.kind == .symbolicLink {
                try FileManager.default.createSymbolicLink(at: stage, withDestinationURL: source)
            } else { try moveDurably(source, to: stage) }
            try control.checkpoint()
            let backup = parent.appendingPathComponent(".MacExplorer-replaced-" + UUID().uuidString)
            var displaced = false
            if FileNames.exists(target) {
                guard replace, let existing, existing.matches(target) else { throw ExplorerError.message("The destination changed while copying. No existing file was overwritten.") }
                try guardSource(target); try moveDurably(target, to: backup); displaced = true
            }
            // Cooperative cancellation is deferred, but each exclusive rename
            // still has a durable intent and recoverable process-crash boundary.
            try moveDurably(stage, to: target)
            var undo: [UndoStep]
            if crossVolume {
                guard original.matches(source) else { throw ExplorerError.message("The source changed before the cross-volume move committed.") }
                let recovery = (sourceRecoveryDirectory ?? source.deletingLastPathComponent()).appendingPathComponent(".MacExplorer-moved-" + UUID().uuidString)
                try moveDurably(source, to: recovery)
                undo = [try UndoStep(.trash, source: target), try UndoStep(.move, source: recovery, destination: source)]
            } else {
                undo = [try UndoStep(job.kind == .move ? .move : .trash, source: target, destination: job.kind == .move ? source : nil)]
            }
            if displaced { undo.append(try UndoStep(.move, source: backup, destination: target)) }
            return undo
        }
    }
}
