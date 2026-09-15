import Foundation
import ExplorerCore

/// Bounded filesystem reads with per-caller cancellation, shared in-flight
/// requests and short-lived caching. Two panes at one location issue one read.
/// Cancelling the last observer removes queued work from the metadata lane.
actor StatusVolumeService {
    static let shared = StatusVolumeService()
    typealias Reader = @Sendable (URL, FileReadCancellation) throws -> StatusVolume?
    private struct Key: Hashable { let url: URL; let revision: Int }
    private struct Cached { let value: StatusVolume?; let time: TimeInterval }
    private struct Pending {
        let id: UUID
        var waiters: [UUID: CheckedContinuation<StatusVolume?, Error>]
        let task: Task<Void, Never>
    }
    var inFlightObservers: Int { pending.values.reduce(0) { $0 + $1.waiters.count } }
    var cachedLocations: Int { cache.count }
    private let executor: FileReadExecutor
    private let reader: Reader
    private let lifetime: TimeInterval
    private var cache: [Key: Cached] = [:]
    private var pending: [Key: Pending] = [:]
    init(executor: FileReadExecutor = FileReadExecutor(name: "status-volume", concurrency: 1),
         lifetime: TimeInterval = 10, reader: @escaping Reader = { url, cancellation in
             try cancellation.check(); let value = StatusVolume.read(url); try cancellation.check(); return value
         }) {
        self.executor = executor; self.reader = reader; self.lifetime = max(0, lifetime)
    }
    func read(_ url: URL, revision: Int = 0) async throws -> StatusVolume? {
        try Task.checkCancellation()
        let key = Key(url: url.standardizedFileURL, revision: revision)
        if let cached = cache[key], ProcessInfo.processInfo.systemUptime - cached.time < lifetime { return cached.value }
        let waiter = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if pending[key] != nil { pending[key]?.waiters[waiter] = continuation; return }
                let id = UUID()
                let task = Task { [reader, executor] in
                    let result: Result<StatusVolume?, Error>
                    do { result = .success(try await executor.run { try reader(key.url, $0) }) }
                    catch { result = .failure(error) }
                    complete(key, id: id, result: result)
                }
                pending[key] = Pending(id: id, waiters: [waiter: continuation], task: task)
            }
        } onCancel: { Task { await self.cancel(key, waiter: waiter) } }
    }
    private func cancel(_ key: Key, waiter: UUID) {
        guard let continuation = pending[key]?.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if pending[key]?.waiters.isEmpty == true { pending.removeValue(forKey: key)?.task.cancel() }
    }
    private func complete(_ key: Key, id: UUID, result: Result<StatusVolume?, Error>) {
        guard pending[key]?.id == id, let completed = pending.removeValue(forKey: key) else { return }
        if case .success(let value) = result {
            cache[key] = Cached(value: value, time: ProcessInfo.processInfo.systemUptime)
            if cache.count > 32, let oldest = cache.min(by: { $0.value.time < $1.value.time })?.key { cache.removeValue(forKey: oldest) }
        }
        for continuation in completed.waiters.values { continuation.resume(with: result) }
    }
}
