import SwiftUI
import AppKit
import ExplorerCore

@MainActor final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var history: NavigationHistory
    @Published var entries: [FileEntry] = [] {
        didSet { cachedSelectionStatistics = nil; dataRevision &+= 1; if !installingPrepared { hasPreparedListing = false; invalidatePresentation() } }
    }
    @Published var selection: Set<URL> = [] { didSet { cachedSelectedEntries = nil; cachedSelectionStatistics = nil } }
    @Published var collapsedGroups: Set<String> = [] { didSet { invalidateNavigation() } }
    @Published var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    @Published var allLocations = false { didSet { if allLocations != oldValue { scheduleSearch() } } }
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
            if options.sort != oldValue.sort || options.descending != oldValue.descending || options.foldersFirst != oldValue.foldersFirst || options.group != oldValue.group {
                if hasPreparedListing { reorderListing() } else { invalidatePresentation() }
            }
            if options.group != oldValue.group { collapsedGroups = [] }
            if options.view != oldValue.view { invalidateNavigation() }
            PreferenceStore.shared.remember(location, options)
        }
    }
    var cachedPresentation: FilePresentation?
    var presentationBuilds = 0
    private var presentation: FilePresentation {
        if let cachedPresentation { return cachedPresentation }
        let value = FilePresentation(entries: entries, options: options)
        cachedPresentation = value; presentationBuilds += 1; return value
    }
    func invalidatePresentation() { cachedPresentation = nil; cachedSelectedEntries = nil; invalidateNavigation() }
    var cachedSelectedEntries: [FileEntry]?
    private(set) var selectedProjectionBuilds = 0
    var selectedEntries: [FileEntry] {
        if let cachedSelectedEntries { return cachedSelectedEntries }
        let result = presentation.selected(selection)
        cachedSelectedEntries = result; selectedProjectionBuilds += 1; return result
    }
    private var cachedSelectionStatistics: SelectionStatistics?
    private(set) var selectionStatisticsBuilds = 0
    var selectionStatistics: SelectionStatistics {
        if let cachedSelectionStatistics { return cachedSelectionStatistics }
        var result = SelectionStatistics()
        for entry in selectedEntries { result.include(isDirectory: entry.isDirectory, byteCount: entry.size) }
        cachedSelectionStatistics = result; selectionStatisticsBuilds += 1
        return result
    }
    var cachedNavigation: FileNavigationSnapshot?
    private(set) var navigationBuilds = 0
    private func invalidateNavigation() { cachedNavigation = nil }
    var navigation: FileNavigationSnapshot {
        if let cachedNavigation { return cachedNavigation }
        let entries = options.view == .details && !collapsedGroups.isEmpty
            ? presentation.groups.filter { !collapsedGroups.contains($0.title) }.flatMap(\.entries) : presentation.ordered
        let value = FileNavigationSnapshot(entries: entries)
        cachedNavigation = value; navigationBuilds += 1; return value
    }
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
    var pendingSelection: Set<URL>?
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
    var work: Task<Void, Never>?
    var searchDebounce: Task<Void, Never>?
    var refreshDebounce: Task<Void, Never>?
    var projectionTask: Task<Void, Never>?
    let watcher = DirectoryWatcher()
    let spotlight = SpotlightSearch()
    var generation: UInt64 = 0
    var requestSequence: UInt64 = 0
    @Published var selectionMatching = false
    var selectionWork: Task<Void, Never>?
    var selectionWorkID: UUID?
    var dataRevision: UInt64 = 0
    var refreshPending = false
    var installingPrepared = false
    var hasPreparedListing = false
    var activeRequest: BrowserReadRequest?
    var refreshStarts = 0
    var snapshotInstalls = 0
    var location: Location { history.current }
    var visibleEntries: [FileEntry] { presentation.sorted }
    var groups: [(String, [FileEntry])] { presentation.groups.map { ($0.title, $0.entries) } }
    init(_ location: Location) { history = NavigationHistory(location); options = PreferenceStore.shared.folderOptions(location) }
    func stop() { cancelSelectionWork(); cancelLoading(); projectionTask?.cancel(); projectionTask = nil; watcher.stop() }
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
}
