import Foundation
import ExplorerJournal

public struct InterruptedFileOperation: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let started: Date
    public let state: String
    public let warning: String?
    public let pendingMutations: Int
}
public struct FileRecoveryReport: Sendable {
    public let resolved: Bool
    public let notices: [String]
    public let retainedArtifacts: [URL]
    public let receipt: OperationReceipt?
}
/// Undo records the exact remainder atomically with its inverse checkpoint.
/// A restart cannot replay an original step that was already checkpointed.
struct OperationCheckpoint: Codable {
    var schemaVersion = 1
    var updated = Date()
    let receipt: OperationReceipt
    let replacing: UUID?
    let remaining: OperationReceipt?
}
struct ManagedOperationStage { let url: URL; let identity: FileFingerprint }

extension FileOperationEngine {
    func openJournal() throws -> FileJournal {
        if let operationJournal { return operationJournal }
        let journal = try FileJournal(directory: recoveryDirectory.appendingPathComponent("Journal", isDirectory: true), fault: journalFault)
        operationJournal = journal; return journal
    }
    func beginJournal(_ title: String) throws {
        guard activeJournal == nil else { throw ExplorerError.message("An operation transaction is already active.") }
        let journal = try openJournal()
        guard try journal.summaries().isEmpty else {
            throw ExplorerError.message("An interrupted file operation needs review. Open Recovery History before starting another mutation.")
        }
        activeJournal = try journal.begin(title: title); managedStages = []
    }
    func transaction() throws -> JournalTransaction {
        guard let activeJournal else { throw ExplorerError.message("A durable operation transaction is required.") }; return activeJournal
    }
    func record(_ receipt: OperationReceipt, replacing: UUID? = nil, remaining: OperationReceipt? = nil) throws {
        let data = try JSONEncoder().encode(OperationCheckpoint(receipt: receipt, replacing: replacing, remaining: remaining))
        try transaction().checkpoint(receipt: data); cleanStages(removeContents: false)
    }
    func newStage(in directory: URL) throws -> URL {
        guard !FileNames.isDescendant(directory.resolvingSymlinksInPath(), of: recoveryDirectory.resolvingSymlinksInPath()) else {
            throw ExplorerError.message("The active recovery store is not a file-operation destination.")
        }
        let stage = directory.appendingPathComponent(".MacExplorer-stage-" + UUID().uuidString, isDirectory: true)
        try transaction().registerArtifact(stage)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        managedStages.append(ManagedOperationStage(url: stage, identity: try FileFingerprint(stage))); return stage
    }
    func moveDurably(_ source: URL, to destination: URL, emptyDirectory: Bool = false) throws {
        try transaction().move(source, to: destination, emptyDirectory: emptyDirectory)
    }
    /// Only the live creator can clean its known stage. Post-crash recovery never
    /// recursively deletes a path solely because the journal mentions it.
    private func cleanStages(removeContents: Bool) {
        managedStages.removeAll { stage in
            guard FileNames.exists(stage.url) else { return true }
            guard stage.identity.matchesIdentity(stage.url), DirectoryMergeGuard.isPlainDirectory(stage.url) else { return false }
            guard removeContents || (try? FileManager.default.contentsOfDirectory(atPath: stage.url.path).isEmpty) == true else { return false }
            do { try FileManager.default.removeItem(at: stage.url); return true } catch { return false }
        }
    }
    @discardableResult func rollbackJournal(into result: inout FileJobResult) -> Bool {
        guard let activeJournal else { return true }
        do {
            let recovery = try activeJournal.rollbackToCheckpoint()
            if let data = recovery.receipt, let checkpoint = try? JSONDecoder().decode(OperationCheckpoint.self, from: data) { result.receipt = checkpoint.receipt }
            else { result.receipt.steps = [] }
            guard recovery.resolved else { result.errors += recovery.notices; return false }
            cleanStages(removeContents: true)
            for stage in managedStages { result.errors.append("Private staging retained: " + stage.url.path) }
            return true
        } catch { result.errors.append("Recovery requires review: " + error.localizedDescription); return false }
    }
    func finishJournal(_ result: inout FileJobResult) {
        guard let activeJournal else { return }
        defer { self.activeJournal = nil; managedStages = [] }
        let resolved = rollbackJournal(into: &result)
        do { try activeJournal.finish(receipt: nil, needsReview: !resolved, warning: result.errors.isEmpty ? nil : result.errors.joined(separator: "\n")) }
        catch { result.errors.append("Could not finalize recovery state: " + error.localizedDescription) }
    }
    public func interruptedOperations() throws -> [InterruptedFileOperation] {
        try openJournal().summaries().filter { $0.id != activeJournal?.id }.map {
            InterruptedFileOperation(id: $0.id, title: $0.title, started: $0.started, state: $0.state, warning: $0.warning, pendingMutations: $0.pendingMutations)
        }
    }
    public func recoverInterrupted(_ id: UUID) async throws -> FileRecoveryReport {
        await acquire(); defer { release() }
        let report = try openJournal().recover(id)
        let receipt = report.receipt.flatMap { try? JSONDecoder().decode(OperationCheckpoint.self, from: $0).receipt }
        return FileRecoveryReport(resolved: report.resolved, notices: report.notices, retainedArtifacts: report.retainedArtifacts, receipt: receipt)
    }
    public func acknowledgeInterrupted(_ id: UUID) async throws {
        await acquire(); defer { release() }; try openJournal().acknowledge(id)
    }
    public func history() -> [OperationReceipt] {
        var receipts: [UUID: OperationReceipt] = [:]
        let urls = (try? FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let receipt = try? JSONDecoder().decode(OperationReceipt.self, from: data) { receipts[receipt.id] = receipt }
        }
        let records = (try? openJournal().receipts(limit: 10_000)) ?? []
        for checkpoint in records.compactMap({ try? JSONDecoder().decode(OperationCheckpoint.self, from: $0) }) {
            if let id = checkpoint.replacing { receipts.removeValue(forKey: id) }
            if !checkpoint.receipt.steps.isEmpty { receipts[checkpoint.receipt.id] = checkpoint.receipt }
            if let remaining = checkpoint.remaining, !remaining.steps.isEmpty { receipts[remaining.id] = remaining }
        }
        return receipts.values.sorted { $0.date > $1.date }
    }
}
