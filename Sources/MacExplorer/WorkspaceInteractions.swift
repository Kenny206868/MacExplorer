import AppKit
import ExplorerCore

@MainActor extension ExplorerWorkspace {
    func select(_ url: URL, extend: Bool, range: Bool) {
        let tab = current, order = current.navigation.order
        guard order.contains(url) else { return }
        if range && tab.rangeBaseline == nil { tab.rangeBaseline = extend ? tab.selection : [] }
        if !range { tab.rangeBaseline = nil }
        var model = ExplorerSelection(selected: range && extend ? (tab.rangeBaseline ?? []) : tab.selection, anchor: tab.selectionAnchor, focus: tab.focusedURL)
        model.click(url, in: order, toggle: extend, range: range)
        tab.applySelection(model)
    }
    func selectAll() {
        let tab = current; tab.rangeBaseline = nil
        let all = Set(tab.navigation.order.ids); if tab.selection != all { tab.selection = all }
    }
    func invertSelection() { current.rangeBaseline = nil; current.selection = Set(current.navigation.order.ids).subtracting(current.selection) }
    func moveSelection(_ offset: Int, extend: Bool = false, focusOnly: Bool = false) {
        let tab = current, order = current.navigation.order
        tab.typeAhead.reset(); guard !order.ids.isEmpty else { return }
        if !extend { tab.rangeBaseline = nil }
        var model = ExplorerSelection(selected: tab.selection, anchor: tab.selectionAnchor, focus: tab.focusedURL)
        model.move(by: offset, in: order, extend: extend, focusOnly: focusOnly)
        tab.applySelection(model)
    }
    func selectBoundary(last: Bool, extend: Bool, focusOnly: Bool = false) {
        let tab = current, order = current.navigation.order
        guard !order.ids.isEmpty else { return }
        if extend && tab.selectionAnchor == nil { tab.selectionAnchor = tab.focusedURL ?? order.ids.first }
        if !extend { tab.rangeBaseline = nil }
        var model = ExplorerSelection(selected: tab.selection, anchor: tab.selectionAnchor, focus: tab.focusedURL)
        model.boundary(last: last, in: order, extend: extend, focusOnly: focusOnly)
        tab.applySelection(model)
    }
    func typeToSelect(_ text: String, time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        let tab = current, navigation = current.navigation
        let focusedIndex = navigation.order.focusedIndex(tab.focusedURL, selected: tab.selection)
        guard let index = tab.typeAhead.match(text, names: navigation.names, focusedIndex: focusedIndex, time: time) else { return false }
        select(navigation.order.ids[index], extend: false, range: false); return true
    }
    func cycleTab(backward: Bool) { cycleTab(backward ? -1 : 1) }
    func keyboardMove(_ key: UInt16, shift: Bool, control: Bool) {
        current.typeAhead.reset()
        if key == 115 || key == 119 { selectBoundary(last: key == 119, extend: shift, focusOnly: control && !shift) }
        else {
            let stride = [.details, .list, .content, .gallery].contains(current.options.view) ? 1 : max(1, current.gridColumns)
            var delta = key == 123 ? -1 : key == 124 ? 1 : key == 126 ? -stride : stride
            if stride > 1 && (key == 125 || key == 126) {
                let order = current.navigation.order
                if let index = order.focusedIndex(current.focusedURL, selected: current.selection),
                   let neighbor = GridNavigation.verticalNeighbor(of: index, counts: current.groups.map { $0.1.count }, columns: stride, direction: key == 126 ? -1 : 1) { delta = neighbor - index }
            }
            moveSelection(delta, extend: shift, focusOnly: control && !shift)
        }
    }
    func typeAhead(_ text: String, time: TimeInterval) { _ = typeToSelect(text, time: time) }
    func toggleFocusedSelection() {
        guard let url = current.focusedURL ?? current.navigation.order.ids.first else { return }; select(url, extend: true, range: false)
    }
}
