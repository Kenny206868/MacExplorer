import Foundation

/// Logical sizes from an existing listing, never recursive folder sizes or
/// physical allocation. Saturating arithmetic makes large selections safe.
public struct SelectionStatistics: Equatable, Sendable {
    public private(set) var files = 0
    public private(set) var folders = 0
    public private(set) var bytes: Int64 = 0
    public private(set) var overflowed = false
    public var count: Int { files + folders }
    public init() {}
    public mutating func include(isDirectory: Bool, byteCount: Int64) {
        if isDirectory { folders += 1; return }
        files += 1
        let result = bytes.addingReportingOverflow(max(0, byteCount))
        bytes = result.overflow ? .max : result.partialValue
        overflowed = overflowed || result.overflow
    }
}
