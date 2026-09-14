import SwiftUI
import AppKit
import ExplorerCore

@MainActor final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var history: NavigationHistory
    @Published var entries: [FileEntry] = []
    @Published var selection: Set<URL> = []
    @Published var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    @Published var allLocations = false { didSet { scheduleSearch() } }
    @Published var loading = false
    @Published var error: String?
    @Published var warnings: [String] = []
    @Published var truncated = false
    @Published var previewURL: URL?
    @Published var options: FolderOptions { didSet { PreferenceStore.shared.remember(location, options) } }
    var selectionAnchor: URL?
    @Published var focusedURL: URL?
    var typeAhead = TypeAheadSearch()
    var gridColumns = 1
    var pendingSelection: Set<URL>?
    var selectionState: ExplorerSelection<URL> {
        get { ExplorerSelection(selected: selection, anchor: selectionAnchor, focus: focusedURL) }
        set { selection = newValue.selected; selectionAnchor = newValue.anchor; focusedURL = newValue.focus }
    }
    var displayEntries: [FileEntry] { options.group == .none ? visibleEntries : groups.flatMap { $0.1 } }
    func revealAfterRefresh(_ urls: [URL]) { pendingSelection = Set(urls); refresh() }
    let service = FileService()
    private var work: Task<Void, Never>?
    private let watcher = DirectoryWatcher()
    private let spotlight = SpotlightSearch()
    private var generation = 0
    var location: Location { history.current }
    var visibleEntries: [FileEntry] { options.sorted(entries) }
    var groups: [(String, [FileEntry])] {
        let files = visibleEntries
        guard options.group != .none else { return [("", files)] }
        let dictionary = Dictionary(grouping: files) { file -> String in
            switch options.group {
            case .none: return ""
            case .kind: return file.kind
            case .tags: return file.tags.first ?? "Untagged"
            case .modified:
                if Calendar.current.isDateInToday(file.modified) { return "Today" }
                if Calendar.current.isDateInYesterday(file.modified) { return "Yesterday" }
                return file.modified.formatted(.dateTime.year().month(.wide))
            }
        }
        return dictionary.keys.sorted().map { ($0, dictionary[$0] ?? []) }
    }
    init(_ location: Location) { history = NavigationHistory(location); options = PreferenceStore.shared.folderOptions(location) }
    func stop() { generation += 1; work?.cancel(); spotlight.stop(); watcher.stop() }
    func navigate(_ location: Location) {
        stop(); history.navigate(location); query = ""; selection = []; selectionAnchor = nil; focusedURL = nil; typeAhead.reset(); pendingSelection = nil
        options = PreferenceStore.shared.folderOptions(location); refresh()
    }
    func back() { if history.canGoBack { stop(); history.back(); query = ""; selection = []; selectionAnchor = nil; focusedURL = nil; typeAhead.reset(); pendingSelection = nil; options = PreferenceStore.shared.folderOptions(location); refresh() } }
    func forward() { if history.canGoForward { stop(); history.forward(); query = ""; selection = []; selectionAnchor = nil; focusedURL = nil; typeAhead.reset(); pendingSelection = nil; options = PreferenceStore.shared.folderOptions(location); refresh() } }
    func up() { if let directory = location.directory, directory.path != "/" { navigate(.folder(directory.deletingLastPathComponent())) } else { navigate(.computer) } }
    func scheduleSearch() { work?.cancel(); work = Task { try? await Task.sleep(for: .milliseconds(260)); guard !Task.isCancelled else { return }; refresh() } }
    func refresh() {
        work?.cancel(); spotlight.stop(); generation += 1
        let token = generation, location = location, expression = SearchExpression(query)
        let p = PreferenceStore.shared.value
        let root = location.directory ?? FileManager.default.homeDirectoryForCurrentUser
        loading = true; error = nil; warnings = []; truncated = false
        if let directory = location.directory { watcher.watch(directory) { [weak self] in self?.scheduleRefresh() } } else { watcher.stop() }
        if !query.isEmpty && (allLocations || expression.filters["content"] != nil) {
            spotlight.start(expression: expression, root: allLocations ? nil : root) { [weak self] urls, gathering in
                guard let self, token == self.generation else { return }
                self.work?.cancel()
                self.work = Task {
                    do {
                        var snapshot = try await self.service.entries(urls)
                        snapshot.entries = snapshot.entries.filter { expression.matches($0) && (p.showHidden || !$0.isHidden) }
                        guard token == self.generation, !Task.isCancelled else { return }
                        self.install(snapshot); self.loading = gathering
                    } catch is CancellationError {} catch { self.error = error.localizedDescription; self.loading = false }
                }
            }
            return
        }
        if case .tag(let tag) = location, query.isEmpty {
            spotlight.start(expression: SearchExpression("tag:\"\(tag)\""), root: nil) { [weak self] urls, gathering in
                guard let self, token == self.generation else { return }
                self.work?.cancel(); self.work = Task {
                    do { let snapshot = try await self.service.entries(urls); guard token == self.generation, !Task.isCancelled else { return }; self.install(snapshot); self.loading = gathering }
                    catch is CancellationError {} catch { self.error = error.localizedDescription; self.loading = false }
                }
            }
            return
        }
        work = Task {
            do {
                let snapshot: DirectorySnapshot
                if !query.isEmpty {
                    if p.recursiveSearch { snapshot = try await service.search([root], expression: expression, showHidden: p.showHidden) }
                    else { var value = try await service.list(root, showHidden: p.showHidden); value.entries = value.entries.filter(expression.matches); snapshot = value }
                } else {
                    switch location {
                    case .home: snapshot = try await service.entries(p.recent.map(\.url).filter { FileNames.exists($0) })
                    case .folder(let url): snapshot = try await service.list(url, showHidden: p.showHidden)
                    case .gallery: snapshot = try await service.search([root], expression: expression, showHidden: p.showHidden, imagesOnly: true)
                    case .trash:
                        var combined = DirectorySnapshot()
                        for trash in NativeIntegration.trashDirectories() {
                            do { let part = try await service.list(trash, showHidden: p.showHidden); combined.entries += part.entries; combined.warnings += part.warnings }
                            catch { combined.warnings.append("\(trash.path): \(error.localizedDescription)") }
                        }
                        snapshot = combined
                    case .computer, .network, .tag: snapshot = DirectorySnapshot()
                    }
                }
                guard token == generation, !Task.isCancelled else { return }
                install(snapshot); loading = false
            } catch is CancellationError {} catch { guard token == generation else { return }; self.error = error.localizedDescription; loading = false }
        }
    }
    private func install(_ snapshot: DirectorySnapshot) {
        entries = snapshot.entries; warnings = snapshot.warnings; truncated = snapshot.truncated
        if let pendingSelection { selection = pendingSelection; focusedURL = entries.first(where: { pendingSelection.contains($0.url) })?.url; selectionAnchor = focusedURL; self.pendingSelection = nil }
        var state = selectionState; state.reconcile(with: displayEntries.map(\.url)); selectionState = state
    }
    private func scheduleRefresh() { work?.cancel(); work = Task { try? await Task.sleep(for: .milliseconds(180)); guard !Task.isCancelled else { return }; refresh() } }
}

@MainActor final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var url: URL?
    func watch(_ url: URL, changed: @escaping @MainActor () -> Void) {
        if self.url == url, source != nil { return }
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        self.url = url
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke], queue: .main)
        source.setEventHandler { Task { @MainActor in changed() } }
        source.setCancelHandler { close(descriptor) }
        self.source = source; source.resume()
    }
    func stop() { source?.cancel(); source = nil; url = nil }
    deinit { source?.cancel() }
}

@MainActor final class SpotlightSearch {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    func start(expression: SearchExpression, root: URL?, receive: @escaping @MainActor ([URL], Bool) -> Void) {
        stop()
        let query = NSMetadataQuery(); self.query = query
        query.searchScopes = root.map { [$0.path] } ?? [NSMetadataQueryLocalComputerScope]
        query.predicate = expression.spotlightPredicate
        query.notificationBatchingInterval = 0.3
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak query] _ in
                Task { @MainActor in
                    guard let query else { return }
                    query.disableUpdates()
                    let urls = (query.results as? [NSMetadataItem] ?? []).compactMap { ($0.value(forAttribute: NSMetadataItemPathKey) as? String).map { URL(fileURLWithPath: $0) } }
                    query.enableUpdates(); receive(urls, query.isGathering)
                }
            })
        }
        if !query.start() { receive([], false) }
    }
    func stop() { query?.stop(); query = nil; observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll() }
    deinit { query?.stop(); observers.forEach(NotificationCenter.default.removeObserver) }
}
