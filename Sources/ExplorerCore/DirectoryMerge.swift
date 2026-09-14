import Foundation

/// Packages are indivisible documents; links are objects, never traversal edges.
enum DirectoryMergeGuard {
    static func isPlainDirectory(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let values = try? url.resourceValues(forKeys: [.isPackageKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true, values.isPackage != true else { return false }
        return true
    }
    static func canMerge(_ source: URL, _ target: URL) -> Bool {
        guard isPlainDirectory(source), isPlainDirectory(target),
              !FileNames.isDescendant(source, of: target), !FileNames.isDescendant(target, of: source),
              let fingerprint = try? FileFingerprint(source), !fingerprint.matchesIdentity(target) else { return false }
        return true
    }
}
private final class MergeAncestry: @unchecked Sendable {
    let source: URL
    let target: URL
    let sourceIdentity: FileFingerprint
    let targetIdentity: FileFingerprint
    let parent: MergeAncestry?
    init(source: URL, target: URL, parent: MergeAncestry?) throws {
        guard DirectoryMergeGuard.canMerge(source, target) else { throw ExplorerError.message("Only distinct, non-overlapping ordinary folders can be merged.") }
        self.source = source; self.target = target; self.parent = parent
        sourceIdentity = try FileFingerprint(source); targetIdentity = try FileFingerprint(target)
    }
    func validate() throws {
        var cursor: MergeAncestry? = self
        while let item = cursor {
            guard DirectoryMergeGuard.isPlainDirectory(item.source), DirectoryMergeGuard.isPlainDirectory(item.target),
                  item.sourceIdentity.matchesIdentity(item.source), item.targetIdentity.matchesIdentity(item.target) else {
                throw ExplorerError.message("A merge folder changed identity or became a link. Remaining work stopped to protect the filesystem.")
            }
            cursor = item.parent
        }
    }
}
private enum MergeWork { case visit(URL, URL, MergeAncestry), finish(MergeAncestry) }

extension FileOperationEngine {
    /// The gate is already held. Each child has its own durable receipt boundary,
    /// so completed work survives cancellation or a later process crash.
    func mergeContents(_ job: FileJob, source: URL, target: URL, receipt: OperationReceipt,
                       control: OperationControl, reporter: TransferProgressReporter,
                       resolve: @Sendable (FileCollision) async -> CollisionAnswer) async -> FileJobResult {
        var result = FileJobResult(title: job.title); result.receipt = receipt
        let manager = FileManager.default
        var changed = false, skipped = false
        var leafPolicy: CollisionChoice?
        do {
            guard job.kind == .copy || job.kind == .move else { throw ExplorerError.message("This operation does not support folder merging.") }
            try guardSource(source)
            let root = try MergeAncestry(source: source, target: target, parent: nil)
            let recoveryParent = source.deletingLastPathComponent(), recoveryParentIdentity = try FileFingerprint(source.deletingLastPathComponent())
            var work: [MergeWork] = [.finish(root)]
            func children(_ folder: MergeAncestry) throws -> [MergeWork] {
                try folder.validate()
                return try manager.contentsOfDirectory(at: folder.source, includingPropertiesForKeys: nil)
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }.reversed()
                    .map { .visit($0, folder.target.appendingPathComponent($0.lastPathComponent), folder) }
            }
            work.append(contentsOf: try children(root))
            while let next = work.popLast() {
                try control.checkpoint()
                switch next {
                case .visit(let child, var destination, let ancestry):
                    try ancestry.validate(); try FileNames.validate(child.lastPathComponent); try guardSource(child)
                    if DirectoryMergeGuard.canMerge(child, destination) {
                        let nested = try MergeAncestry(source: child, target: destination, parent: ancestry)
                        work.append(.finish(nested)); work.append(contentsOf: try children(nested)); continue
                    }
                    reporter.begin(name: child.lastPathComponent, copying: job.kind == .copy)
                    var replace = false
                    if FileNames.exists(destination) {
                        let sourceBefore = try FileFingerprint(child), targetBefore = try FileFingerprint(destination)
                        let answer: CollisionAnswer
                        if let leafPolicy { answer = CollisionAnswer(leafPolicy) }
                        else { reporter.phase(.waiting, name: child.lastPathComponent); answer = await resolve(FileCollision(source: child, destination: destination)) }
                        try control.checkpoint(); try ancestry.validate()
                        guard sourceBefore.matches(child), targetBefore.matches(destination) else { throw ExplorerError.message("An item changed while the merge decision was open. No replacement was performed.") }
                        switch answer.choice {
                        case .cancel: control.cancel(); throw CancellationError()
                        case .skip: skipped = true; if answer.applyToAll { leafPolicy = .skip }; continue
                        case .keepBoth: destination = FileNames.unique(destination)
                        case .replace: replace = true
                        case .merge: throw ExplorerError.message("Packages, links, and files cannot be merged as folders.")
                        }
                        if answer.applyToAll { leafPolicy = answer.choice }
                    }
                    reporter.phase(job.kind == .copy ? .copying : .processing, name: child.lastPathComponent)
                    let steps = try transfer(job, source: child, target: destination, replace: replace, control: control, reporter: reporter, sourceRecoveryDirectory: recoveryParent)
                    var updated = result.receipt; updated.steps.insert(contentsOf: steps, at: 0)
                    try record(updated); result.receipt = updated; changed = true; reporter.commitChild()
                case .finish(let ancestry):
                    try ancestry.validate()
                    if job.kind == .move {
                        guard try manager.contentsOfDirectory(atPath: ancestry.source.path).isEmpty else { skipped = true; continue }
                        guard recoveryParentIdentity.matchesIdentity(recoveryParent) else { throw ExplorerError.message("The source's parent changed during merging. The empty source folder was retained.") }
                        let backup = recoveryParent.appendingPathComponent(".MacExplorer-merged-directory-" + UUID().uuidString)
                        try moveDurably(ancestry.source, to: backup, emptyDirectory: true)
                        var updated = result.receipt
                        updated.steps.insert(try UndoStep(.move, source: backup, destination: ancestry.source, emptyDirectory: true), at: 0)
                        try record(updated); result.receipt = updated; changed = true
                    }
                }
            }
            if !skipped { result.completedSources = [source] }
        } catch is CancellationError { result.cancelled = true }
        catch { result.errors.append("\(source.lastPathComponent): \(error.localizedDescription)") }
        if result.cancelled || !result.errors.isEmpty { _ = rollbackJournal(into: &result) }
        if skipped { result.skippedSources = [source] }
        if changed || !result.completedSources.isEmpty { result.outputs = [target] }
        return result
    }
}
