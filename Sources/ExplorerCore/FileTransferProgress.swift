import Foundation

public enum FileOperationPhase: String, Sendable {
    case calculating = "Calculating size"
    case copying = "Copying"
    case processing = "Working"
    case waiting = "Waiting for a decision"
    case finished = "Finished"
    case cancelled = "Cancelled"
}

public struct FileProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let name: String
    public let bytes: Int64
    public let logicalBytes: Int64
    public let totalBytes: Int64?
    public let clonedFiles: Int
    public let phase: FileOperationPhase
    public let sequence: UInt64
    public let timestamp: TimeInterval
    public init(completed: Int, total: Int, name: String, bytes: Int64 = 0,
                logicalBytes: Int64 = 0, totalBytes: Int64? = nil, clonedFiles: Int = 0,
                phase: FileOperationPhase = .processing, sequence: UInt64 = 0) {
        self.completed = completed; self.total = total; self.name = name; self.bytes = bytes
        self.logicalBytes = logicalBytes; self.totalBytes = totalBytes; self.clonedFiles = clonedFiles
        self.phase = phase; self.sequence = sequence; timestamp = ProcessInfo.processInfo.systemUptime
    }
}

/// A single stream across all source roots, with monotonic delivery sequence IDs.
/// The observer runs outside the lock. Consumers reject stale queued UI updates.
final class TransferProgressReporter: @unchecked Sendable {
    private struct State {
        var completed = 0
        var name = "Preparing"
        var phase = FileOperationPhase.processing
        var bytes: Int64 = 0, logical: Int64 = 0, baseBytes: Int64 = 0, baseLogical: Int64 = 0
        var clones = 0, baseClones = 0
        var totalBytes: Int64?
        var sequence: UInt64 = 0
    }
    private let lock = NSLock()
    private var state = State()
    private let total: Int
    private let observer: @Sendable (FileProgress) -> Void
    init(total: Int, observer: @escaping @Sendable (FileProgress) -> Void) { self.total = total; self.observer = observer }
    @discardableResult private func update(_ mutation: (inout State) -> Void) -> FileProgress {
        lock.lock(); mutation(&state); state.sequence &+= 1
        let value = FileProgress(completed: state.completed, total: total, name: state.name, bytes: state.bytes,
                                 logicalBytes: state.logical, totalBytes: state.totalBytes, clonedFiles: state.clones,
                                 phase: state.phase, sequence: state.sequence)
        lock.unlock(); observer(value); return value
    }
    func phase(_ phase: FileOperationPhase, name: String) { update { $0.phase = phase; $0.name = name } }
    func estimate(_ bytes: Int64?) { update { $0.totalBytes = bytes } }
    func begin(name: String, copying: Bool) {
        update { $0.baseBytes = $0.bytes; $0.baseLogical = $0.logical; $0.baseClones = $0.clones; $0.name = name; $0.phase = copying ? .copying : .processing }
    }
    func copy(_ value: NativeCopyProgress) {
        update {
            $0.bytes = Self.add($0.baseBytes, value.writtenBytes)
            $0.logical = Self.add($0.baseLogical, value.logicalBytes)
            $0.clones = $0.baseClones + value.clonedFiles
            $0.name = URL(fileURLWithPath: value.path).lastPathComponent
            $0.phase = .copying
        }
    }
    /// Commit a merge child without incrementing the completed top-level count.
    func commitChild() {
        update { $0.baseBytes = $0.bytes; $0.baseLogical = $0.logical; $0.baseClones = $0.clones }
    }
    func end(success: Bool) {
        update {
            if success { $0.completed += 1 }
            else { $0.logical = $0.baseLogical; $0.clones = $0.baseClones }
        }
    }
    func finish(cancelled: Bool) -> FileProgress {
        update { $0.phase = cancelled ? .cancelled : .finished; $0.name = cancelled ? "Cancelled" : "Finished" }
    }
    private static func add(_ first: Int64, _ second: Int64) -> Int64 {
        let (value, overflow) = first.addingReportingOverflow(max(0, second)); return overflow ? .max : value
    }
}
