import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Exact geometry shared by SwiftUI and input. Hit testing is independent of
/// materialized views. Marquee ranges cost O(groups + intersecting rows), not
/// O(selected cells * groups); direct point/identity lookups use binary search.
public struct ExplorerGridGeometry: Sendable {
    public struct Section: Sendable {
        public let startIndex: Int
        public let count: Int
        public let top: CGFloat
        public let rows: Int
    }
    public let columns: Int
    public let cellWidth: CGFloat
    public let cellHeight: CGFloat
    public let inset: CGFloat
    public let gap: CGFloat
    public let rowGap: CGFloat
    public let sections: [Section]
    public let height: CGFloat

    public init(counts: [Int], width: CGFloat, minimumWidth: CGFloat, cellHeight: CGFloat, headers: Bool,
                inset: CGFloat = 18, gap: CGFloat = 9, rowGap: CGFloat = 10) {
        func dimension(_ value: CGFloat, fallback: CGFloat, minimum: CGFloat = 0) -> CGFloat {
            value.isFinite ? min(1_000_000_000, max(minimum, value)) : fallback
        }
        self.inset = dimension(inset, fallback: 18)
        self.gap = dimension(gap, fallback: 9)
        self.rowGap = dimension(rowGap, fallback: 10)
        self.cellHeight = dimension(cellHeight, fallback: 1, minimum: 1)
        let available = max(1, dimension(width, fallback: 1) - 2 * self.inset)
        let count = (available + self.gap) / (dimension(minimumWidth, fallback: 1, minimum: 1) + self.gap)
        columns = max(1, Int(min(4096, count)))
        cellWidth = max(1, (available - CGFloat(columns - 1) * self.gap) / CGFloat(columns))
        var y = self.inset, start = 0, result: [Section] = []
        result.reserveCapacity(counts.count)
        for supplied in counts {
            let count = min(max(0, supplied), Int.max - start)
            // Ceil division without overflowing count + columns - 1.
            let rows = count / columns + (count % columns == 0 ? 0 : 1)
            if headers { y += 28 }
            result.append(Section(startIndex: start, count: count, top: y, rows: rows))
            y += CGFloat(rows) * self.cellHeight + CGFloat(max(0, rows - 1)) * self.rowGap + 15
            start += count
        }
        sections = result; height = y + self.inset
    }

    public func rect(for index: Int) -> CGRect? {
        guard index >= 0 else { return nil }
        var low = 0, high = sections.count
        while low < high {
            let middle = low + (high - low) / 2
            if sections[middle].startIndex <= index { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let section = sections[low - 1], local = index - section.startIndex
        guard local < section.count else { return nil }
        return CGRect(x: inset + CGFloat(local % columns) * (cellWidth + gap),
                      y: section.top + CGFloat(local / columns) * (cellHeight + rowGap), width: cellWidth, height: cellHeight)
    }

    public func indexSet(intersecting rectangle: CGRect) -> IndexSet {
        guard rectangle.origin.x.isFinite, rectangle.origin.y.isFinite,
              rectangle.size.width.isFinite, rectangle.size.height.isFinite else { return [] }
        let r = rectangle.standardized
        guard !r.isNull, !r.isInfinite, r.minX.isFinite, r.minY.isFinite, r.maxX.isFinite, r.maxY.isFinite, r.width > 0, r.height > 0 else { return [] }
        var result = IndexSet()
        for section in sections where section.count > 0 {
            let bounds = CGRect(x: inset, y: section.top, width: CGFloat(columns) * (cellWidth + gap) - gap,
                                height: CGFloat(section.rows) * (cellHeight + rowGap) - rowGap)
            let intersection = r.intersection(bounds)
            guard !intersection.isNull, !intersection.isEmpty else { continue }
            var firstRow = boundedFloor((intersection.minY - section.top) / (cellHeight + rowGap), upper: section.rows - 1)
            var lastRow = boundedFloor((intersection.maxY - section.top) / (cellHeight + rowGap), upper: section.rows - 1)
            var firstColumn = boundedFloor((intersection.minX - inset) / (cellWidth + gap), upper: columns - 1)
            var lastColumn = boundedFloor((intersection.maxX - inset) / (cellWidth + gap), upper: columns - 1)
            if section.top + CGFloat(firstRow) * (cellHeight + rowGap) + cellHeight <= intersection.minY { firstRow += 1 }
            if section.top + CGFloat(lastRow) * (cellHeight + rowGap) >= intersection.maxY { lastRow -= 1 }
            if inset + CGFloat(firstColumn) * (cellWidth + gap) + cellWidth <= intersection.minX { firstColumn += 1 }
            if inset + CGFloat(lastColumn) * (cellWidth + gap) >= intersection.maxX { lastColumn -= 1 }
            guard firstRow <= lastRow, firstColumn <= lastColumn else { continue }
            if firstColumn == 0 && lastColumn == columns - 1 {
                let lastOffset = lastRow * columns
                let end = lastOffset + min(columns, section.count - lastOffset)
                result.insert(integersIn: (section.startIndex + firstRow * columns)..<(section.startIndex + end))
            } else {
                for row in firstRow...lastRow {
                    let offset = row * columns, available = min(columns, section.count - offset)
                    guard firstColumn < available else { continue }
                    let start = section.startIndex + offset
                    result.insert(integersIn: (start + firstColumn)..<(start + min(lastColumn + 1, available)))
                }
            }
        }
        return result
    }
    public func indices(intersecting rectangle: CGRect) -> [Int] { Array(indexSet(intersecting: rectangle)) }

    public func index(at point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite, point.x >= inset,
              point.x < inset + CGFloat(columns) * (cellWidth + gap) - gap else { return nil }
        var low = 0, high = sections.count
        while low < high {
            let middle = low + (high - low) / 2
            if sections[middle].top <= point.y { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let section = sections[low - 1]
        guard section.count > 0,
              point.y < section.top + CGFloat(section.rows) * (cellHeight + rowGap) - rowGap else { return nil }
        let row = boundedFloor((point.y - section.top) / (cellHeight + rowGap), upper: section.rows - 1)
        let column = boundedFloor((point.x - inset) / (cellWidth + gap), upper: columns - 1)
        guard point.x < inset + CGFloat(column) * (cellWidth + gap) + cellWidth,
              point.y < section.top + CGFloat(row) * (cellHeight + rowGap) + cellHeight else { return nil }
        let offset = row * columns
        guard column < section.count - offset else { return nil }
        return section.startIndex + offset + column
    }

    private func boundedFloor(_ value: CGFloat, upper: Int) -> Int {
        // CGFloat(Int.max) rounds upward; compare before converting, not after.
        if value >= CGFloat(upper) { return upper }
        if value <= 0 { return 0 }
        return Int(value.rounded(.down))
    }
}
