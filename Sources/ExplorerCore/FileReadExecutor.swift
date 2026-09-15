import Foundation

/// Cooperative cancellation for blocking read work running outside Swift's
/// cooperative executor. It cannot interrupt a kernel filesystem call; it can
/// release the awaiting task immediately and suppress every obsolete result.
public final class FileReadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func check() throws { if isCancelled { throw CancellationError() } }
}

/// Fixed-width, shared lanes. A long recursive scan/hash cannot sit in front of
/// foreground folder listing. Cancelled queued work performs no filesystem I/O.
/// Only use this executor for reads/derived data, never partially committed writes.
public final class FileReadExecutor: @unchecked Sendable {
    public static let browsing = FileReadExecutor(name: "browsing", concurrency: 2, quality: .userInitiated)
    public static let metadata = FileReadExecutor(name: "metadata", concurrency: 2, quality: .utility)
    public static let bulk = FileReadExecutor(name: "bulk", concurrency: 1, quality: .utility)
    public static let presentation = FileReadExecutor(name: "presentation", concurrency: 1, quality: .userInitiated)
    private let queue: OperationQueue
    public init(name: String, concurrency: Int, quality: QualityOfService = .utility) {
        queue = OperationQueue(); queue.name = "MacExplorer.read." + name
        queue.maxConcurrentOperationCount = max(1, min(8, concurrency)); queue.qualityOfService = quality
    }
    /// Diagnostic snapshot including queued and executing reads.
    var outstandingReadCount: Int { queue.operationCount }
    public func run<T: Sendable>(_ work: @escaping @Sendable (FileReadCancellation) throws -> T) async throws -> T {
        try Task.checkCancellation()
        let job = ReadOperation<T>(work: work)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard job.install(continuation) else { return }
                queue.addOperation(job)
            }
        } onCancel: { job.cancel() }
    }
}
/// An enqueued operation owns its read closure only until it starts or is
/// cancelled. Cancelling a caller must not retain an obsolete large listing
/// behind a stalled filesystem call. Running calls remain cooperative.
private final class ReadOperation<T: Sendable>: Operation, @unchecked Sendable {
    typealias Work = @Sendable (FileReadCancellation) throws -> T
    private var work: Work?
    init(work: @escaping Work) { self.work = work; super.init() }
    let cancellation = FileReadCancellation()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var completed = false
    func install(_ continuation: CheckedContinuation<T, Error>) -> Bool {
        lock.lock()
        if completed { lock.unlock(); continuation.resume(throwing: CancellationError()); return false }
        self.continuation = continuation; lock.unlock(); return true
    }
    override func main() {
        lock.lock()
        let read = completed ? nil : work
        work = nil
        lock.unlock()
        guard let read else { return }
        complete(Result {
            try cancellation.check()
            let value = try read(cancellation)
            try cancellation.check()
            return value
        })
    }
    override func cancel() {
        cancellation.cancel()
        super.cancel()
        complete(.failure(CancellationError()))
    }
    func complete(_ result: Result<T, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true; let callback = continuation; continuation = nil
        // Captured objects may have reentrant destructors. Release the closure
        // after unlocking, just like resuming the continuation.
        let discardedWork = work; work = nil
        lock.unlock()
        withExtendedLifetime(discardedWork) {}
        callback?.resume(with: result)
    }
}
