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
    @Published var errors: [String] = []
    @Published var paused = false
    @Published var finished = false
    init(id: UUID = UUID(), title: String) { self.id = id; self.title = title }
    func cancel() { control.cancel(); status = "Cancelling…" }
    func togglePause() { paused.toggle(); control.setPaused(paused); status = paused ? "Paused (at the next safe checkpoint)" : "Running" }
}

struct ConflictPrompt: Identifiable {
    let id = UUID()
    let collision: FileCollision
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
    func submit(_ job: FileJob, owner: ExplorerWorkspace, completion: ((FileJobResult) -> Void)? = nil) {
        let origin = owner.current, originLocation = owner.current.location
        let row = OperationRow(id: job.id, title: job.title)
        jobs.insert(row, at: 0)
        Task {
            let result = await FileOperationEngine.shared.run(job, control: row.control, progress: { [weak row] progress in
                Task { @MainActor in row?.progress = progress; if row?.paused != true { row?.status = "Running" } }
            }, resolve: { [weak owner] collision in
                guard let owner else { return CollisionAnswer(.cancel) }
                return await owner.resolve(collision)
            })
            complete(row, result: result)
            if origin.location == originLocation { origin.revealAfterRefresh(result.outputs) }
            completion?(result)
        }
    }
    func rename(_ mapping: [(URL, String)], owner: ExplorerWorkspace) {
        let origin = owner.current, originLocation = owner.current.location
        let row = OperationRow(title: "Rename \(mapping.count) item(s)"); jobs.insert(row, at: 0)
        Task {
            let result = await FileOperationEngine.shared.rename(mapping, control: row.control)
            complete(row, result: result); if origin.location == originLocation { origin.revealAfterRefresh(result.outputs) }
        }
    }
    private func complete(_ row: OperationRow, result: FileJobResult) {
        row.errors = result.errors; row.finished = true
        row.status = result.cancelled ? "Cancelled — completed items were retained" : result.errors.isEmpty ? "Completed" : "Completed with errors"
        if !result.receipt.steps.isEmpty { undoStack.append(result.receipt); redoStack.removeAll() }
        revision += 1
        if jobs.count > 100 { jobs = Array(jobs.filter { !$0.finished } + jobs.filter(\.finished).prefix(100)) }
    }
    func undo(redo: Bool = false) {
        guard !historyBusy, runningCount == 0, let receipt = redo ? redoStack.popLast() : undoStack.popLast() else { return }
        historyBusy = true
        let row = OperationRow(title: (redo ? "Redo " : "Undo ") + receipt.title); jobs.insert(row, at: 0)
        Task {
            let result = await FileOperationEngine.shared.undo(receipt, control: row.control)
            row.finished = true; row.errors = result.errors; row.status = result.errors.isEmpty ? "Completed" : "Stopped to protect changes"
            if !result.receipt.steps.isEmpty { if redo { undoStack.append(result.receipt) } else { redoStack.append(result.receipt) } }
            if !result.remaining.isEmpty {
                let remaining = OperationReceipt(title: receipt.title, steps: result.remaining)
                if redo { redoStack.append(remaining) } else { undoStack.append(remaining) }
            }
            historyBusy = false; revision += 1
        }
    }
}

@MainActor final class FileClipboard {
    static let shared = FileClipboard()
    private var cutURLs: [URL] = []
    private var cutChangeCount = -1
    func write(_ urls: [URL], cut: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents(); pasteboard.writeObjects(urls as [NSURL])
        cutURLs = cut ? urls : []; cutChangeCount = cut ? pasteboard.changeCount : -1
    }
    var contents: (urls: [URL], isCut: Bool) {
        let p = NSPasteboard.general
        let objects = p.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        let urls = objects.map { $0 as URL }
        return (urls, p.changeCount == cutChangeCount && !cutURLs.isEmpty && Set(urls) == Set(cutURLs))
    }
    func consumeCut() { cutURLs = []; cutChangeCount = -1 }
    func consumeCompletedMoves(_ urls: [URL], generation: Int) {
        guard NSPasteboard.general.changeCount == generation, generation == cutChangeCount else { return }
        let remaining = urls.filter { FileNames.exists($0) }
        if remaining.isEmpty { consumeCut() } else { write(remaining, cut: true) }
    }
}

struct MessageBox: Identifiable { let id = UUID(); let title: String; let message: String }
enum ExplorerSheet: String, Identifiable { case newFolder, newFile, rename, properties, tags, connect, operations, recovery; var id: String { rawValue } }

@MainActor final class ExplorerWorkspace: ObservableObject, Identifiable {
    let id = UUID()
    @Published var tabs: [BrowserTab]
    @Published var activeID: UUID
    var closedTabs: [BrowserTab] = []
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
    var selected: [FileEntry] { current.entries.filter { current.selection.contains($0.url) } }
    var selectedURLs: [URL] { selected.map(\.url) }
    var destination: URL? { current.location.directory }
    init() {
        let p = PreferenceStore.shared
        let locations: [Location] = p.value.restoreTabs && !p.value.tabs.isEmpty ? p.value.tabs : [p.value.startLocation == "This Mac" ? .computer : .home]
        let initial = locations.prefix(20).map { BrowserTab($0) }
        tabs = initial; activeID = initial[0].id
    }
    func saveSession() { preferences.value.tabs = tabs.map(\.location) }
    func newTab(_ location: Location? = nil) { let tab = BrowserTab(location ?? .home); tabs.append(tab); activeID = tab.id; saveSession() }
    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs.count == 1 { window?.performClose(nil); return }
        tabs[index].stop(); closedTabs.append(tabs[index]); closedTabs = Array(closedTabs.suffix(20)); tabs.remove(at: index)
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
            else { navigate(.folder(url.deletingLastPathComponent())); current.revealAfterRefresh([url]) }
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
    func paste(to folder: URL? = nil, forceMove: Bool = false) {
        guard let destination = folder ?? destination else { fail("Choose a folder", "Navigate to a writable folder before pasting."); return }
        let clipboard = FileClipboard.shared.contents
        guard !clipboard.urls.isEmpty else { return }
        let generation = NSPasteboard.general.changeCount
        operations.submit(FileJob(clipboard.isCut || forceMove ? .move : .copy, sources: clipboard.urls, destination: destination), owner: self) { _ in
            if clipboard.isCut { FileClipboard.shared.consumeCompletedMoves(clipboard.urls, generation: generation) }
        }
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
    func resolve(_ collision: FileCollision) async -> CollisionAnswer {
        guard window?.isVisible == true else { return CollisionAnswer(.cancel) }
        sheet = nil
        return await withCheckedContinuation { continuation in conflict = ConflictPrompt(collision: collision, continuation: continuation) }
    }
    func answerCollision(_ choice: CollisionChoice, all: Bool = false) {
        guard let prompt = conflict else { return }; conflict = nil
        prompt.continuation.resume(returning: CollisionAnswer(choice, applyToAll: all))
    }
    func select(_ url: URL, extend: Bool, range: Bool) {
        var state = current.selectionState
        state.click(url, in: current.displayEntries.map(\.url), toggle: extend, range: range)
        current.selectionState = state
    }
    func selectAll() { current.selection = Set(current.visibleEntries.map(\.url)) }
    func invertSelection() { current.selection = Set(current.visibleEntries.map(\.url)).subtracting(current.selection) }
    func moveSelection(_ offset: Int, extend: Bool = false) {
        var state = current.selectionState
        state.move(by: offset, in: current.displayEntries.map(\.url), extend: extend)
        current.selectionState = state
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
