import Foundation

/// Maps vertical arrows to actual visual rows. A partial final row and a group
/// header must not turn a Down arrow into a jump to the middle of another row.
public enum GridNavigation {
    public static func verticalNeighbor(of index: Int, counts: [Int], columns: Int, direction: Int) -> Int? {
        guard index >= 0, columns > 0, direction != 0, counts.allSatisfy({ $0 >= 0 }) else { return nil }
        var starts: [Int] = [], total = 0
        for count in counts {
            starts.append(total)
            let (next, overflow) = total.addingReportingOverflow(count)
            guard !overflow else { return nil }; total = next
        }
        guard index < total,
              let section = counts.indices.first(where: { index >= starts[$0] && index - starts[$0] < counts[$0] }) else { return nil }
        let local = index - starts[section], column = local % columns, row = local / columns
        if direction > 0 {
            let remaining = counts[section] - local
            if remaining > columns - column {
                let nextRow = local - column + columns
                return starts[section] + nextRow + min(column, counts[section] - 1 - nextRow)
            }
            guard let next = counts.indices.first(where: { $0 > section && counts[$0] > 0 }) else { return index }
            return starts[next] + min(column, counts[next] - 1)
        }
        if row > 0 { return starts[section] + (row - 1) * columns + column }
        guard let previous = counts.indices.reversed().first(where: { $0 < section && counts[$0] > 0 }) else { return index }
        let lastRow = (counts[previous] - 1) / columns
        let lastStart = lastRow * columns
        return starts[previous] + lastStart + min(column, counts[previous] - 1 - lastStart)
    }
}
