import Foundation
import ExplorerJournal
import Darwin

extension FileOperationEngine {
    /// One durable archive checkpoint: recover the original before it, Undo
    /// after it. No cross-filesystem rename or in-place truncation is attempted.
    public func editArchive(_ source: URL, expected: FileFingerprint, mutation: ArchiveMutation,
                            control: OperationControl) async -> FileJobResult {
        await acquire(); defer { release() }
        var result = FileJobResult(title: "Edit " + source.lastPathComponent)
        do {
            try control.checkpoint(); try guardSource(source)
            guard try JournalIdentity(source).isRegularFile, expected.matches(source) else { throw ExplorerError.message("The archive changed since it was opened. Reload before editing.") }
            try beginJournal(result.receipt.title)
            let parent = source.deletingLastPathComponent(), parentIdentity = try JournalIdentity(source.deletingLastPathComponent())
            let stage = try newStage(in: parent).appendingPathComponent("archive")
            try ArchiveRewriter.rewrite(source, to: stage, mutation: mutation, control: control)
            // Keep Finder tags, ACLs, resource forks and quarantine on the
            // archive itself. Never copy its old data over the candidate.
            let metadata = copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW)
            guard copyfile(source.path, stage.path, nil, metadata) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: stage.path)
            try JournalDurability.synchronizeTree(stage) { try control.checkpoint() }
            try control.checkpoint()
            guard expected.matches(source), parentIdentity.matches(parent, exact: false) else { throw ExplorerError.message("Archive or containing folder changed; nothing was replaced.") }
            let backup = parent.appendingPathComponent(".MacExplorer-archive-original-" + UUID().uuidString)
            let edited = parent.appendingPathComponent(".MacExplorer-archive-edited-" + UUID().uuidString)
            try moveDurably(source, to: backup); try moveDurably(stage, to: source)
            var receipt = result.receipt
            receipt.steps = [try UndoStep(.move, source: source, destination: edited), try UndoStep(.move, source: backup, destination: source)]
            try record(receipt); result.receipt = receipt; result.outputs = [source]
        } catch is CancellationError { result.cancelled = true }
        catch { result.errors.append(error.localizedDescription) }
        finishJournal(&result); return result
    }
}
