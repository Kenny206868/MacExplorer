import Foundation
import AppKit
import ExplorerCore

@MainActor final class SpotlightSearch {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    func start(expression: SearchExpression, root: URL?, receive: @escaping @MainActor ([URL], Bool) -> Void) {
        stop(); let token = generation
        let query = NSMetadataQuery(); self.query = query
        query.searchScopes = root.map { [$0.path] } ?? [NSMetadataQueryLocalComputerScope]
        query.predicate = expression.spotlightPredicate; query.notificationBatchingInterval = 0.3
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token, let query = self.query else { return }
                    query.disableUpdates()
                    let urls = (query.results as? [NSMetadataItem] ?? []).compactMap { ($0.value(forAttribute: NSMetadataItemPathKey) as? String).map { URL(fileURLWithPath: $0) } }
                    query.enableUpdates(); receive(urls, query.isGathering)
                }
            })
        }
        if !query.start() { receive([], false) }
    }
    func stop() { generation += 1; query?.stop(); query = nil; observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll() }
    deinit { query?.stop(); observers.forEach(NotificationCenter.default.removeObserver) }
}
