import Foundation

/// Bounded, clock-independent telemetry. Call with monotonic time and cumulative
/// data bytes. Logical clone completion is intentionally not a throughput sample.
public struct TransferStatistics: Sendable {
    public struct Sample: Sendable {
        public let time: TimeInterval
        public let bytesPerSecond: Double
    }
    public private(set) var samples: [Sample] = []
    public private(set) var bytesPerSecond: Double?
    public private(set) var bytes: Int64 = 0
    private var lastTime: TimeInterval?
    private var lastBytes: Int64 = 0
    public init() {}
    public mutating func record(bytes value: Int64, at time: TimeInterval, paused: Bool = false) {
        guard time.isFinite else { return }
        let value = max(0, value)
        if let lastTime, time < lastTime { return }
        bytes = max(bytes, value)
        guard !paused else { suspend(); lastBytes = value; return }
        guard let previous = lastTime else { lastTime = time; lastBytes = value; return }
        let interval = time - previous
        guard interval >= 0.1 else { return }
        guard value >= lastBytes else { lastTime = time; lastBytes = value; bytesPerSecond = nil; return }
        let instantaneous = Double(value - lastBytes) / interval
        let weight = 1 - exp(-interval / 2)
        let rate = bytesPerSecond.map { $0 + weight * (instantaneous - $0) } ?? instantaneous
        bytesPerSecond = max(0, rate)
        samples.append(Sample(time: time, bytesPerSecond: max(0, rate)))
        if samples.count > 120 { samples.removeFirst(samples.count - 120) }
        lastTime = time; lastBytes = value
    }
    public mutating func suspend() { lastTime = nil; bytesPerSecond = nil }
    public func secondsRemaining(totalBytes: Int64?, completedBytes: Int64) -> TimeInterval? {
        guard let totalBytes, totalBytes >= 0, let rate = bytesPerSecond, rate > 1 else { return nil }
        return Double(max(0, totalBytes - max(0, completedBytes))) / rate
    }
}

public enum TransferInventory {
    /// An estimate, not a filesystem snapshot. Fails explicitly on incomplete
    /// traversal; callers may continue a transfer with an indeterminate total.
    public static func logicalBytes(_ source: URL, control: OperationControl) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        try control.checkpoint()
        let root = try source.resourceValues(forKeys: keys)
        if root.isSymbolicLink == true { return 0 }
        if root.isRegularFile == true { return Int64(max(0, root.fileSize ?? 0)) }
        guard root.isDirectory == true else { return 0 }
        var traversalError: Error?
        guard let iterator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, error in
            traversalError = error; return false
        }) else { throw ExplorerError.message("Cannot enumerate \(source.path).") }
        var total: Int64 = 0
        for case let url as URL in iterator {
            try control.checkpoint()
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if values.isRegularFile == true {
                let (sum, overflow) = total.addingReportingOverflow(Int64(max(0, values.fileSize ?? 0)))
                guard !overflow else { throw ExplorerError.message("The selected logical size exceeds the supported byte counter.") }
                total = sum
            }
        }
        if let traversalError { throw traversalError }
        return total
    }
}
