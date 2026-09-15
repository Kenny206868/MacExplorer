import Foundation

/// A listing-revision index, not a per-event temporary. Membership and focused
/// movement are O(1); range selection touches only the selected interval. IDs
/// must be unique, as they are in a directory snapshot. Duplicate IDs retain
/// their first position so malformed input never traps Dictionary initialization.
public struct IndexedSelectionOrder<ID: Hashable & Sendable>: Sendable {
    public let ids: [ID]
    private let positions: [ID: Int]
    public init(_ ids: [ID]) {
        self.ids = ids
        positions = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }
    public func index(of id: ID) -> Int? { positions[id] }
    public func contains(_ id: ID) -> Bool { positions[id] != nil }
    public func firstSelectedIndex(in selected: Set<ID>) -> Int? {
        // Empty/single/sparse selections must not scan the entire directory.
        if selected.count < ids.count / 4 { return selected.compactMap { positions[$0] }.min() }
        return ids.firstIndex(where: selected.contains)
    }
    public func focusedIndex(_ focus: ID?, selected: Set<ID>) -> Int? {
        focus.flatMap { positions[$0] } ?? firstSelectedIndex(in: selected)
    }
}

public extension ExplorerSelection {
    mutating func click(_ item: ID, in order: IndexedSelectionOrder<ID>, toggle: Bool = false, range: Bool = false) {
        guard let index = order.index(of: item) else { return }
        if range {
            let start = anchor ?? focus ?? item
            if let beginning = order.index(of: start) {
                let interval = Set(order.ids[min(beginning, index)...max(beginning, index)])
                selected = toggle ? selected.union(interval) : interval; anchor = start
            } else { selected = [item]; anchor = item }
        } else if toggle {
            if !selected.insert(item).inserted { selected.remove(item) }; anchor = item
        } else { selected = [item]; anchor = item }
        focus = item
    }
    mutating func move(by offset: Int, in order: IndexedSelectionOrder<ID>, extend: Bool = false, focusOnly: Bool = false) {
        guard !order.ids.isEmpty else { return }
        let index: Int
        if let previous = order.focusedIndex(focus, selected: selected) {
            // A synthetic Page Down / accessibility increment must not overflow.
            let (sum, overflow) = previous.addingReportingOverflow(offset)
            index = overflow ? (offset < 0 ? 0 : order.ids.count - 1) : max(0, min(order.ids.count - 1, sum))
        } else { index = offset < 0 ? order.ids.count - 1 : 0 }
        if focusOnly { focus = order.ids[index]; if anchor == nil { anchor = focus } }
        else { click(order.ids[index], in: order, range: extend) }
    }
    mutating func boundary(last: Bool, in order: IndexedSelectionOrder<ID>, extend: Bool = false, focusOnly: Bool = false) {
        guard let item = last ? order.ids.last : order.ids.first else { return }
        if focusOnly { focus = item; if anchor == nil { anchor = item } }
        else { click(item, in: order, range: extend) }
    }
}
