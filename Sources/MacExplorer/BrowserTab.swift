import SwiftUI
import AppKit
import ExplorerCore

@MainActor final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var history: NavigationHistory
    @Published var entries: [FileEntry] = [] { didSet { invalidatePresentation() } }
    @Published var selection: Set<URL> = [] { didSet { cachedSelectedEntries = nil } }
    @Published var collapsedGroups: Set<String> = [] { didSet { invalidateNavigation() } }
    @Published var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    @Published var allLocations = false { didSet { scheduleSearch() } }
    @Published var loading = false
    @Published var archiveRevision = 0
    @Published var archiveItemCount = 0
    @Published var archiveSelectionCount = 0
    @Published var error: String?
    @Published var warnings: [String] = []
    @Published var truncated = false
    @Published var previewURL: URL?
    @Published var options: FolderOptions {
        didSet {
            if options.sort != oldValue.sort || options.descending != oldValue.descending || options.foldersFirst != oldValue.foldersFirst || options.group != oldValue.group { invalidatePresentation() }
            if options.group != oldValue.group { collapsedGroups = [] }
            if options.view != oldValue.view { invalidateNavigation() }
            PreferenceStore.shared.remember(location, options)
        }
    }
    private var cachedPresentation: FilePresentation?
    private(set) var presentationBuilds = 0
    private var presentation: FilePresentation {
        if let cachedPresentation { return cachedPresentation }
        let value = FilePresentation(entries: entries, options: options)
        cachedPresentation = value; presentationBuilds += 1; return value
    }
    func invalidatePresentation() { cachedPresentation = nil; cachedSelectedEntries = nil; invalidateNavigation() }
    private var cachedSelectedEntries: [FileEntry]?
    private(set) var selectedProjectionBuilds = 0
    var selectedEntries: [FileEntry] {
        if let cachedSelectedEntries { return cachedSelectedEntries }
        let result = presentation.selected(selection)
        cachedSelectedEntries = result; selectedProjectionBuilds += 1; return result
    }
    private var cachedNavigation: FileNavigationSnapshot?
    private(set) var navigationBuilds = 0
    private func invalidateNavigation() { cachedNavigation = nil }
    var navigation: FileNavigationSnapshot {
        if let cachedNavigation { return cachedNavigation }
        let entries = options.view == .details && !collapsedGroups.isEmpty
            ? presentation.groups.filter { !collapsedGroups.contains($0.title) }.flatMap(\.entries) : presentation.ordered
        let value = FileNavigationSnapshot(entries: entries)
        cachedNavigation = value; navigationBuilds += 1; return value
    }
    /// No filesystem access or redundant publication in high-frequency input.
    func applySelection(_ value: ExplorerSelection<URL>) {
        if selection != value.selected { selection = value.selected }
        selectionAnchor = value.anchor
        if focusedURL != value.focus { focusedURL = value.focus }
    }
    var selectionAnchor: URL?
    @Published var focusedURL: URL?
    var rangeBaseline: Set<URL>?
    var typeAhead = TypeAheadSearch()
    var gridColumns = 1
    private var pendingSelection: Set<URL>?
    var selectionState: ExplorerSelection<URL> {
        get { ExplorerSelection(selected: selection, anchor: selectionAnchor, focus: focusedURL) }
        set { selection = newValue.selected; selectionAnchor = newValue.anchor; focusedURL = newValue.focus }
    }
    var displayEntries: [FileEntry] { presentation.ordered }
    var navigableEntries: [FileEntry] { navigation.entries }
    func toggleGroup(_ title: String) {
        guard !title.isEmpty, let group = presentation.groups.first(where: { $0.title == title }) else { return }
        if collapsedGroups.remove(title) != nil { return }
        let hidden = Set(group.entries.map(\.url))
        collapsedGroups.insert(title); selection.subtract(hidden)
        if let focus = focusedURL, hidden.contains(focus) { focusedURL = nil }
        if let anchor = selectionAnchor, hidden.contains(anchor) { selectionAnchor = nil }
        rangeBaseline = nil; typeAhead.reset()
    }
    func revealAfterRefresh(_ urls: [URL]) { refresh(selecting: urls) }
    let service = FileService()
    private var work: Task<Void, Never>?
    private let watcher = DirectoryWatcher()
    private let spotlight = SpotlightSearch()
    private var generation = 0
    var location: Location { history.current }
    var visibleEntries: [FileEntry] { presentation.sorted }
    var groups: [(String, [FileEntry])] { presentation.groups.map { ($0.title, $0.entries) } }
    init(_ location: Location) { history = NavigationHistory(location); options = PreferenceStore.shared.folderOptions(location) }
    func stop() { generation += 1; work?.cancel(); spotlight.stop(); watcher.stop() }
    func refresh(selecting urls: [URL]) { pendingSelection = Set(urls); refresh() }
    private func resetSelection() {
        selection = []; selectionAnchor = nil; focusedURL = nil; collapsedGroups = []
        rangeBaseline = nil; pendingSelection = nil; typeAhead = TypeAheadSearch()
    }
    func navigate(_ location: Location) {
        stop(); history.navigate(location); query = ""; resetSelection()
        options = PreferenceStore.shared.folderOptions(location); refresh()
    }
    func back() { if history.canGoBack { stop(); history.back(); query = ""; resetSelection(); options = PreferenceStore.shared.folderOptions(location); refresh() } }
    func forward() { if history.canGoForward { stop(); history.forward(); query = ""; resetSelection(); options = PreferenceStore.shared.folderOptions(location); refresh() } }
    func up() {
        if case .archive(let source, let folder) = location {
            navigate(folder.isEmpty ? .folder(source.deletingLastPathComponent()) : .archive(source, folder: folder.split(separator: "/").dropLast().joined(separator: "/")))
        } else if let directory = location.directory, directory.path != "/" { navigate(.folder(directory.deletingLastPathComponent())) }
        else { navigate(.computer) }
    }
    func scheduleSearch() {
        guard !location.isArchive else { return }
        work?.cancel(); work = Task { try? await Task.sleep(for: .milliseconds(260)); guard !Task.isCancelled else { return }; refresh() }
    }
    func refresh() {
        work?.cancel(); spotlight.stop(); generation += 1
        if location.isArchive {
            watcher.stop(); entries = []; selection = []; loading = false; error = nil; warnings = []
            archiveRevision &+= 1; return
        }
        archiveItemCount = 0; archiveSelectionCount = 0
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
                            do { let part = try await self.service.list(trash, showHidden: p.showHidden); combined.entries += part.entries; combined.warnings += part.warnings }
                            catch { combined.warnings.append("\(trash.path): \(error.localizedDescription)") }
                        }
                        snapshot = combined
                    case .computer, .network, .tag, .archive: snapshot = DirectorySnapshot()
                    }
                }
                guard token == generation, !Task.isCancelled else { return }
                install(snapshot); loading = false
            } catch is CancellationError {} catch { guard token == generation else { return }; self.error = error.localizedDescription; loading = false }
        }
    }
    private func install(_ snapshot: DirectorySnapshot) {
        entries = snapshot.entries; warnings = snapshot.warnings; truncated = snapshot.truncated
        let available = Set(entries.map(\.url))
        if let pendingSelection {
            selection = pendingSelection.intersection(available); self.pendingSelection = nil
            for group in presentation.groups where group.entries.contains(where: { selection.contains($0.url) }) { collapsedGroups.remove(group.title) }
        } else { selection.formIntersection(available) }
        if let focus = focusedURL, !available.contains(focus) { focusedURL = nil }
        if let anchor = selectionAnchor, !available.contains(anchor) { selectionAnchor = nil; rangeBaseline = nil }
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
        guard descriptor >= 0 else { return }; self.url = url
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke], queue: .main)
        source.setEventHandler { Task { @MainActor in changed() } }
        source.setCancelHandler { close(descriptor) }; self.source = source; source.resume()
    }
    func stop() { source?.cancel(); source = nil; url = nil }
    deinit { source?.cancel() }
}

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
