import Foundation
import ExplorerCore

/// One immutable input order per drag. Reject a refresh, navigation or reorder
/// synchronously, even before SwiftUI delivers the corresponding onChange.
@MainActor final class FileMarqueeSession {
    enum Update { case unchanged, changed(lastHit: URL?), invalidated }
    private weak var tab: BrowserTab?
    private let location: Location
    private let dataRevision: UInt64
    private let navigationBuild: Int
    private var projection: MarqueeSelection<URL>

    init(tab: BrowserTab, mode: MarqueeSelectionMode) {
        self.tab = tab; location = tab.location; dataRevision = tab.dataRevision
        let navigation = tab.navigation
        navigationBuild = tab.navigationBuilds
        projection = MarqueeSelection(order: navigation.order.ids, baseline: tab.selection, mode: mode)
    }
    func update(hits: IndexSet) -> Update {
        guard let tab, tab.location == location, tab.dataRevision == dataRevision else { return .invalidated }
        let navigation = tab.navigation
        guard tab.navigationBuilds == navigationBuild else { return .invalidated }
        guard let selection = projection.update(hits: hits) else { return .unchanged }
        if tab.selection != selection { tab.selection = selection }
        let last = hits.last.flatMap { navigation.entries.indices.contains($0) ? navigation.entries[$0].url : nil }
        return .changed(lastHit: last)
    }
}
