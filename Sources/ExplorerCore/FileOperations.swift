import Foundation

/// Thread-safe cooperative control. Pausing and cancellation are observed between entries
/// and native copy callbacks, never by interrupting an atomic rename.
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
        self.source = source; self.destination = destination
        canMerge = DirectoryMergeGuard.canMerge(source, destination)
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
    /// Empty source containers in a move-merge are retained, not deleted. Their
    /// mtimes change as our inverse child operations run; identity + emptiness
    /// protect them during both Undo and Redo. Optional for older receipts.
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
    /// Optional for backwards-compatible decoding of v1 recovery receipts.
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
    private let recoveryDirectory: URL
    public init(recoveryDirectory: URL? = nil) { self.recoveryDirectory = recoveryDirectory ?? Self.journalDirectory }
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
    func record(_ receipt: OperationReceipt) throws {
        guard !receipt.steps.isEmpty else { return }
        let directory = recoveryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipt).write(to: directory.appendingPathComponent(receipt.id.uuidString + ".json"), options: .atomic)
    }
    public func history() -> [OperationReceipt] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(OperationReceipt.self, from: $0) } }.sorted { $0.date > $1.date }
    }
    func guardSource(_ url: URL) throws {
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
    func transfer(_ job: FileJob, source: URL, target: URL, replace: Bool, control: OperationControl,
                          reporter: TransferProgressReporter) throws -> [UndoStep] {
        let manager = FileManager(), delegate = CopyDelegate(control); manager.delegate = delegate
        try guardSource(source)
        let entry = try FileEntry(url: source)
        if entry.isDirectory && !entry.isSymbolicLink && FileNames.isDescendant(target, of: source) { throw ExplorerError.message("A folder cannot be placed inside itself.") }
        guard source.standardizedFileURL != target.standardizedFileURL else { return [] }
        let original = try FileFingerprint(source)
        let existing = FileNames.exists(target) ? try FileFingerprint(target) : nil
        if let existing, existing.inode == original.inode, existing.device == original.device {
            throw ExplorerError.message("The source and destination identify the same filesystem object. Choose Keep Both.")
        }
        let parent = target.deletingLastPathComponent()
        let stagingDirectory = parent.appendingPathComponent(".MacExplorer-stage-" + UUID().uuidString)
        let stage = stagingDirectory.appendingPathComponent("payload")
        let backup = parent.appendingPathComponent(".MacExplorer-replaced-" + UUID().uuidString)
        return try coordinated(source, target) {
            try control.checkpoint()
            // The partial object lives in an exclusively created private container.
            try manager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer {
                // Never recursively purge an unrecovered source after rollback fails.
                if let children = try? manager.contentsOfDirectory(atPath: stagingDirectory.path), children.isEmpty {
                    try? manager.removeItem(at: stagingDirectory)
                }
            }
            var displaced = false, installed = false
            do {
                switch job.kind {
                case .copy:
                    try NativeFileCopy.copy(from: source, to: stage, control: control) { reporter.copy($0) }
                    guard original.matches(source) else { throw ExplorerError.message("The source changed during copying. The partial copy was not installed.") }
                case .symbolicLink: try manager.createSymbolicLink(at: stage, withDestinationURL: source)
                default: try manager.moveItem(at: source, to: stage)
                }
                try control.checkpoint()
                if FileNames.exists(target) {
                    guard replace, let existing, existing.matches(target) else {
                        throw ExplorerError.message("The destination changed while copying. No existing file was overwritten.")
                    }
                    try manager.moveItem(at: target, to: backup); displaced = true
                }
                // Commit is deliberately not interruptible between these renames.
                try manager.moveItem(at: stage, to: target); installed = true
                var undo = [try UndoStep(job.kind == .move ? .move : .trash, source: target, destination: job.kind == .move ? source : nil)]
                if displaced { undo.append(try UndoStep(.move, source: backup, destination: target)) }
                return undo
            } catch {
                let originalError = error
                var recoveryErrors: [String] = []
                if installed {
                    do { try manager.moveItem(at: target, to: stage) }
                    catch { recoveryErrors.append("Installed object remains at \(target.path): \(error.localizedDescription)") }
                }
                if FileNames.exists(stage) {
                    if job.kind == .move {
                        if !FileNames.exists(source) {
                            do { try manager.moveItem(at: stage, to: source) }
                            catch { recoveryErrors.append("Original remains recoverable at \(stage.path): \(error.localizedDescription)") }
                        } else { recoveryErrors.append("A source-path conflict prevents recovery; retained object: \(stage.path)") }
                    } else {
                        do { try manager.removeItem(at: stage) }
                        catch { recoveryErrors.append("Partial copy retained at \(stage.path): \(error.localizedDescription)") }
                    }
                }
                if displaced {
                    if !FileNames.exists(target) {
                        do { try manager.moveItem(at: backup, to: target) }
                        catch { recoveryErrors.append("Replacement backup remains at \(backup.path): \(error.localizedDescription)") }
                    } else { recoveryErrors.append("Replacement backup retained at \(backup.path)") }
                }
                if recoveryErrors.isEmpty { throw originalError }
                throw ExplorerError.message(([originalError.localizedDescription] + recoveryErrors).joined(separator: "\n"))
            }
        }
    }
    public func run(_ job: FileJob, control: OperationControl, progress: @escaping @Sendable (FileProgress) -> Void, resolve: @Sendable (FileCollision) async -> CollisionAnswer) async -> FileJobResult {
        await acquire(); defer { release() }
        var result = FileJobResult(title: job.title), sticky: CollisionChoice?
        let manager = FileManager.default
        let reporter = TransferProgressReporter(total: job.sources.count, observer: progress)
        if job.kind == .copy {
            var total: Int64 = 0, completeEstimate = true
            for source in job.sources {
                reporter.phase(.calculating, name: source.lastPathComponent)
                do {
                    let size = try TransferInventory.logicalBytes(source, control: control)
                    let (sum, overflow) = total.addingReportingOverflow(size)
                    if overflow { completeEstimate = false } else { total = sum }
                } catch is CancellationError {
                    result.cancelled = true; result.finalProgress = reporter.finish(cancelled: true); return result
                } catch { completeEstimate = false }
            }
            reporter.estimate(completeEstimate ? total : nil)
        }
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
                    output = try ArchiveService.extract(source, to: destination, control: control, options: job.archiveOptions)
                }
                result.outputs = [output]; result.receipt.steps = [try UndoStep(.trash, source: output)]
                try record(result.receipt)
            } catch is CancellationError { result.cancelled = true }
            catch { result.errors.append(error.localizedDescription) }
            let final = FileProgress(completed: result.outputs.isEmpty ? 0 : 1, total: 1, name: result.outputs.first?.lastPathComponent ?? job.title,
                                     phase: result.cancelled ? .cancelled : .finished)
            result.finalProgress = final; progress(final)
            return result
        }
        for source in job.sources {
            reporter.begin(name: source.lastPathComponent, copying: job.kind == .copy)
            var succeeded = false
            defer { reporter.end(success: succeeded) }
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
                    if source.standardizedFileURL == target.standardizedFileURL && job.kind == .move { result.skippedSources.append(source); continue }
                    var replace = false, merge = false
                    if FileNames.exists(target) {
                        let collision = FileCollision(source: source, destination: target)
                        let answer: CollisionAnswer
                        if let sticky, sticky != .merge || collision.canMerge { answer = CollisionAnswer(sticky) }
                        else {
                            reporter.phase(.waiting, name: target.lastPathComponent)
                            answer = await resolve(collision)
                            reporter.phase(job.kind == .copy ? .copying : .processing, name: source.lastPathComponent)
                        }
                        if answer.applyToAll { sticky = answer.choice }
                        switch answer.choice {
                        case .cancel: control.cancel(); throw CancellationError()
                        case .skip: result.skippedSources.append(source); continue
                        case .keepBoth: target = FileNames.unique(target)
                        case .merge:
                            guard collision.canMerge, job.kind == .copy || job.kind == .move else {
                                throw ExplorerError.message("Only distinct ordinary folders can be merged. Packages and symbolic links are not traversed.")
                            }
                            merge = true
                        case .replace:
                            guard source.standardizedFileURL != target.standardizedFileURL else { throw ExplorerError.message("Choose Keep Both to duplicate an item in the same folder.") }
                            replace = true
                        }
                    }
                    if merge {
                        let merged = await mergeContents(job, source: source, target: target, receipt: result.receipt,
                                                         control: control, reporter: reporter, resolve: resolve)
                        result.receipt = merged.receipt
                        result.errors += merged.errors; result.outputs += merged.outputs
                        result.completedSources += merged.completedSources; result.skippedSources += merged.skippedSources
                        succeeded = !merged.completedSources.isEmpty
                        if merged.cancelled { result.cancelled = true; break }
                        continue
                    }
                    steps = try transfer(job, source: source, target: target, replace: replace, control: control, reporter: reporter)
                    result.outputs.append(target)
                }
                result.completedSources.append(source); succeeded = true
                result.receipt.steps.insert(contentsOf: steps, at: 0)
                try record(result.receipt)
            } catch is CancellationError { result.cancelled = true; break }
            catch { result.errors.append("\(source.lastPathComponent): \(error.localizedDescription)") }
        }
        result.cancelled = result.cancelled || control.isCancelled
        result.finalProgress = reporter.finish(cancelled: result.cancelled)
        return result
    }
    public func undo(_ receipt: OperationReceipt, control: OperationControl) async -> FileJobResult {
        await acquire(); defer { release() }
        var result = FileJobResult(title: receipt.title)
        if receipt.renameBatch == true {
            do {
                // Validate the complete cycle before staging any member. Sequential
                // inverse moves cannot restore A↔B swaps or longer rename cycles.
                for step in receipt.steps {
                    guard step.kind == .move, let destination = step.destination,
                          destination.deletingLastPathComponent() == step.source.deletingLastPathComponent(),
                          step.expected.matches(step.source) else {
                        throw ExplorerError.message("A renamed item changed or its recorded destination is invalid. Recovery stopped without modifying the batch.")
                    }
                }
                let mapping = receipt.steps.compactMap { step -> (URL, String)? in
                    step.destination.map { (step.source, $0.lastPathComponent) }
                }
                result = performRename(mapping, control: control)
                if !result.errors.isEmpty || result.cancelled { result.remaining = receipt.steps }
            } catch {
                result.errors.append(error.localizedDescription); result.remaining = receipt.steps
            }
            return result
        }
        for (index, step) in receipt.steps.enumerated() {
            do {
                try control.checkpoint()
                guard step.canRestore() else { throw ExplorerError.message("\(step.source.lastPathComponent) changed since the operation. Undo stopped to protect newer changes.") }
                switch step.kind {
                case .move:
                    guard let destination = step.destination, !FileNames.exists(destination) else { throw ExplorerError.message("Undo destination is occupied. Move the conflicting item first.") }
                    try FileManager.default.moveItem(at: step.source, to: destination)
                    result.receipt.steps.insert(try UndoStep(.move, source: destination, destination: step.source, emptyDirectory: step.emptyDirectory == true), at: 0)
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
    public func rename(_ mapping: [(URL, String)], control: OperationControl,
                       expected: [String: FileFingerprint] = [:]) async -> FileJobResult {
        await acquire(); defer { release() }
        // Validate after acquiring the cross-window serialization gate, not when
        // an editor first queues its work. A replaced source must not be renamed.
        for (source, _) in mapping {
            if let fingerprint = expected[source.standardizedFileURL.path], !fingerprint.matches(source) {
                var result = FileJobResult(title: "Rename")
                result.errors = ["\(source.lastPathComponent) changed while its name was being edited. No rename was performed."]
                return result
            }
        }
        return performRename(mapping, control: control)
    }
    private func performRename(_ mapping: [(URL, String)], control: OperationControl) -> FileJobResult {
        var result = FileJobResult(title: "Rename")
        result.receipt.renameBatch = true
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
                    guard a?.inode == b?.inode && a?.device == b?.device else { throw ExplorerError.message("The name \(name) already exists.") }
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
            for item in staged.reversed() where installed.contains(where: { $0.target == item.target }) {
                do { try manager.moveItem(at: item.target, to: item.stage) }
                catch { result.errors.append("Rollback could not stage \(item.target.path): \(error.localizedDescription)") }
            }
            for item in staged where FileNames.exists(item.stage) && !FileNames.exists(item.source) {
                do { try manager.moveItem(at: item.stage, to: item.source) }
                catch { result.errors.append("Original remains recoverable at \(item.stage.path): \(error.localizedDescription)") }
            }
            result.outputs = []; result.receipt.steps = []
            if error is CancellationError { result.cancelled = true }
            else { result.errors.append(error.localizedDescription) }
        }
        return result
    }
}
