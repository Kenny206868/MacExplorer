import Foundation
import CoreGraphics

/// Exact geometry shared by the SwiftUI grid and selection hit testing. Unmaterialized
/// LazyVGrid cells remain selectable without retaining a view or rectangle per file.
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
        self.inset = inset; self.gap = gap; self.rowGap = rowGap; self.cellHeight = max(1, cellHeight)
        let available = max(1, width - 2 * inset)
        columns = max(1, Int((available + gap) / (max(1, minimumWidth) + gap)))
        cellWidth = max(1, (available - CGFloat(columns - 1) * gap) / CGFloat(columns))
        var y = inset, start = 0, result: [Section] = []
        for count in counts {
            let count = max(0, count), rows = (count + columns - 1) / columns
            if headers { y += 28 }
            result.append(Section(startIndex: start, count: count, top: y, rows: rows))
            y += CGFloat(rows) * self.cellHeight + CGFloat(max(0, rows - 1)) * rowGap + 15
            start += count
        }
        sections = result; height = y + inset
    }
    public func rect(for index: Int) -> CGRect? {
        guard let section = sections.first(where: { index >= $0.startIndex && index < $0.startIndex + $0.count }) else { return nil }
        let local = index - section.startIndex
        return CGRect(x: inset + CGFloat(local % columns) * (cellWidth + gap),
                      y: section.top + CGFloat(local / columns) * (cellHeight + rowGap), width: cellWidth, height: cellHeight)
    }
    public func indices(intersecting rectangle: CGRect) -> [Int] {
        let r = rectangle.standardized
        guard !r.isNull, !r.isInfinite, r.width > 0, r.height > 0 else { return [] }
        var result: [Int] = []
        for section in sections where section.count > 0 {
            let bounds = CGRect(x: inset, y: section.top, width: CGFloat(columns) * (cellWidth + gap) - gap,
                                height: CGFloat(section.rows) * (cellHeight + rowGap) - rowGap)
            let intersection = r.intersection(bounds)
            guard !intersection.isNull, !intersection.isEmpty else { continue }
            let firstRow = max(0, Int((intersection.minY - section.top) / (cellHeight + rowGap)))
            let lastRow = min(section.rows - 1, Int((intersection.maxY - section.top) / (cellHeight + rowGap)))
            let firstColumn = max(0, Int((intersection.minX - inset) / (cellWidth + gap)))
            let lastColumn = min(columns - 1, Int((intersection.maxX - inset) / (cellWidth + gap)))
            guard firstRow <= lastRow, firstColumn <= lastColumn else { continue }
            for row in firstRow...lastRow {
                for column in firstColumn...lastColumn {
                    let index = section.startIndex + row * columns + column
                    if index < section.startIndex + section.count, let cell = rect(for: index), cell.intersects(r) { result.append(index) }
                }
            }
        }
        return result
    }
    public func index(at point: CGPoint) -> Int? {
        indices(intersecting: CGRect(origin: point, size: CGSize(width: 0.01, height: 0.01))).first
    }
}
