import Foundation

public enum DetailsColumn: String, CaseIterable, Codable, Identifiable, Sendable {
    case name, modified, kind, size, tags, availability
    public var id: String { rawValue }
    public var title: String {
        switch self { case .name: return "Name"; case .modified: return "Date modified"; case .kind: return "Kind"; case .size: return "Size"; case .tags: return "Tags"; case .availability: return "Availability" }
    }
    public var minimum: Double {
        switch self { case .name: return 160; case .modified: return 118; case .kind: return 88; case .size: return 64; case .tags: return 110; case .availability: return 112 }
    }
    public var weight: Double {
        switch self { case .name: return 0.48; case .modified: return 0.25; case .kind: return 0.17; case .size: return 0.10; case .tags, .availability: return 0.18 }
    }
    public var sort: SortField? {
        switch self { case .name: return .name; case .modified: return .modified; case .kind: return .kind; case .size: return .size; default: return nil }
    }
}

public struct DetailsColumns: Codable, Equatable, Sendable {
    public var order: [DetailsColumn] = DetailsColumn.allCases
    public var hidden: Set<DetailsColumn> = [.tags, .availability]
    public var overrides: [String: Double] = [:]
    public init() {}
    public var visible: [DetailsColumn] { normalizedOrder.filter { $0 == .name || !hidden.contains($0) } }
    private var normalizedOrder: [DetailsColumn] {
        var seen = Set<DetailsColumn>()
        return (order + DetailsColumn.allCases).filter { seen.insert($0).inserted }
    }
    public mutating func move(_ column: DetailsColumn, before target: DetailsColumn) {
        guard column != target else { return }
        order = normalizedOrder.filter { $0 != column }
        order.insert(column, at: order.firstIndex(of: target) ?? order.count)
    }
    public mutating func setWidth(_ value: Double, for column: DetailsColumn) {
        guard value.isFinite else { return }
        overrides[column.rawValue] = min(1600, max(column.minimum, value))
    }
    /// Weighted water filling keeps all four default columns visible whenever
    /// their minimum widths fit. Explicit user widths may require scrolling.
    public func widths(available: Double) -> [Double] {
        let columns = visible
        var result = [DetailsColumn: Double](), flexible = columns
        var remaining = available.isFinite ? max(0, available) : 0
        for column in columns {
            if let value = overrides[column.rawValue], value.isFinite {
                let size = min(1600, max(column.minimum, value))
                result[column] = size; remaining -= size; flexible.removeAll { $0 == column }
            }
        }
        while !flexible.isEmpty {
            let weight = flexible.reduce(0) { $0 + $1.weight }
            let pinned = flexible.filter { remaining * $0.weight / weight < $0.minimum }
            if pinned.isEmpty {
                for column in flexible { result[column] = max(column.minimum, remaining * column.weight / weight) }
                break
            }
            for column in pinned { result[column] = column.minimum; remaining -= column.minimum }
            flexible.removeAll { pinned.contains($0) }
        }
        return columns.map { result[$0] ?? $0.minimum }
    }
}
