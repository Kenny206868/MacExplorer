import SwiftUI
import AppKit
import ExplorerCore

@MainActor extension ExplorerWorkspace {
    func reopenClosedTab() {
        guard let tab = closedTabs.popLast() else { return }
        tabs.append(tab); activeID = tab.id; tab.refresh(); saveSession()
    }
    func cycleTab(backward: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        activeID = tabs[(index + (backward ? tabs.count - 1 : 1)) % tabs.count].id
    }
    func keyboardMove(_ key: UInt16, shift: Bool, control: Bool) {
        var state = current.selectionState
        let order = current.displayEntries.map(\.url)
        switch key {
        case 115, 119: state.boundary(last: key == 119, in: order, extend: shift, focusOnly: control && !shift)
        default:
            let stride = [.details, .list, .content].contains(current.options.view) ? 1 : max(1, current.gridColumns)
            let delta = key == 123 ? -1 : key == 124 ? 1 : key == 126 ? -stride : stride
            state.move(by: delta, in: order, extend: shift, focusOnly: control && !shift)
        }
        current.typeAhead.reset(); current.selectionState = state
    }
    func typeAhead(_ text: String, time: TimeInterval) {
        let entries = current.displayEntries
        let focus = current.focusedURL.flatMap { url in entries.firstIndex { $0.url == url } }
        if let index = current.typeAhead.match(text, names: entries.map(\.name), focusedIndex: focus, time: time) {
            select(entries[index].url, extend: false, range: false)
        }
    }
    func toggleFocusedSelection() {
        guard let url = current.focusedURL ?? current.displayEntries.first?.url else { return }
        select(url, extend: true, range: false)
    }
}
