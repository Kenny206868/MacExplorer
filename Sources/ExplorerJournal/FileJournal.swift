import Foundation

public enum JournalFaultPoint: String, CaseIterable, Sendable {
    case intentCommitted, filesystemApplied, appliedCommitted, checkpointCommitted
    case rollbackIntentCommitted, rollbackApplied, rollbackCommitted
}
public struct JournalSummary: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let started: Date
    public let state: String
    public let warning: String?
    public let pendingMutations: Int
    public let receipt: Data?
}
public struct JournalRecoveryResult: Sendable {
    public let receipt: Data?
    public let retainedArtifacts: [URL]
    public let notices: [String]
    public let resolved: Bool
}
private struct ArtifactIntent: Codable {
    let path: URL
    let parent: JournalIdentity
    let identity: JournalIdentity?
}
private struct ExternalIntent: Codable {
    let source: URL
    let identity: JournalIdentity
    let parent: JournalIdentity
}
private struct ExternalOutcome: Codable {
    let destination: URL?
    let identity: JournalIdentity?
    let parent: JournalIdentity?
}
/// SQLite WAL + FULL sync protects intent records. Recovery compensates only
/// unfinished mutations after the last durable receipt checkpoint.
public final class FileJournal: @unchecked Sendable {
    let database: JournalDatabase
    private let stateLock = NSRecursiveLock()
    private var active = Set<UUID>()
    let fault: (@Sendable (JournalFaultPoint) -> Void)?
    public init(directory: URL, fault: (@Sendable (JournalFaultPoint) -> Void)? = nil) throws {
        database = try JournalDatabase(directory: directory); self.fault = fault
    }
    public func begin(title: String, id: UUID = UUID()) throws -> JournalTransaction {
        stateLock.lock(); defer { stateLock.unlock() }
        try database.execute("INSERT INTO operations(id,title,started,state) VALUES(?,?,?,'running')", [
            .text(id.uuidString), .text(String(title.prefix(512))), .real(Date().timeIntervalSince1970)])
        active.insert(id); return JournalTransaction(journal: self, id: id)
    }
    func released(_ id: UUID) { stateLock.lock(); active.remove(id); stateLock.unlock() }
    public func summaries(unfinishedOnly: Bool = true, limit: Int = 100) throws -> [JournalSummary] {
        stateLock.lock(); defer { stateLock.unlock() }
        let predicate = unfinishedOnly ? "WHERE state NOT IN ('finished','recovered')" : ""
        let rows = try database.query("SELECT id,title,started,state,warning,receipt,(SELECT count(*) FROM mutations m WHERE m.operation=operations.id AND m.id>operations.checkpoint AND m.phase NOT IN ('reverted','aborted','reviewed')) FROM operations \(predicate) ORDER BY started DESC LIMIT ?", [.integer(Int64(max(1, min(limit, 1000))))])
        return try rows.map { row in
            guard row.count == 7, let id = row[0].string.flatMap(UUID.init(uuidString:)), let title = row[1].string,
                  case .real(let time) = row[2], let state = row[3].string else { throw JournalError.database("Invalid operation record.") }
            return JournalSummary(id: id, title: title, started: Date(timeIntervalSince1970: time), state: state,
                warning: row[4].string, pendingMutations: Int(row[6].integer ?? 0), receipt: row[5].data)
        }
    }
    public func receipts(limit: Int = 1000) throws -> [Data] {
        try database.query("SELECT receipt FROM operations WHERE receipt IS NOT NULL ORDER BY started DESC LIMIT ?", [.integer(Int64(max(1, min(limit, 10_000))))]).compactMap { $0.first?.data }
    }
    public func recover(_ id: UUID) throws -> JournalRecoveryResult {
        stateLock.lock(); defer { stateLock.unlock() }
        guard !active.contains(id) else { throw JournalError.conflict("This operation is still active.") }
        let header = try database.query("SELECT state,receipt,checkpoint FROM operations WHERE id=?", [.text(id.uuidString)]).first
        guard let header, let state = header[0].string else { throw JournalError.database("Recovery operation was not found.") }
        if state == "finished" || state == "recovered" { return JournalRecoveryResult(receipt: header[1].data, retainedArtifacts: [], notices: [], resolved: true) }
        let rows = try database.query("SELECT id,kind,phase,payload,outcome FROM mutations WHERE operation=? AND id>? ORDER BY id DESC", [.text(id.uuidString), .integer(header[2].integer ?? 0)])
        var artifacts: [URL] = [], notices: [String] = []
        for row in rows {
            guard let mutation = row[0].integer, let kind = row[1].string, let phase = row[2].string, let payload = row[3].data else { throw JournalError.database("Invalid mutation record.") }
            if ["reverted", "aborted", "reviewed"].contains(phase) { continue }
            do {
                switch kind {
                case "move": try recoverMove(JSONDecoder().decode(JournalMove.self, from: payload), mutation: mutation)
                case "artifact":
                    let item = try JSONDecoder().decode(ArtifactIntent.self, from: payload)
                    if FileManager.default.fileExists(atPath: item.path.path) || (try? JournalIdentity(item.path)) != nil {
                        artifacts.append(item.path); notices.append("Private staging retained for inspection: " + item.path.path)
                    }
                    try setPhase(mutation, "reviewed")
                case "trash", "delete":
                    let intent = try JSONDecoder().decode(ExternalIntent.self, from: payload)
                    if let data = row[4].data {
                        let outcome = try JSONDecoder().decode(ExternalOutcome.self, from: data)
                        if kind == "trash", let destination = outcome.destination, let identity = outcome.identity,
                           identity.matches(destination), !FileManager.default.fileExists(atPath: intent.source.path) {
                            guard intent.parent.matches(intent.source.deletingLastPathComponent(), exact: false) else { throw JournalError.conflict("Original Trash parent changed.") }
                            let inverse = try JournalMove(source: destination, destination: intent.source)
                            try setPhase(mutation, "rollbackPrepared"); fault?(.rollbackIntentCommitted)
                            try journalRename(inverse, reverse: false); fault?(.rollbackApplied)
                            try setPhase(mutation, "reverted"); fault?(.rollbackCommitted)
                        } else if kind == "delete" {
                            notices.append("Permanent deletion was recorded and cannot be undone: " + intent.source.path)
                            try setPhase(mutation, "reviewed")
                        } else if intent.identity.matches(intent.source) { try setPhase(mutation, "reverted") }
                        else { throw JournalError.conflict("The native Trash result changed; inspect it before recovery.") }
                    } else if intent.identity.matches(intent.source) {
                        notices.append("An interrupted \(kind) request still has its original source; it was not repeated.")
                        try setPhase(mutation, "aborted")
                    } else {
                        throw JournalError.conflict("An interrupted \(kind) has an unrecorded OS outcome: \(intent.source.path). Review Trash/source contents manually.")
                    }
                default: throw JournalError.database("Unknown mutation kind; journal retained.")
                }
            } catch {
                notices.append(error.localizedDescription)
                try database.execute("UPDATE operations SET state='needsReview',warning=? WHERE id=?", [.text(error.localizedDescription), .text(id.uuidString)])
                return JournalRecoveryResult(receipt: header[1].data, retainedArtifacts: artifacts, notices: notices, resolved: false)
            }
        }
        try database.execute("UPDATE operations SET state='recovered',warning=? WHERE id=?", [.text(notices.joined(separator: "\n")), .text(id.uuidString)])
        return JournalRecoveryResult(receipt: header[1].data, retainedArtifacts: artifacts, notices: notices, resolved: true)
    }
    private func recoverMove(_ move: JournalMove, mutation: Int64) throws {
        if move.matches(move.source), (try? JournalIdentity(move.destination)) == nil {
            try setPhase(mutation, "reverted"); return
        }
        guard (try? JournalIdentity(move.source)) == nil, move.matches(move.destination) else {
            throw JournalError.conflict("The original path is occupied or the moved object changed: \(move.source.path)")
        }
        try setPhase(mutation, "rollbackPrepared"); fault?(.rollbackIntentCommitted)
        try journalRename(move, reverse: true); fault?(.rollbackApplied)
        try setPhase(mutation, "reverted"); fault?(.rollbackCommitted)
    }
    func setPhase(_ mutation: Int64, _ phase: String) throws { try database.execute("UPDATE mutations SET phase=? WHERE id=?", [.text(phase), .integer(mutation)]) }
}
public final class JournalTransaction: @unchecked Sendable {
    public let id: UUID
    private let journal: FileJournal
    private let lock = NSRecursiveLock()
    private var finished = false
    fileprivate init(journal: FileJournal, id: UUID) { self.journal = journal; self.id = id }
    deinit { journal.released(id) }
    public func move(_ source: URL, to destination: URL, emptyDirectory: Bool = false) throws {
        lock.lock(); defer { lock.unlock() }
        let intent = try JournalMove(source: source, destination: destination, emptyDirectory: emptyDirectory)
        guard (try? JournalIdentity(intent.destination)) == nil else { throw JournalError.conflict("Destination already exists: " + destination.path) }
        let mutation = try prepare("move", payload: JSONEncoder().encode(intent))
        journal.fault?(.intentCommitted)
        try journalRename(intent, reverse: false); journal.fault?(.filesystemApplied)
        try journal.setPhase(mutation, "applied"); journal.fault?(.appliedCommitted)
    }
    /// Log private staging before creation. Recovery never recursively removes
    /// an arbitrary path merely because that path appears in the database.
    public func registerArtifact(_ path: URL) throws {
        lock.lock(); defer { lock.unlock() }
        try JournalIdentity.validatePath(path)
        guard path.lastPathComponent.hasPrefix(".MacExplorer-") else { throw JournalError.unsafe("Staging must use an application-private name.") }
        let parent = try JournalIdentity(path.deletingLastPathComponent())
        guard parent.isDirectory, (try? JournalIdentity(path)) == nil else { throw JournalError.unsafe("Staging destination must be absent.") }
        _ = try prepare("artifact", payload: JSONEncoder().encode(ArtifactIntent(path: path, parent: parent, identity: nil)))
    }
    /// Native Trash and irreversible deletion do not transact with SQLite.
    /// Unknown crash outcomes remain explicit review items, never guessed/replayed.
    public func external(_ kind: String, source: URL, operation: () throws -> URL?) throws -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard kind == "trash" || kind == "delete" else { throw JournalError.unsafe("Unknown external operation.") }
        let intent = ExternalIntent(source: source, identity: try JournalIdentity(source), parent: try JournalIdentity(source.deletingLastPathComponent()))
        let mutation = try prepare(kind, payload: JSONEncoder().encode(intent))
        journal.fault?(.intentCommitted)
        let output = try operation(); journal.fault?(.filesystemApplied)
        let outcome = ExternalOutcome(destination: output, identity: try output.map(JournalIdentity.init), parent: try output.map { try JournalIdentity($0.deletingLastPathComponent()) })
        try journal.database.execute("UPDATE mutations SET phase='applied',outcome=? WHERE id=?", [.blob(try JSONEncoder().encode(outcome)), .integer(mutation)])
        journal.fault?(.appliedCommitted); return output
    }
    public func checkpoint(receipt: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { throw JournalError.unsafe("Transaction already finished.") }
        try journal.database.execute("UPDATE operations SET receipt=?,checkpoint=coalesce((SELECT max(id) FROM mutations WHERE operation=?),0) WHERE id=?", [.blob(receipt), .text(id.uuidString), .text(id.uuidString)])
        journal.fault?(.checkpointCommitted)
    }
    public func finish(receipt: Data?, needsReview: Bool = false, warning: String? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        if !needsReview, let receipt {
            try journal.database.execute("UPDATE operations SET state='finished',warning=?,receipt=?,checkpoint=coalesce((SELECT max(id) FROM mutations WHERE operation=?),0) WHERE id=?", [warning.map(SQLValue.text) ?? .null, .blob(receipt), .text(id.uuidString), .text(id.uuidString)])
        } else {
            try journal.database.execute("UPDATE operations SET state=?,warning=? WHERE id=?", [.text(needsReview ? "needsReview" : "finished"), warning.map(SQLValue.text) ?? .null, .text(id.uuidString)])
        }
        finished = true; journal.released(id)
    }
    private func prepare(_ kind: String, payload: Data) throws -> Int64 {
        guard !finished else { throw JournalError.unsafe("Transaction already finished.") }
        return try journal.database.execute("INSERT INTO mutations(operation,kind,phase,payload) VALUES(?,?,'prepared',?)", [.text(id.uuidString), .text(kind), .blob(payload)])
    }
}
