import Foundation

/// Logical row rectangles remain available even when LazyVStack has recycled
/// their views. Header gaps are not selectable; collapsed groups have no rows.
public struct DetailsRowGeometry: Sendable {
    private struct Run: Sendable { let top: Double; let count: Int; let index: Int }
    private var runs: [Run] = []
    public let rowHeight: Double
    public let headerHeight: Double
    public private(set) var height: Double
    public init(counts: [Int], headings: [Bool], rowHeight: Double, headerHeight: Double) {
        self.rowHeight = rowHeight.isFinite ? max(1, rowHeight) : 36
        self.headerHeight = headerHeight.isFinite ? max(0, headerHeight) : 34
        height = self.headerHeight
        var index = 0
        for (group, supplied) in counts.enumerated() {
            let count = min(1_000_000, max(0, supplied))
            if group < headings.count && headings[group] { height += self.headerHeight }
            runs.append(Run(top: height, count: count, index: index))
            height += Double(count) * self.rowHeight; index += count
        }
    }
    public func index(at y: Double) -> Int? {
        guard y.isFinite else { return nil }
        for run in runs where y >= run.top && y < run.top + Double(run.count) * rowHeight {
            return run.index + Int((y - run.top) / rowHeight)
        }
        return nil
    }
    public func indices(from a: Double, through b: Double) -> [Int] { Array(indexSet(from: a, through: b)) }
    public func indexSet(from a: Double, through b: Double) -> IndexSet {
        guard a.isFinite, b.isFinite else { return [] }
        let low = min(a, b), high = max(a, b)
        guard high > low else { return [] }
        var result = IndexSet()
        for run in runs where run.count > 0 {
            let firstY = max(low, run.top), lastY = min(high, run.top + Double(run.count) * rowHeight)
            guard firstY < lastY else { continue }
            let first = max(0, Int(floor((firstY - run.top) / rowHeight)))
            let end = min(run.count, Int(ceil((lastY - run.top) / rowHeight)))
            if first < end { result.insert(integersIn: (run.index + first)..<(run.index + end)) }
        }
        return result
    }
}
