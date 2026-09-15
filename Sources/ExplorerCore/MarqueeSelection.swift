import Foundation

public enum MarqueeSelectionMode: Sendable { case replace, add, toggle }

/// A drag owns one immutable identity order and baseline. Geometry contributes
/// compressed index ranges; unchanged ranges produce no selection publication.
/// The order must contain unique identities. Do not reuse a session after the
/// listing or its presentation order changes.
public struct MarqueeSelection<ID: Hashable> {
    private let order: [ID]
    private let baseline: Set<ID>
    private let mode: MarqueeSelectionMode
    private var previous: IndexSet?
    private var result: Set<ID>
    public private(set) var projectionUpdates = 0

    public init(order: [ID], baseline: Set<ID>, mode: MarqueeSelectionMode) {
        self.order = order; self.baseline = baseline; self.mode = mode
        result = mode == .replace ? [] : baseline
    }

    /// nil means the set of hit rows/cells has not changed. Invalid indices are
    /// discarded before indexing. Callers retain their last published selection.
    public mutating func update(hits: IndexSet) -> Set<ID>? {
        let hits = hits.intersection(IndexSet(integersIn: 0..<order.count))
        guard previous != hits else { return nil }
        let removed = previous?.subtracting(hits) ?? IndexSet()
        let added = previous.map { hits.subtracting($0) } ?? hits
        for index in removed {
            let id = order[index]
            if mode != .replace && baseline.contains(id) { result.insert(id) }
            else { result.remove(id) }
        }
        for index in added {
            let id = order[index]
            if mode == .toggle && baseline.contains(id) { result.remove(id) }
            else { result.insert(id) }
        }
        previous = hits; projectionUpdates += 1
        return result
    }
}
extension MarqueeSelection: Sendable where ID: Sendable {}
