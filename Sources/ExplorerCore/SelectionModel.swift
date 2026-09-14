import Foundation

/// Explorer selection semantics, independent of SwiftUI and the filesystem.
/// Focus is deliberately distinct from the anchor and the selected set.
public struct ExplorerSelection<ID: Hashable & Sendable>: Sendable {
    public var selected: Set<ID>
    public var anchor: ID?
    public var focus: ID?

    public init(selected: Set<ID> = [], anchor: ID? = nil, focus: ID? = nil) {
        self.selected = selected; self.anchor = anchor; self.focus = focus
    }

    public mutating func click(_ item: ID, in order: [ID], toggle: Bool = false, range: Bool = false) {
        guard order.contains(item) else { return }
        if range {
            let start = anchor ?? focus ?? item
            if let a = order.firstIndex(of: start), let b = order.firstIndex(of: item) {
                let interval = Set(order[min(a, b)...max(a, b)])
                selected = toggle ? selected.union(interval) : interval
                anchor = start
            } else { selected = [item]; anchor = item }
        } else if toggle {
            if !selected.insert(item).inserted { selected.remove(item) }
            anchor = item
        } else { selected = [item]; anchor = item }
        focus = item
    }

    public mutating func move(by offset: Int, in order: [ID], extend: Bool = false, focusOnly: Bool = false) {
        guard !order.isEmpty else { return }
        let previous = focus.flatMap { order.firstIndex(of: $0) }
            ?? order.firstIndex(where: selected.contains)
        let index = previous.map { max(0, min(order.count - 1, $0 + offset)) }
            ?? (offset < 0 ? order.count - 1 : 0)
        if focusOnly { focus = order[index]; if anchor == nil { anchor = focus } }
        else { click(order[index], in: order, range: extend) }
    }

    public mutating func boundary(last: Bool, in order: [ID], extend: Bool = false, focusOnly: Bool = false) {
        guard let item = last ? order.last : order.first else { return }
        if focusOnly { focus = item; if anchor == nil { anchor = item } }
        else { click(item, in: order, range: extend) }
    }

    public mutating func reconcile(with order: [ID]) {
        let available = Set(order)
        selected.formIntersection(available)
        if let focus, !available.contains(focus) { self.focus = order.first(where: selected.contains) }
        if let anchor, !available.contains(anchor) { self.anchor = focus }
    }
}

/// Call with a monotonic timestamp. A fresh prefix searches after the focused item;
/// subsequent characters refine it. Repeating a single character cycles matches.
public struct TypeAheadSearch: Sendable {
    public private(set) var prefix = ""
    private var lastTime: TimeInterval = -.infinity
    public var timeout: TimeInterval = 0.9
    public init() {}
    public mutating func reset() { prefix = ""; lastTime = -.infinity }
    public mutating func match(_ text: String, names: [String], focusedIndex: Int?, time: TimeInterval) -> Int? {
        guard !text.isEmpty, !names.isEmpty,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let expired = time - lastTime > timeout || time < lastTime
        let cycling = !expired && prefix.count == 1 && prefix.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        prefix = expired || cycling ? text : prefix + text
        lastTime = time
        let start = focusedIndex.map { (expired || cycling ? $0 + 1 : $0) % names.count } ?? 0
        for offset in 0..<names.count {
            let index = (start + offset) % names.count
            if names[index].range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil { return index }
        }
        return nil
    }
}
