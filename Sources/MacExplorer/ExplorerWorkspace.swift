import SwiftUI
import Combine
import AppKit
import ExplorerCore

/// One independent tab group. A window may host two groups; file commands never
/// look through to another group's current tab to resolve their source files.
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
    @Published var dualPane: DualPaneController?
    @Published var pendingPaneTransfer: PaneTransferRequest?
    @Published var touchSelecting = false
    var retainedCompanion: CompanionSession?
    weak var parentWorkspace: ExplorerWorkspace?
    var fileSurfaceFocused = true
    var fileViewportHeight: Double = 500
    weak var window: NSWindow?
    var restorationFrame: CGRect?
    let preferences = PreferenceStore.shared
    let operations = OperationCenter.shared
    var current: BrowserTab { tabs.first(where: { $0.id == activeID }) ?? tabs[0] }
    var selected: [FileEntry] { current.selectedEntries }
    var selectedURLs: [URL] { selected.map(\.url) }
    var destination: URL? { current.location.directory }
    init(session: BrowserSession? = nil, windowSession: WindowSession? = nil) {
        if let session {
            let tab = BrowserTab(session.history.current)
            tabs = [tab]; activeID = tab.id; tab.restore(session); observeCurrentTab(); return
        }
        let p = PreferenceStore.shared
        let initialChoice = windowSession.map(WorkspaceSessionCoordinator.InitialWindow.restored)
            ?? WorkspaceSessionCoordinator.shared.claimInitialWindow(restore: p.value.restoreTabs)
        if case .restored(let saved) = initialChoice {
            let restored = saved.tabs.map { value -> BrowserTab in let tab = BrowserTab(value.history.current); tab.restore(value); return tab }
            tabs = restored; activeID = restored[saved.activeIndex].id
            closedTabs = saved.closedTabs; restorationFrame = saved.frame
            observeCurrentTab()
            if let companion = saved.companion { dualPane = DualPaneController(primary: self, session: companion) }
            return
        }
        let useLegacy: Bool
        if case .legacy = initialChoice { useLegacy = true } else { useLegacy = false }
        let locations: [Location] = useLegacy && !p.value.tabs.isEmpty ? p.value.tabs : [p.value.startLocation == "This Mac" ? .computer : .home]
        let initial = locations.prefix(20).map { BrowserTab($0) }
        tabs = initial; activeID = initial[0].id; observeCurrentTab()
    }
    private func observeCurrentTab() { tabObservation = current.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }
    func saveSession() { WorkspaceSessionCoordinator.shared.record(windowRoot) }
    func newTab(_ location: Location? = nil) { let tab = BrowserTab(location ?? .home); tabs.append(tab); activeID = tab.id; saveSession() }
    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs.count == 1 {
            if parentWorkspace != nil { windowRoot.toggleDualPane() }
            else { window?.performClose(nil) }
            return
        }
        closedTabs.append(tabs[index].session()); if closedTabs.count > 30 { closedTabs.removeFirst() }
        tabs[index].stop(); tabs.remove(at: index)
        if activeID == id { activeID = tabs[min(index, tabs.count - 1)].id }; saveSession()
    }
    func navigate(_ location: Location, newTab: Bool = false) { if newTab { self.newTab(location) } else { current.navigate(location); saveSession() } }
    func open(_ entry: FileEntry) {
        if entry.canBrowse { navigate(.folder(entry.url)) }
        else { preferences.visit(entry.url); if !NSWorkspace.shared.open(entry.url) { fail("Open failed", "No application could open \(entry.name).") } }
    }
    func openSelection() {
        let entries = selected
        if entries.count == 1 { open(entries[0]) }
        else { for entry in entries { if entry.canBrowse { newTab(.folder(entry.url)) } else { open(entry) } } }
    }
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
    func confirmDeletion() { let urls = pendingDeletion; pendingDeletion = []; operations.submit(FileJob(permanentDeletion ? .delete : .trash, sources: urls), owner: self) }
    func compress() { guard !selectedURLs.isEmpty, let destination else { return }; operations.submit(FileJob(.compress, sources: selectedURLs, destination: destination), owner: self) }
    func extract() { guard !selectedURLs.isEmpty else { return }; sheet = .archive }
    func alias() { guard let destination else { return }; operations.submit(FileJob(.symbolicLink, sources: selectedURLs, destination: destination, names: Dictionary(uniqueKeysWithValues: selectedURLs.map { ($0.path, $0.lastPathComponent + " link") })), owner: self) }
    func quickLook() { current.previewURL = selectedURLs.first }
    func fail(_ title: String, _ text: String) { activatePane(); message = MessageBox(title: title, message: text) }
    func resolve(_ collision: FileCollision, operationID: UUID, control: OperationControl) async -> CollisionAnswer {
        guard !control.isCancelled, window?.isVisible == true else { return CollisionAnswer(.cancel) }
        activatePane(); sheet = nil
        return await withCheckedContinuation { continuation in conflict = ConflictPrompt(collision: collision, operationID: operationID, continuation: continuation) }
    }
    func answerCollision(_ choice: CollisionChoice, all: Bool = false) {
        guard let prompt = conflict else { return }; conflict = nil
        prompt.continuation.resume(returning: CollisionAnswer(choice, applyToAll: all))
    }
    func drop(_ providers: [NSItemProvider], to folder: URL, move: Bool) -> Bool {
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        guard !accepted.isEmpty else { return false }
        // The destination and owning pane are captured before asynchronous loads.
        let destinationIdentity = try? FileFingerprint(folder)
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
            guard !urls.isEmpty else { return }
            guard destinationIdentity?.matchesIdentity(folder) == true else { fail("Drop stopped", "The destination folder changed while the dragged files were being received."); return }
            transfer(to: folder, move: move, urls: urls)
        }
        return true
    }
}
