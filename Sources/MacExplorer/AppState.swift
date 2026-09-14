import SwiftUI
import Combine
import AppKit
import ExplorerCore

struct Preferences: Codable {
    var showHidden = false
    var showExtensions = true
    var checkboxes = false
    var compact = false
    var inspector = true
    var previewPane = false
    var singleClickOpen = false
    var restoreTabs = true
    var confirmTrash = false
    var theme = "system"
    var startLocation = "Home"
    var recursiveSearch = true
    var folders: [String: FolderOptions] = [:]
    var pins: [Bookmark] = ["Desktop", "Downloads", "Documents", "Pictures"].map { Bookmark(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0)) }
    var recent: [Bookmark] = []
    var savedSearches: [String] = []
    var tabs: [Location] = [.home]
}

@MainActor final class PreferenceStore: ObservableObject {
    static let shared = PreferenceStore()
    @Published var value: Preferences { didSet { save() } }
    private let key = "MacExplorer.preferences.v1"
    init() {
        value = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
    }
    private func save() { if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) } }
    func pin(_ url: URL) { if !value.pins.contains(where: { $0.url == url }) { value.pins.append(Bookmark(url)) } }
    func unpin(_ url: URL) { value.pins.removeAll { $0.url == url } }
    func visit(_ url: URL) { value.recent.removeAll { $0.url == url }; value.recent.insert(Bookmark(url), at: 0); value.recent = Array(value.recent.prefix(200)) }
    func folderOptions(_ location: Location) -> FolderOptions { value.folders[location.directory?.path ?? location.title] ?? FolderOptions() }
    func remember(_ location: Location, _ options: FolderOptions) { value.folders[location.directory?.path ?? location.title] = options }
    var colorScheme: ColorScheme? { value.theme == "dark" ? .dark : value.theme == "light" ? .light : nil }
}

@MainActor final class OperationRow: ObservableObject, Identifiable {
    let id: UUID
    let title: String
    let started = Date()
    let control = OperationControl()
    @Published var progress = FileProgress(completed: 0, total: 1, name: "Queued")
    @Published var status = "Queued"
    @Published var statistics = TransferStatistics()
    var cancellationAction: (() -> Void)?
    @Published var errors: [String] = []
    @Published var paused = false
    @Published var finished = false
    @Published var cancelled = false
    init(id: UUID = UUID(), title: String) { self.id = id; self.title = title }
    func cancel() { control.cancel(); statistics.suspend(); status = "Cancelling…"; cancellationAction?() }
    func acceptProgress(_ value: FileProgress) {
        guard !finished, value.sequence >= progress.sequence, value.timestamp >= progress.timestamp else { return }
        if value.phase != .copying || progress.phase != .copying { statistics.suspend() }
        progress = value
        statistics.record(bytes: value.bytes, at: value.timestamp, paused: paused || value.phase != .copying)
        if !paused && !control.isCancelled { status = value.phase.rawValue }
    }
    func togglePause() { paused.toggle(); statistics.suspend(); control.setPaused(paused); status = paused ? "Paused (at the next safe checkpoint)" : "Running" }
}

struct ConflictPrompt: Identifiable {
    let id = UUID()
    let collision: FileCollision
    let operationID: UUID
    let continuation: CheckedContinuation<CollisionAnswer, Never>
}

@MainActor final class OperationCenter: ObservableObject {
    static let shared = OperationCenter()
    @Published var jobs: [OperationRow] = []
    @Published var undoStack: [OperationReceipt] = []
    @Published var redoStack: [OperationReceipt] = []
    @Published var revision = 0
    @Published var historyBusy = false
    var runningCount: Int { jobs.filter { !$0.finished }.count }
    func submit(_ job: FileJob, owner: ExplorerWorkspace, cutTicket: FileClipboard.CutTicket? = nil, completion: ((FileJobResult) -> Void)? = nil) {
        let origin = owner.current, location = owner.current.location
        let row = OperationRow(id: job.id, title: job.title)
        let control = row.control
        jobs.insert(row, at: 0)
        row.cancellationAction = { [weak owner] in
            if owner?.conflict?.operationID == job.id { owner?.answerCollision(.cancel) }
        }
        Task {
            let result = await FileOperationEngine.shared.run(job, control: row.control, progress: { [weak row] progress in
                Task { @MainActor in
                    guard let row, !row.finished else { return }
                    row.acceptProgress(progress)
                }
            }, resolve: { [weak owner] collision in
                guard let owner else { return CollisionAnswer(.cancel) }
                return await owner.resolve(collision, operationID: job.id, control: control)
            })
            complete(row, result: result)
            if let cutTicket { FileClipboard.shared.finish(cutTicket, moved: result.completedSources) }
            completion?(result)
            if origin.location == location { if result.outputs.isEmpty { origin.refresh() } else { origin.refresh(selecting: result.outputs) } }
        }
    }
    func rename(_ mapping: [(URL, String)], owner: ExplorerWorkspace) {
        let origin = owner.current, location = owner.current.location
        let row = OperationRow(title: "Rename \(mapping.count) item(s)"); jobs.insert(row, at: 0)
        Task {
            let result = await FileOperationEngine.shared.rename(mapping, control: row.control)
            complete(row, result: result)
            if origin.location == location { if result.outputs.isEmpty { origin.refresh() } else { origin.refresh(selecting: result.outputs) } }
        }
    }
    private func complete(_ row: OperationRow, result: FileJobResult) {
        if let final = result.finalProgress { row.acceptProgress(final) }
        row.cancellationAction = nil
        row.paused = false; row.control.setPaused(false); row.cancelled = result.cancelled || row.control.isCancelled
        row.errors = result.errors; row.finished = true
        row.status = result.cancelled ? "Cancelled — completed items were retained" : result.errors.isEmpty ? "Completed" : "Completed with errors"
        if !result.skippedSources.isEmpty { row.status += " — \(result.skippedSources.count) skipped" }
        if !result.receipt.steps.isEmpty { undoStack.append(result.receipt); redoStack.removeAll() }
        revision += 1
        // Never discard active jobs or recovery receipts while trimming presentation history.
        if jobs.count > 100 { jobs = Array(jobs.filter { !$0.finished } + jobs.filter(\.finished).prefix(100)) }
    }
    func undo(redo: Bool = false) {
        guard !historyBusy, runningCount == 0, let receipt = redo ? redoStack.popLast() : undoStack.popLast() else { return }
        historyBusy = true
        let row = OperationRow(title: (redo ? "Redo " : "Undo ") + receipt.title); jobs.insert(row, at: 0)
        Task {
            let result = await FileOperationEngine.shared.undo(receipt, control: row.control)
            row.cancelled = result.cancelled || row.control.isCancelled
            row.finished = true; row.errors = result.errors; row.status = result.errors.isEmpty ? "Completed" : "Stopped to protect changes"
            if !result.receipt.steps.isEmpty { if redo { undoStack.append(result.receipt) } else { redoStack.append(result.receipt) } }
            if !result.remaining.isEmpty {
                var remaining = OperationReceipt(title: receipt.title, steps: result.remaining)
                remaining.renameBatch = receipt.renameBatch
                if redo { redoStack.append(remaining) } else { undoStack.append(remaining) }
            }
            historyBusy = false; revision += 1
        }
    }
}

struct MessageBox: Identifiable { let id = UUID(); let title: String; let message: String }
enum ExplorerSheet: String, Identifiable { case newFolder, newFile, rename, properties, tags, connect, operations, recovery; var id: String { rawValue } }

@MainActor final class ExplorerWorkspace: ObservableObject, Identifiable {
    let id = UUID()
    @Published var tabs: [BrowserTab]
    @Published var activeID: UUID { didSet { observeCurrentTab() } }
    private var tabObservation: AnyCancellable?
    @Published var closedTabs: [BrowserSession] = []
    @Published var sheet: ExplorerSheet?
    @Published var message: MessageBox?
    @Published var conflict: ConflictPrompt?
    @Published var pendingDeletion: [URL] = []
    @Published var permanentDeletion = false
    @Published var addressFocused = false
    @Published var searchFocused = false
    @Published var selectedInspector = "Details"
    weak var window: NSWindow?
    let preferences = PreferenceStore.shared
    let operations = OperationCenter.shared
    var current: BrowserTab { tabs.first(where: { $0.id == activeID }) ?? tabs[0] }
    var selected: [FileEntry] { current.displayEntries.filter { current.selection.contains($0.url) } }
    var selectedURLs: [URL] { selected.map(\.url) }
    var destination: URL? { current.location.directory }
    init(session: BrowserSession? = nil) {
        if let session {
            let tab = BrowserTab(session.history.current)
            tabs = [tab]; activeID = tab.id
            tab.restore(session)
            observeCurrentTab()
            return
        }
        let p = PreferenceStore.shared
        let locations: [Location] = p.value.restoreTabs && !p.value.tabs.isEmpty ? p.value.tabs : [p.value.startLocation == "This Mac" ? .computer : .home]
        let initial = locations.prefix(20).map { BrowserTab($0) }
        tabs = initial; activeID = initial[0].id
        observeCurrentTab()
    }
    private func observeCurrentTab() {
        tabObservation = current.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    func saveSession() { preferences.value.tabs = tabs.map(\.location) }
    func newTab(_ location: Location? = nil) { let tab = BrowserTab(location ?? .home); tabs.append(tab); activeID = tab.id; saveSession() }
    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs.count == 1 { window?.performClose(nil); return }
        closedTabs.append(tabs[index].session())
        if closedTabs.count > 30 { closedTabs.removeFirst() }
        tabs[index].stop(); tabs.remove(at: index)
        if activeID == id { activeID = tabs[min(index, tabs.count - 1)].id }
        saveSession()
    }
    func navigate(_ location: Location, newTab: Bool = false) { if newTab { self.newTab(location) } else { current.navigate(location); saveSession() } }
    func open(_ entry: FileEntry) {
        if entry.canBrowse { navigate(.folder(entry.url)) }
        else { preferences.visit(entry.url); if !NSWorkspace.shared.open(entry.url) { fail("Open failed", "No application could open \(entry.name).") } }
    }
    func openSelection() { let entries = selected; if entries.count == 1 { open(entries[0]) } else { for entry in entries { if entry.canBrowse { newTab(.folder(entry.url)) } else { open(entry) } } } }
    func openURLs(_ urls: [URL]) {
        for url in urls {
            if let entry = try? FileEntry(url: url), entry.canBrowse { navigate(.folder(url), newTab: !current.entries.isEmpty) }
            else { navigate(.folder(url.deletingLastPathComponent())); current.refresh(selecting: [url]) }
        }
    }
    func goToAddress(_ text: String) {
        if let url = URL(string: text), ["smb", "afp", "nfs", "https"].contains(url.scheme?.lowercased() ?? "") { NativeIntegration.connect(text, owner: self); return }
        let path = (text as NSString).expandingTildeInPath
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : (destination ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent(path)
        do { let entry = try FileEntry(url: url); if entry.canBrowse { navigate(.folder(url)) } else { open(entry) } }
        catch { fail("Location unavailable", error.localizedDescription) }
    }
    func copy(cut: Bool = false) { guard !selectedURLs.isEmpty else { return }; FileClipboard.shared.write(selectedURLs, cut: cut) }
    func paste(to folder: URL? = nil) {
        guard let destination = folder ?? destination else { fail("Choose a folder", "Navigate to a writable folder before pasting."); return }
        let clipboard = FileClipboard.shared.contents
        guard !clipboard.urls.isEmpty else { return }
        let ticket = clipboard.isCut ? FileClipboard.shared.reserveCut() : nil
        guard !clipboard.isCut || ticket != nil else { return }
        operations.submit(FileJob(clipboard.isCut ? .move : .copy, sources: clipboard.urls, destination: destination), owner: self, cutTicket: ticket)
    }
    func transfer(to folder: URL, move: Bool, urls: [URL]? = nil) { operations.submit(FileJob(move ? .move : .copy, sources: urls ?? selectedURLs, destination: folder), owner: self) }
    func duplicate() { guard let destination else { return }; operations.submit(FileJob(.copy, sources: selectedURLs, destination: destination), owner: self) }
    func delete(permanent: Bool = false) {
        guard !selectedURLs.isEmpty else { return }
        if permanent || current.location == .trash || preferences.value.confirmTrash { pendingDeletion = selectedURLs; permanentDeletion = permanent || current.location == .trash }
        else { operations.submit(FileJob(.trash, sources: selectedURLs), owner: self) }
    }
    func confirmDeletion() {
        let urls = pendingDeletion; pendingDeletion = []
        operations.submit(FileJob(permanentDeletion ? .delete : .trash, sources: urls), owner: self)
    }
    func compress() { guard !selectedURLs.isEmpty, let destination else { return }; operations.submit(FileJob(.compress, sources: selectedURLs, destination: destination), owner: self) }
    func extract() { guard let first = selectedURLs.first, let destination else { return }; operations.submit(FileJob(.extract, sources: [first], destination: destination), owner: self) }
    func alias() { guard let destination else { return }; operations.submit(FileJob(.symbolicLink, sources: selectedURLs, destination: destination, names: Dictionary(uniqueKeysWithValues: selectedURLs.map { ($0.path, $0.lastPathComponent + " link") })), owner: self) }
    func quickLook() { current.previewURL = selectedURLs.first }
    func fail(_ title: String, _ text: String) { message = MessageBox(title: title, message: text) }
    func resolve(_ collision: FileCollision, operationID: UUID, control: OperationControl) async -> CollisionAnswer {
        guard !control.isCancelled else { return CollisionAnswer(.cancel) }
        // Never suspend the global operation queue behind a prompt in a closed window.
        guard window?.isVisible == true else { return CollisionAnswer(.cancel) }
        sheet = nil
        return await withCheckedContinuation { continuation in conflict = ConflictPrompt(collision: collision, operationID: operationID, continuation: continuation) }
    }
    func answerCollision(_ choice: CollisionChoice, all: Bool = false) {
        guard let prompt = conflict else { return }; conflict = nil
        prompt.continuation.resume(returning: CollisionAnswer(choice, applyToAll: all))
    }
    func drop(_ providers: [NSItemProvider], to folder: URL, move: Bool) -> Bool {
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        guard !accepted.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in accepted {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { object, _ in
                        if let url = object as? URL { continuation.resume(returning: url) }
                        else if let data = object as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                if let url, url.isFileURL { urls.append(url) }
            }
            if !urls.isEmpty { transfer(to: folder, move: move, urls: urls) }
        }
        return true
    }
}
