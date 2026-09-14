import Foundation

/// Thread-safe cooperative control. Pausing and cancellation are observed between entries
/// (and at FileManager delegate boundaries), never by interrupting an atomic rename.
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
    public init(_ kind: FileJobKind, sources: [URL] = [], destination: URL? = nil, names: [String: String] = [:]) {
        id = UUID(); self.kind = kind; self.sources = FileNames.independentRoots(sources); self.destination = destination; self.names = names
    }
    public var title: String { kind.rawValue.capitalized }
}
public struct FileProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let name: String
    public let bytes: Int64
    public init(completed: Int, total: Int, name: String, bytes: Int64 = 0) { self.completed = completed; self.total = total; self.name = name; self.bytes = bytes }
}
public struct FileCollision: Sendable { public let source: URL; public let destination: URL }
public enum CollisionChoice: String, CaseIterable, Sendable { case keepBoth = "Keep Both", replace = "Replace", skip = "Skip", cancel = "Cancel" }
public struct CollisionAnswer: Sendable {
    public let choice: CollisionChoice
    public let applyToAll: Bool
    public init(_ choice: CollisionChoice, applyToAll: Bool = false) { self.choice = choice; self.applyToAll = applyToAll }
}
public struct FileFingerprint: Codable, Sendable {
    public let inode: UInt64
    public let size: UInt64
    public let modified: Date
    public init(_ url: URL) throws {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        size = (a[.size] as? NSNumber)?.uint64Value ?? 0
        modified = a[.modificationDate] as? Date ?? .distantPast
    }
    public func matches(_ url: URL) -> Bool {
        guard let now = try? FileFingerprint(url) else { return false }
        return inode == now.inode && size == now.size && modified == now.modified
    }
}
public struct UndoStep: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case move, trash }
    public let kind: Kind
    public let source: URL
    public let destination: URL?
    public let expected: FileFingerprint
    public init(_ kind: Kind, source: URL, destination: URL? = nil) throws {
        self.kind = kind; self.source = source; self.destination = destination; expected = try FileFingerprint(source)
    }
}
public struct OperationReceipt: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var title: String
    public var steps: [UndoStep]
    public init(title: String, steps: [UndoStep] = []) { self.title = title; self.steps = steps }
}
public struct FileJobResult: Sendable {
    public var receipt: OperationReceipt
    public var errors: [String] = []
    public var outputs: [URL] = []
    public var remaining: [UndoStep] = []
    public var cancelled = false
    public init(title: String) { receipt = OperationReceipt(title: title) }
}

private final class CopyDelegate: NSObject, FileManagerDelegate {
    let control: OperationControl
    init(_ control: OperationControl) { self.control = control }
    func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool { (try? control.checkpoint()) != nil }
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, copyingItemAt srcURL: URL, to dstURL: URL) -> Bool { false }
}

/// One serialization gate for all windows, including across actor reentrancy while a
/// collision prompt is awaiting a decision. The actor never runs filesystem work on MainActor.
public actor FileOperationEngine {
    public static let shared = FileOperationEngine()
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    public init() {}
    private func acquire() async {
        if occupied { await withCheckedContinuation { waiters.append($0) } }
        else { occupied = true }
    }
    private func release() {
        if waiters.isEmpty { occupied = false } else { waiters.removeFirst().resume() }
    }
    public static var journalDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacExplorer/Recovery", isDirectory: true)
    }
    private func record(_ receipt: OperationReceipt) throws {
        guard !receipt.steps.isEmpty else { return }
        let directory = Self.journalDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipt).write(to: directory.appendingPathComponent(receipt.id.uuidString + ".json"), options: .atomic)
    }
    public func history() -> [OperationReceipt] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.journalDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(OperationReceipt.self, from: $0) } }.sorted { $0.date > $1.date }
    }
    private func guardSource(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        let protected = ["/", "/System", "/Library", "/Users", "/Volumes", FileManager.default.homeDirectoryForCurrentUser.path]
        guard !protected.contains(standardized.path), standardized.lastPathComponent != ".", standardized.lastPathComponent != ".." else { throw ExplorerError.message("This filesystem root cannot be modified: \(url.path)") }
        let values = try? url.resourceValues(forKeys: [.isVolumeKey])
        guard values?.isVolume != true else { throw ExplorerError.message("Eject a volume instead of moving or deleting its root.") }
    }
    private func coordinated<T>(_ source: URL, _ destination: URL, body: () throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<T, Error>?
        coordinator.coordinate(readingItemAt: source, options: [], writingItemAt: destination, options: .forReplacing, error: &coordinationError) { _, _ in
            outcome = Result { try body() }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw ExplorerError.message("The filesystem did not grant coordinated access.") }
        return try outcome.get()
    }
    private func transfer(_ job: FileJob, source: URL, target: URL, replace: Bool, control: OperationControl) throws -> [UndoStep] {
        let manager = FileManager(), delegate = CopyDelegate(control); manager.delegate = delegate
        try guardSource(source)
        let entry = try FileEntry(url: source)
        if entry.isDirectory && !entry.isSymbolicLink && FileNames.isDescendant(target, of: source) { throw ExplorerError.message("A folder cannot be placed inside itself.") }
        guard source.standardizedFileURL != target.standardizedFileURL else { return [] }
        let parent = target.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".MacExplorer-stage-" + UUID().uuidString)
        let backup = parent.appendingPathComponent(".MacExplorer-replaced-" + UUID().uuidString)
        return try coordinated(source, target) {
            var displaced = false, staged = false
            do {
                try control.checkpoint()
                switch job.kind {
                case .copy: try manager.copyItem(at: source, to: stage)
                case .symbolicLink: try manager.createSymbolicLink(at: stage, withDestinationURL: source)
                default: try manager.moveItem(at: source, to: stage)
                }
                staged = true
                // A cancelled FileManager delegate may leave an incomplete copy. It must never be installed.
                try control.checkpoint()
                if FileNames.exists(target) {
                    guard replace else { throw ExplorerError.message("The destination changed while copying. No existing file was overwritten.") }
                    try manager.moveItem(at: target, to: backup); displaced = true
                }
                try manager.moveItem(at: stage, to: target); staged = false
                var undo: [UndoStep] = []
                if job.kind == .move { undo.append(try UndoStep(.move, source: target, destination: source)) }
                else { undo.append(try UndoStep(.trash, source: target)) }
                if displaced { undo.append(try UndoStep(.move, source: backup, destination: target)) }
                return undo
            } catch {
                // Best-effort rollback never destroys either the source or a replacement backup.
                if staged && job.kind == .move && !FileNames.exists(source) { try? manager.moveItem(at: stage, to: source) }
                else if FileNames.exists(stage) && job.kind != .move { try? manager.removeItem(at: stage) }
                if displaced && !FileNames.exists(target) { try? manager.moveItem(at: backup, to: target) }
                throw error
            }
        }
    }
    public func run(_ job: FileJob, control: OperationControl, progress: @Sendable (FileProgress) -> Void, resolve: @Sendable (FileCollision) async -> CollisionAnswer) async -> FileJobResult {
        await acquire(); defer { release() }
        var result = FileJobResult(title: job.title), sticky: CollisionChoice?
        let manager = FileManager.default
        if [.createFolder, .createFile, .compress, .extract].contains(job.kind) {
            do {
                try control.checkpoint()
                guard let destination = job.destination else { throw ExplorerError.message("Choose a destination folder.") }
                let output: URL
                switch job.kind {
                case .createFolder, .createFile:
                    output = destination
                    try FileNames.validate(output.lastPathComponent)
                    guard !FileNames.exists(output) else { throw ExplorerError.message("An item with that name already exists.") }
                    if job.kind == .createFolder { try manager.createDirectory(at: output, withIntermediateDirectories: false) }
                    else { try Data().write(to: output, options: .withoutOverwriting) }
                case .compress: output = try ArchiveService.compress(job.sources, to: destination, control: control)
                default:
                    guard let source = job.sources.first else { throw ExplorerError.message("Select an archive.") }
                    output = try ArchiveService.extract(source, to: destination, control: control)
                }
                result.outputs = [output]; result.receipt.steps = [try UndoStep(.trash, source: output)]
                try record(result.receipt)
            } catch is CancellationError { result.cancelled = true }
            catch { result.errors.append(error.localizedDescription) }
            progress(FileProgress(completed: 1, total: 1, name: result.outputs.first?.lastPathComponent ?? job.title))
            return result
        }
        for (index, source) in job.sources.enumerated() {
            progress(FileProgress(completed: index, total: job.sources.count, name: source.lastPathComponent))
            do {
                try control.checkpoint()
                try guardSource(source)
                var steps: [UndoStep] = []
                if job.kind == .trash {
                    var trashed: NSURL?
                    try manager.trashItem(at: source, resultingItemURL: &trashed)
                    if let trashed { steps = [try UndoStep(.move, source: trashed as URL, destination: source)] }
                    else { result.errors.append("macOS trashed \(source.lastPathComponent), but did not provide a restore URL.") }
                } else if job.kind == .delete {
                    try manager.removeItem(at: source)
                } else {
                    guard let directory = job.destination else { throw ExplorerError.message("Choose a destination folder.") }
                    let name = job.names[source.path] ?? source.lastPathComponent
                    try FileNames.validate(name)
                    var target = directory.appendingPathComponent(name)
                    if source.standardizedFileURL == target.standardizedFileURL && job.kind == .move { continue }
                    var replace = false
                    if FileNames.exists(target) {
                        let answer: CollisionAnswer
                        if let sticky { answer = CollisionAnswer(sticky) }
                        else { answer = await resolve(FileCollision(source: source, destination: target)) }
                        if answer.applyToAll { sticky = answer.choice }
                        switch answer.choice {
                        case .cancel: control.cancel(); throw CancellationError()
                        case .skip: continue
                        case .keepBoth: target = FileNames.unique(target)
                        case .replace:
                            // Replacing a file with itself is never a valid operation.
                            guard source.standardizedFileURL != target.standardizedFileURL else { throw ExplorerError.message("Choose Keep Both to duplicate an item in the same folder.") }
                            replace = true
                        }
                    }
                    steps = try transfer(job, source: source, target: target, replace: replace, control: control)
                    result.outputs.append(target)
                }
                result.receipt.steps.insert(contentsOf: steps, at: 0)
                try record(result.receipt)
            } catch is CancellationError { result.cancelled = true; break }
            catch { result.errors.append("\(source.lastPathComponent): \(error.localizedDescription)") }
        }
        progress(FileProgress(completed: job.sources.count, total: job.sources.count, name: result.cancelled ? "Cancelled" : "Finished"))
        return result
    }
    public func undo(_ receipt: OperationReceipt, control: OperationControl) async -> FileJobResult {
        await acquire(); defer { release() }
        var result = FileJobResult(title: receipt.title)
        for (index, step) in receipt.steps.enumerated() {
            do {
                try control.checkpoint()
                guard step.expected.matches(step.source) else { throw ExplorerError.message("\(step.source.lastPathComponent) changed since the operation. Undo stopped to protect newer changes.") }
                switch step.kind {
                case .move:
                    guard let destination = step.destination, !FileNames.exists(destination) else { throw ExplorerError.message("Undo destination is occupied. Move the conflicting item first.") }
                    try FileManager.default.moveItem(at: step.source, to: destination)
                    result.receipt.steps.insert(try UndoStep(.move, source: destination, destination: step.source), at: 0)
                    result.outputs.append(destination)
                case .trash:
                    var trashed: NSURL?
                    try FileManager.default.trashItem(at: step.source, resultingItemURL: &trashed)
                    if let trashed { result.receipt.steps.insert(try UndoStep(.move, source: trashed as URL, destination: step.source), at: 0) }
                }
            } catch {
                result.errors.append(error.localizedDescription); result.remaining = Array(receipt.steps[index...]); break
            }
        }
        do { try record(result.receipt) } catch { result.errors.append("Recovery log: \(error.localizedDescription)") }
        return result
    }
    /// Two-phase batch rename supports swaps and case-only renames without overwriting siblings.
    public func rename(_ mapping: [(URL, String)], control: OperationControl) async -> FileJobResult {
        await acquire(); defer { release() }
        var result = FileJobResult(title: "Rename")
        let manager = FileManager.default
        var staged: [(source: URL, stage: URL, target: URL)] = [], installed: [(source: URL, target: URL)] = []
        do {
            let sources = Set(mapping.map { $0.0.standardizedFileURL })
            var targets = Set<URL>()
            for (source, name) in mapping {
                try guardSource(source); try FileNames.validate(name)
                let target = source.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
                guard targets.insert(target).inserted else { throw ExplorerError.message("Two items would have the same name.") }
                if FileNames.exists(target) && !sources.contains(target) {
                    let a = try? FileFingerprint(source), b = try? FileFingerprint(target)
                    guard a?.inode == b?.inode else { throw ExplorerError.message("The name \(name) already exists.") }
                }
            }
            for (source, name) in mapping {
                try control.checkpoint()
                let stage = source.deletingLastPathComponent().appendingPathComponent(".MacExplorer-rename-" + UUID().uuidString)
                try manager.moveItem(at: source, to: stage)
                staged.append((source, stage, source.deletingLastPathComponent().appendingPathComponent(name)))
            }
            // Cancellation is deferred across the short commit phase to preserve all-or-rollback semantics.
            for item in staged {
                try manager.moveItem(at: item.stage, to: item.target)
                installed.append((item.source, item.target)); result.outputs.append(item.target)
            }
            for item in installed.reversed() { result.receipt.steps.append(try UndoStep(.move, source: item.target, destination: item.source)) }
            try record(result.receipt)
        } catch {
            // Move installed entries back to their unique staging names before restoring originals (swaps).
            for item in staged.reversed() where installed.contains(where: { $0.target == item.target }) { try? manager.moveItem(at: item.target, to: item.stage) }
            for item in staged where FileNames.exists(item.stage) && !FileNames.exists(item.source) { try? manager.moveItem(at: item.stage, to: item.source) }
            result.outputs = []; result.receipt.steps = []; result.errors.append(error.localizedDescription)
        }
        return result
    }
}
