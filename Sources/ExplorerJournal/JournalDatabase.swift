import Foundation
import CJournal

public enum JournalError: Error, LocalizedError {
    case database(String), unsafe(String), conflict(String), io(String, Int32)
    public var errorDescription: String? {
        switch self {
        case .database(let message): return "Recovery database: " + message
        case .unsafe(let message): return "Recovery safety check: " + message
        case .conflict(let message): return "Recovery stopped: " + message
        case .io(let operation, let code): return "\(operation): \(String(cString: strerror(code))) (\(code))"
        }
    }
}
enum SQLValue {
    case text(String), integer(Int64), real(Double), blob(Data), null
    var string: String? { if case .text(let s) = self { return s }; return nil }
    var integer: Int64? { if case .integer(let n) = self { return n }; return nil }
    var data: Data? { if case .blob(let d) = self { return d }; return nil }
}
/// All data uses bound parameters. SQLite supplies crash-consistent WAL framing,
/// checksums, recovery and synchronous commit ordering rather than custom logs.
final class JournalDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var processLock: Int32 = -1
    let directory: URL
    init(directory: URL) throws {
        guard directory.isFileURL else { throw JournalError.unsafe("The journal must be on a local filesystem.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let identity = try JournalIdentity(directory)
        guard identity.isDirectory, identity.owner == me_current_uid(), identity.mode & 0o077 == 0 else {
            throw JournalError.unsafe("The journal directory must be owned by this user with mode 0700.")
        }
        // SQLite NOFOLLOW rejects all symbolic path components, including the
        // macOS /var alias. Validate the leaf, then resolve the parent spelling.
        let canonical = directory.resolvingSymlinksInPath().standardizedFileURL
        guard identity.matches(canonical, exact: false) else {
            throw JournalError.unsafe("The journal directory changed while resolving its path.")
        }
        self.directory = canonical
        processLock = me_open_journal_lock(canonical.appendingPathComponent("writer.lock").path)
        guard processLock >= 0 else { throw JournalError.io("Acquire exclusive recovery writer lock", errno) }
        let database = canonical.appendingPathComponent("operations.sqlite3")
        for suffix in ["", "-wal", "-shm"] {
            let path = URL(fileURLWithPath: database.path + suffix)
            if let item = try? JournalIdentity(path) {
                guard item.isRegularFile, item.owner == me_current_uid() else {
                    closeResources(); throw JournalError.unsafe("A database path is not an owned regular file.")
                }
            }
        }
        let status = sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        guard status == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            closeResources(); throw JournalError.database(message)
        }
        do {
            sqlite3_busy_timeout(handle, 5000)
            _ = try query("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL"); try execute("PRAGMA fullfsync=ON")
            try execute("PRAGMA checkpoint_fullfsync=ON"); try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA trusted_schema=OFF"); _ = try query("PRAGMA wal_autocheckpoint=1000")
            guard try query("PRAGMA journal_mode").first?.first?.string == "wal",
                  try query("PRAGMA synchronous").first?.first?.integer == 2,
                  try query("PRAGMA fullfsync").first?.first?.integer == 1 else {
                throw JournalError.database("Required durability settings were not accepted.")
            }
            let version = try query("PRAGMA user_version").first?.first?.integer ?? -1
            guard version == 0 || version == 1 else { throw JournalError.database("Unknown schema version; original database retained.") }
            try transaction {
                try execute("CREATE TABLE IF NOT EXISTS operations(id TEXT PRIMARY KEY, title TEXT NOT NULL, started REAL NOT NULL, state TEXT NOT NULL, checkpoint INTEGER NOT NULL DEFAULT 0, receipt BLOB, warning TEXT)")
                try execute("CREATE TABLE IF NOT EXISTS mutations(id INTEGER PRIMARY KEY AUTOINCREMENT, operation TEXT NOT NULL REFERENCES operations(id), kind TEXT NOT NULL, phase TEXT NOT NULL, payload BLOB NOT NULL, outcome BLOB)")
                try execute("CREATE INDEX IF NOT EXISTS mutations_operation ON mutations(operation,id)")
                try execute("PRAGMA user_version=1")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.path)
        } catch { closeResources(); throw error }
    }
    deinit { closeResources() }
    private func closeResources() {
        if let handle { sqlite3_close_v2(handle); self.handle = nil }
        if processLock >= 0 { me_close(processLock); processLock = -1 }
    }
    @discardableResult func execute(_ sql: String, _ arguments: [SQLValue] = []) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(sql, arguments); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
        return sqlite3_last_insert_rowid(handle)
    }
    func query(_ sql: String, _ arguments: [SQLValue] = [], limit: Int = 500_000) throws -> [[SQLValue]] {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(sql, arguments); defer { sqlite3_finalize(statement) }
        var rows: [[SQLValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw failure() }
            guard rows.count < limit else { throw JournalError.database("Recovery result exceeded its safety limit; no rows were silently discarded.") }
            var row: [SQLValue] = []
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row.append(.integer(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(statement, column)))
                case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(statement, column))))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    guard count <= 64 * 1024 * 1024 else { throw JournalError.database("Oversized recovery payload.") }
                    row.append(.blob(count == 0 ? Data() : Data(bytes: sqlite3_column_blob(statement, column)!, count: count)))
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
    }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do { let value = try body(); try execute("COMMIT"); return value }
        catch { _ = try? execute("ROLLBACK"); throw error }
    }
    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        do {
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1), result: Int32
                switch value {
                case .text(let text): result = text.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
                case .integer(let n): result = sqlite3_bind_int64(statement, index, n)
                case .real(let n): result = sqlite3_bind_double(statement, index, n)
                case .blob(let data):
                    guard data.count <= 64 * 1024 * 1024 else { throw JournalError.database("Recovery payload exceeds 64 MiB.") }
                    result = data.isEmpty ? sqlite3_bind_zeroblob(statement, index, 0) : data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
                case .null: result = sqlite3_bind_null(statement, index)
                }
                guard result == SQLITE_OK else { throw failure() }
            }
            return statement
        } catch { sqlite3_finalize(statement); throw error }
    }
    private func failure() -> JournalError { .database(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Database closed") }
}
