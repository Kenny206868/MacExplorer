import Foundation
import AppKit
import ExplorerCore

struct BrowserReadRequest: Equatable, Sendable {
    let location: Location
    let query: String
    let allLocations: Bool
    let showHidden: Bool
    let recursive: Bool
}
private struct PreparedBrowserListing: Sendable {
    let snapshot: DirectorySnapshot
    let presentation: FilePresentation
    let navigation: FileNavigationSnapshot
}

@MainActor extension BrowserTab {
    /// Query/navigation supersedes old work immediately; watcher notifications
    /// coalesce behind useful in-flight work rather than repeatedly cancelling it.
    func cancelLoading() {
        generation &+= 1; requestSequence &+= 1
        work?.cancel(); work = nil
        searchDebounce?.cancel(); searchDebounce = nil
        refreshDebounce?.cancel(); refreshDebounce = nil
        refreshPending = false; activeRequest = nil; spotlight.stop()
    }
    func scheduleSearch() {
        guard !location.isArchive else { return }
        cancelLoading(); let expected = generation
        searchDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(260)) } catch { return }
            guard let self, expected == self.generation, !Task.isCancelled else { return }
            self.searchDebounce = nil; self.refresh()
        }
    }
    func requestFilesystemRefresh() {
        refreshPending = true
        guard work == nil, searchDebounce == nil, refreshDebounce == nil else { return }
        refreshDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.refreshDebounce = nil
            guard self.work == nil, self.searchDebounce == nil else { return }
            self.refreshPending = false; self.refresh()
        }
    }
    func refresh() {
        if location.isArchive {
            cancelLoading(); watcher.stop(); projectionTask?.cancel(); projectionTask = nil
            entries = []; selection = []; loading = false; error = nil; warnings = []; truncated = false
            archiveRevision &+= 1; return
        }
        archiveItemCount = 0; archiveSelectionCount = 0
        let preferences = PreferenceStore.shared.value
        let request = BrowserReadRequest(location: location, query: query, allLocations: allLocations,
            showHidden: preferences.showHidden, recursive: preferences.recursiveSearch)
        if work != nil && activeRequest == request { refreshPending = true; return }
        cancelLoading(); activeRequest = request; refreshStarts += 1
        let expected = generation, expression = SearchExpression(request.query)
        let root = request.location.directory ?? FileManager.default.homeDirectoryForCurrentUser
        if !loading { loading = true }
        if error != nil { error = nil }
        let spotlightSearch = !request.query.isEmpty && (request.allLocations || expression.filters["content"] != nil)
        if spotlightSearch || (request.query.isEmpty && isTagLocation(request.location)) {
            watcher.stop()
            let search = spotlightSearch ? expression : SearchExpression("tag:\"\(tagName(request.location))\"")
            spotlight.start(expression: search, root: spotlightSearch && !request.allLocations ? root : nil) { [weak self] urls, gathering in
                guard let self, expected == self.generation else { return }
                self.work?.cancel(); self.requestSequence &+= 1
                let sequence = self.requestSequence
                self.work = Task { [weak self] in
                    guard let self else { return }
                    defer { self.finishedRequest(expected, sequence: sequence, gathering: gathering) }
                    do {
                        let snapshot = try await self.service.entries(urls)
                        try await self.installRead(snapshot, generation: expected, sequence: sequence, filter: search, showHidden: request.showHidden)
                    } catch is CancellationError {} catch {
                        if expected == self.generation && sequence == self.requestSequence { self.error = error.localizedDescription }
                    }
                }
            }
            return
        }
        if let directory = request.location.directory { watcher.watch(directory) { [weak self] in self?.requestFilesystemRefresh() } }
        else { watcher.stop() }
        requestSequence &+= 1; let sequence = requestSequence
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.finishedRequest(expected, sequence: sequence, gathering: false) }
            do {
                let snapshot: DirectorySnapshot
                if !request.query.isEmpty {
                    if request.recursive { snapshot = try await self.service.search([root], expression: expression, showHidden: request.showHidden) }
                    else { snapshot = try await self.service.list(root, showHidden: request.showHidden) }
                } else {
                    switch request.location {
                    case .home: snapshot = try await self.service.recentEntries(preferences.recent)
                    case .folder(let directory): snapshot = try await self.service.list(directory, showHidden: request.showHidden)
                    case .gallery: snapshot = try await self.service.search([root], expression: expression, showHidden: request.showHidden, imagesOnly: true)
                    case .trash:
                        let directories = try await FileReadExecutor.browsing.run { cancellation in
                            var roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")]
                            let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
                            for volume in volumes where volume.path != "/" {
                                try cancellation.check(); let trash = volume.appendingPathComponent(".Trashes/\(getuid())")
                                if FileNames.exists(trash) { roots.append(trash) }
                            }
                            return roots
                        }
                        var combined = DirectorySnapshot()
                        for directory in directories {
                            try Task.checkCancellation()
                            do {
                                let part = try await self.service.list(directory, showHidden: request.showHidden)
                                combined.entries += part.entries; combined.warnings += part.warnings
                            } catch is CancellationError { throw CancellationError() }
                            catch { if combined.warnings.count < 20 { combined.warnings.append(error.localizedDescription) } }
                        }
                        snapshot = combined
                    case .computer, .network, .tag, .archive: snapshot = DirectorySnapshot()
                    }
                }
                try await self.installRead(snapshot, generation: expected, sequence: sequence,
                    filter: request.query.isEmpty || request.recursive ? nil : expression, showHidden: request.showHidden)
            } catch is CancellationError {} catch {
                if expected == self.generation && sequence == self.requestSequence { self.error = error.localizedDescription }
            }
        }
    }
    private func finishedRequest(_ expected: UInt64, sequence: UInt64, gathering: Bool) {
        guard expected == generation, sequence == requestSequence else { return }
        work = nil
        if loading != gathering { loading = gathering }
        if refreshPending { requestFilesystemRefresh() }
    }
    private func installRead(_ original: DirectorySnapshot, generation expected: UInt64, sequence: UInt64,
                             filter: SearchExpression?, showHidden: Bool) async throws {
        while expected == generation && sequence == requestSequence {
            try Task.checkCancellation()
            let configuration = options, collapsed = collapsedGroups
            let prepared = try await FileReadExecutor.presentation.run { cancellation in
                var snapshot = original
                if let filter {
                    snapshot.entries = try original.entries.enumerated().filter { index, entry in
                        if index & 255 == 0 { try cancellation.check() }
                        return filter.matches(entry) && (showHidden || !entry.isHidden)
                    }.map(\.element)
                }
                let projection = try FilePresentation(entries: snapshot.entries, options: configuration, checkingCancellation: cancellation.check)
                let visible = configuration.view == .details && !collapsed.isEmpty
                    ? projection.groups.filter { !collapsed.contains($0.title) }.flatMap(\.entries) : projection.ordered
                let navigation = FileNavigationSnapshot(entries: visible); try cancellation.check()
                return PreparedBrowserListing(snapshot: snapshot, presentation: projection, navigation: navigation)
            }
            guard expected == generation, sequence == requestSequence, !Task.isCancelled else { return }
            guard configuration == options, collapsed == collapsedGroups else { continue }
            projectionTask?.cancel(); projectionTask = nil
            installPrepared(prepared); return
        }
    }
    private func installPrepared(_ prepared: PreparedBrowserListing) {
        installingPrepared = true; entries = prepared.snapshot.entries; installingPrepared = false
        cachedPresentation = prepared.presentation; presentationBuilds += 1
        cachedNavigation = prepared.navigation; cachedSelectedEntries = nil
        hasPreparedListing = true; snapshotInstalls += 1
        if warnings != prepared.snapshot.warnings { warnings = prepared.snapshot.warnings }
        if truncated != prepared.snapshot.truncated { truncated = prepared.snapshot.truncated }
        let next = Set(prepared.presentation.selected(pendingSelection ?? selection).map(\.url))
        if selection != next { selection = next }
        if pendingSelection != nil {
            pendingSelection = nil
            for group in prepared.presentation.groups where group.entries.contains(where: { next.contains($0.url) }) { collapsedGroups.remove(group.title) }
        }
        if let focus = focusedURL, !prepared.presentation.contains(focus) { focusedURL = nil }
        if let anchor = selectionAnchor, !prepared.presentation.contains(anchor) { selectionAnchor = nil; rangeBaseline = nil }
    }
    func reorderListing() {
        projectionTask?.cancel()
        let revision = dataRevision, configuration = options, source = entries, collapsed = collapsedGroups
        projectionTask = Task { [weak self] in
            do {
                let prepared = try await FileReadExecutor.presentation.run { cancellation in
                    let projection = try FilePresentation(entries: source, options: configuration, checkingCancellation: cancellation.check)
                    let visible = configuration.view == .details && !collapsed.isEmpty
                        ? projection.groups.filter { !collapsed.contains($0.title) }.flatMap(\.entries) : projection.ordered
                    return (projection, FileNavigationSnapshot(entries: visible))
                }
                guard let self, !Task.isCancelled, revision == self.dataRevision, configuration == self.options else { return }
                self.objectWillChange.send()
                self.cachedPresentation = prepared.0; self.presentationBuilds += 1
                self.cachedNavigation = self.collapsedGroups == collapsed ? prepared.1 : nil
                self.cachedSelectedEntries = nil; self.projectionTask = nil
            } catch { /* Newer projection/navigation owns the visible state. */ }
        }
    }
    private func isTagLocation(_ location: Location) -> Bool { if case .tag = location { return true }; return false }
    private func tagName(_ location: Location) -> String { if case .tag(let value) = location { return value }; return "" }
}
