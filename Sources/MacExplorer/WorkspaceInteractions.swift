import AppKit
import ExplorerCore

@MainActor extension ExplorerWorkspace {
    func select(_ url: URL, extend: Bool, range: Bool) {
        let tab = current
        let ordered = tab.displayEntries.map(\.url)
        if range && tab.rangeBaseline == nil { tab.rangeBaseline = extend ? tab.selection : [] }
        if !range { tab.rangeBaseline = nil }
        var model = ExplorerSelection(selected: range && extend ? (tab.rangeBaseline ?? []) : tab.selection,
                                      anchor: tab.selectionAnchor, focus: tab.focusedURL)
        model.click(url, in: ordered, toggle: extend, range: range)
        tab.selection = model.selected; tab.selectionAnchor = model.anchor; tab.focusedURL = model.focus
    }
    func selectAll() {
        current.rangeBaseline = nil
        current.selection = Set(current.displayEntries.map(\.url))
    }
    func invertSelection() {
        current.rangeBaseline = nil
        current.selection = Set(current.displayEntries.map(\.url)).subtracting(current.selection)
    }
    func moveSelection(_ offset: Int, extend: Bool = false, focusOnly: Bool = false) {
        let tab = current, files = current.displayEntries
        tab.typeAhead.reset()
        guard !files.isEmpty else { return }
        var model = ExplorerSelection(selected: tab.selection, anchor: tab.selectionAnchor, focus: tab.focusedURL)
        model.move(by: offset, in: files.map(\.url), extend: extend, focusOnly: focusOnly)
        guard let focus = model.focus else { return }
        if focusOnly {
            tab.objectWillChange.send()
            tab.focusedURL = focus; tab.selectionAnchor = model.anchor
        } else { select(focus, extend: false, range: extend) }
    }
    func selectBoundary(last: Bool, extend: Bool, focusOnly: Bool = false) {
        let files = current.displayEntries
        guard let file = last ? files.last : files.first else { return }
        if extend && current.selectionAnchor == nil { current.selectionAnchor = current.focusedURL ?? files.first?.url }
        if focusOnly { current.focusedURL = file.url } else { select(file.url, extend: false, range: extend) }
    }
    func typeToSelect(_ text: String, time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        let tab = current, files = current.displayEntries
        let currentIndex = files.firstIndex { $0.url == tab.focusedURL }
            ?? files.firstIndex { tab.selection.contains($0.url) }
        guard let index = tab.typeAhead.match(text, names: files.map(\.name), focusedIndex: currentIndex, time: time) else { return false }
        select(files[index].url, extend: false, range: false)
        return true
    }
    func cycleTab(backward: Bool) { cycleTab(backward ? -1 : 1) }
    func keyboardMove(_ key: UInt16, shift: Bool, control: Bool) {
        current.typeAhead.reset()
        if key == 115 || key == 119 {
            selectBoundary(last: key == 119, extend: shift, focusOnly: control && !shift)
        } else {
            let stride = [.details, .list, .content, .gallery].contains(current.options.view) ? 1 : max(1, current.gridColumns)
            var delta = key == 123 ? -1 : key == 124 ? 1 : key == 126 ? -stride : stride
            if stride > 1 && (key == 125 || key == 126) {
                let files = current.displayEntries
                let index = files.firstIndex { $0.url == current.focusedURL }
                    ?? files.firstIndex { current.selection.contains($0.url) }
                if let index, let neighbor = GridNavigation.verticalNeighbor(of: index, counts: current.groups.map { $0.1.count }, columns: stride, direction: key == 126 ? -1 : 1) {
                    delta = neighbor - index
                }
            }
            moveSelection(delta, extend: shift, focusOnly: control && !shift)
        }
    }
    func typeAhead(_ text: String, time: TimeInterval) { _ = typeToSelect(text, time: time) }
    func toggleFocusedSelection() {
        guard let url = current.focusedURL ?? current.displayEntries.first?.url else { return }
        select(url, extend: true, range: false)
    }
}
