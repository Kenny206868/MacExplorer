import Foundation
import ExplorerCore

/// Immutable input data shared by every event until the listing/group/view
/// revision changes. It never opens files or resolves bookmarks in the UI loop.
struct FileNavigationSnapshot: Sendable {
    let entries: [FileEntry]
    let order: IndexedSelectionOrder<URL>
    let names: [String]
    init(entries: [FileEntry]) {
        self.entries = entries
        order = IndexedSelectionOrder(entries.map(\.url)); names = entries.map(\.name)
    }
}
