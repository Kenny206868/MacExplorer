import Foundation
import ExplorerCore

@MainActor extension BrowserTab {
    /// Match an exact extension, including extensionless files, without regex
    /// escaping or filesystem reads. Large-list work stays off the UI actor.
    func selectSameExtension(_ ext: String) {
        cancelSelectionWork()
        let revision = dataRevision, visible = navigation, originalSelection = selection, token = UUID()
        selectionWorkID = token; selectionMatching = true
        selectionWork = Task { [weak self] in
            defer {
                if let self, self.selectionWorkID == token {
                    self.selectionWorkID = nil; self.selectionWork = nil; self.selectionMatching = false
                }
            }
            do {
                let matched = try await FileReadExecutor.presentation.run { cancellation -> Set<URL> in
                    var result = Set<URL>()
                    for (index, entry) in visible.entries.enumerated() {
                        if index & 127 == 0 { try cancellation.check() }
                        if !entry.isDirectory && entry.url.pathExtension.compare(ext, options: [.caseInsensitive, .literal]) == .orderedSame { result.insert(entry.url) }
                    }
                    return result
                }
                guard let self, !Task.isCancelled, self.selectionWorkID == token,
                      self.dataRevision == revision, self.navigation.order.ids == visible.order.ids,
                      self.selection == originalSelection else { return }
                self.rangeBaseline = nil; self.selection = matched
            } catch { /* Cancellation/stale presentation leaves the user's newer selection untouched. */ }
        }
    }
    func cancelSelectionWork() {
        selectionWorkID = nil; selectionWork?.cancel(); selectionWork = nil
        if selectionMatching { selectionMatching = false }
    }
}
