import AppKit
import Combine
import ExplorerCore

/// Commands are identifiers, not arbitrary executable text. The palette cannot
/// evaluate shell snippets and shares the existing filesystem operation engine.
enum ExplorerCommand: String, CaseIterable, Identifiable {
    case goToFolder, newTab, dualPanes, openFolder, newFolder, newFile, open, rename
    case copy, cut, paste, copyPath, duplicate, trash, permanentDelete, quickLook, properties, tags, compress, archive, reveal
    case selectAll, invertSelection, clearSelection, selectMode
    case back, forward, up, home, computer, search, refresh, terminal, terminalOther, terminalBoth, connect
    case details, icons, gallery, hidden, extensions, previewPane, detailsPane, compact, touch, gestures
    case compareFolders, switchPane, copyOther, moveOther, swapPanes, equalPanes
    case reopenTab, undo, redo, operations, recovery, keyboard
    var id: String { rawValue }
    var spec: (title: String, category: String, symbol: String, shortcut: String, aliases: String) {
        switch self {
        case .goToFolder: return ("Go to Folder…", "Navigate", "folder", "⌘L", "address path location")
        case .newTab: return ("New Tab", "Workspace", "plus", "⌘T", "create browser")
        case .dualPanes: return ("Toggle Dual Panes", "Workspace", "rectangle.split.2x1", "⇧⌘D", "split commander side by side panels")
        case .openFolder: return ("Choose Folder…", "Navigate", "folder.badge.plus", "⇧⌘O", "open browse directory")
        case .newFolder: return ("New Folder…", "Files", "folder.badge.plus", "⇧⌘N", "create directory mkdir")
        case .newFile: return ("New Text Document…", "Files", "doc.badge.plus", "", "create file")
        case .open: return ("Open Selected Items", "Files", "arrow.up.forward.app", "↩", "launch")
        case .rename: return ("Rename", "Files", "character.cursor.ibeam", "F2", "batch filename edit")
        case .copy: return ("Copy", "Files", "doc.on.doc", "⌘C", "clipboard")
        case .cut: return ("Cut", "Files", "scissors", "⌘X", "clipboard move")
        case .paste: return ("Paste", "Files", "doc.on.clipboard", "⌘V", "clipboard")
        case .copyPath: return ("Copy as Path", "Files", "link", "⇧⌘C", "filename address clipboard")
        case .duplicate: return ("Duplicate", "Files", "plus.square.on.square", "⌘D", "copy same folder")
        case .trash: return ("Move to Trash", "Files", "trash", "⌘⌫", "delete recycle bin")
        case .permanentDelete: return ("Delete Permanently…", "Files", "trash.slash", "⇧⌘⌫", "confirm remove bypass trash")
        case .quickLook: return ("Quick Look", "Files", "eye", "Space", "preview")
        case .properties: return ("Properties…", "Files", "info.circle", "⌘I", "get info permissions size hash")
        case .tags: return ("Edit Tags…", "Files", "tag", "", "finder labels colors")
        case .compress: return ("Compress to ZIP", "Files", "archivebox", "", "archive pack")
        case .archive: return ("Browse / Extract Archive…", "Files", "archivebox", "", "unzip password decompress")
        case .reveal: return ("Reveal in Finder", "Files", "arrow.up.forward.square", "", "show original")
        case .selectAll: return ("Select All", "Selection", "checkmark.square", "⌘A", "every file")
        case .invertSelection: return ("Invert Selection", "Selection", "square.on.circle", "", "reverse toggle")
        case .clearSelection: return ("Clear Selection", "Selection", "square", "Esc", "deselect none")
        case .selectMode: return ("Toggle Modifier-free Selection", "Selection", "checkmark.circle", "", "touch multiple select mode")
        case .back: return ("Back", "Navigate", "arrow.left", "⌘[", "history previous")
        case .forward: return ("Forward", "Navigate", "arrow.right", "⌘]", "history next")
        case .up: return ("Parent Folder", "Navigate", "arrow.up", "⌘↑", "up ancestor")
        case .home: return ("Home", "Navigate", "house", "⇧⌘H", "recent quick access")
        case .computer: return ("This Mac", "Navigate", "desktopcomputer", "", "computer devices drives volumes")
        case .search: return ("Search Files", "Navigate", "magnifyingglass", "⌘F", "find query")
        case .refresh: return ("Refresh", "Navigate", "arrow.clockwise", "F5", "reload")
        case .terminal: return ("Open in Terminal", "Navigate", "terminal", "⌥⌘↩", "shell console active directory")
        case .terminalOther: return ("Open Other Pane in Terminal", "Panes", "terminal", "", "shell console opposite directory")
        case .terminalBoth: return ("Open Both Panes in Terminal", "Panes", "terminal", "⇧⌥⌘↩", "shell console left right working directories")
        case .connect: return ("Connect to Server…", "Navigate", "network", "⌘K", "smb afp nfs webdav share")
        case .details: return ("Details View", "View", "list.bullet", "", "table columns rows")
        case .icons: return ("Large Icons", "View", "square.grid.2x2", "", "grid thumbnails")
        case .gallery: return ("Gallery View", "View", "photo.on.rectangle", "", "filmstrip preview images")
        case .hidden: return ("Toggle Hidden Items", "View", "eye.slash", "⇧⌘.", "dotfiles invisible")
        case .extensions: return ("Toggle File Name Extensions", "View", "doc.text", "", "suffix types")
        case .previewPane: return ("Toggle Preview Pane", "View", "doc.viewfinder", "", "quick look sidebar")
        case .detailsPane: return ("Toggle Details Pane", "View", "sidebar.right", "", "inspector information")
        case .compact: return ("Toggle Compact View", "View", "line.3.horizontal.decrease", "", "density spacing")
        case .touch: return ("Toggle Touch-friendly Controls", "Input", "hand.tap", "", "large targets tablet")
        case .gestures: return ("Toggle Trackpad Gestures", "Input", "hand.draw", "", "swipe pinch zoom")
        case .compareFolders: return ("Compare Pane Folders…", "Panes", "doc.text.magnifyingglass", "", "differences matching metadata compare directories")
        case .switchPane: return ("Switch File Pane", "Panes", "arrow.left.arrow.right", "Tab", "focus other")
        case .copyOther: return ("Copy to Other Pane", "Panes", "doc.on.clipboard", "⌥⌘C", "transfer destination")
        case .moveOther: return ("Move to Other Pane…", "Panes", "arrow.right.doc.on.clipboard", "⌥⌘M", "transfer confirm destination")
        case .swapPanes: return ("Swap Pane Locations", "Panes", "arrow.triangle.swap", "", "exchange left right")
        case .equalPanes: return ("Equal Pane Sizes", "Panes", "rectangle.split.2x1", "", "reset divider balance")
        case .reopenTab: return ("Reopen Closed Tab", "History", "arrow.uturn.backward", "⇧⌘T", "restore")
        case .undo: return ("Undo File Operation", "History", "arrow.uturn.backward", "⌘Z", "restore recover")
        case .redo: return ("Redo File Operation", "History", "arrow.uturn.forward", "⇧⌘Z", "repeat")
        case .operations: return ("File Operations…", "History", "arrow.up.arrow.down.circle", "⌘J", "transfers progress queue pause cancel")
        case .recovery: return ("Recovery History…", "History", "clock.arrow.circlepath", "", "undo receipts restore")
        case .keyboard: return ("Keyboard & Gestures…", "Input", "keyboard", "F1", "help shortcuts")
        }
    }
    var needsFiles: Bool {
        switch self {
        case .open, .rename, .copy, .cut, .copyPath, .duplicate, .trash, .permanentDelete, .quickLook, .properties, .tags, .compress, .archive, .reveal, .copyOther, .moveOther: return true
        default: return false
        }
    }
    @MainActor func unavailable(in workspace: ExplorerWorkspace) -> String? {
        if needsFiles && workspace.selected.isEmpty { return "Select a file or folder first" }
        switch self {
        case .paste, .newFolder, .newFile, .duplicate, .compress:
            if workspace.destination == nil { return "Open a filesystem folder first" }
        case .up:
            if workspace.destination == nil && !workspace.current.location.isArchive { return "Open a folder or archive first" }
        case .details, .icons, .gallery:
            if workspace.current.location.isArchive { return "Archive members use their own file view" }
        default: break
        }
        switch self {
        case .terminal:
            return TerminalRequest.directory(for: workspace) == nil ? "Open a filesystem folder first" : nil
        case .terminalOther:
            if (try? TerminalRequest.capture(workspace, scope: .other)) == nil { return "Open a filesystem folder in the other pane" }
        case .terminalBoth:
            guard let other = workspace.paneController?.other(than: workspace) else { return "Turn on dual panes first" }
            return TerminalRequest.directory(for: workspace) == nil || TerminalRequest.directory(for: other) == nil ? "Open a filesystem folder in both panes" : nil
        case .compareFolders: return ComparisonContext.unavailable(workspace)
        case .paste: return FileClipboard.shared.contents.urls.isEmpty ? "No files on the clipboard" : nil
        case .back: return workspace.current.history.canGoBack ? nil : "No previous location"
        case .forward: return workspace.current.history.canGoForward ? nil : "No next location"
        case .reopenTab: return workspace.closedTabs.isEmpty ? "No closed tabs in this pane" : nil
        case .clearSelection: return workspace.current.selection.isEmpty ? "Nothing is selected" : nil
        case .switchPane, .equalPanes, .swapPanes, .copyOther, .moveOther:
            guard let panes = workspace.paneController else { return "Turn on dual panes first" }
            if (self == .copyOther || self == .moveOther), panes.other(than: workspace)?.destination == nil { return "Open a destination folder in the other pane" }
            if self == .swapPanes && workspace.operations.runningCount > 0 { return "Wait for active transfers to finish" }
        case .dualPanes:
            if workspace.paneController != nil && workspace.operations.runningCount > 0 { return "Finish or cancel transfers before closing a pane" }
        case .undo, .redo:
            if workspace.operations.runningCount > 0 || workspace.operations.historyBusy { return "Wait for active file operations" }
            if self == .undo && workspace.operations.undoStack.isEmpty { return "No operation to undo" }
            if self == .redo && workspace.operations.redoStack.isEmpty { return "No operation to redo" }
        default: break
        }
        return nil
    }
    @MainActor func perform(in w: ExplorerWorkspace) {
        switch self {
        case .goToFolder: w.editLocation()
        case .newTab: w.newTab()
        case .dualPanes: w.toggleDualPane()
        case .openFolder: NativeIntegration.chooseFolder(owner: w)
        case .newFolder: w.sheet = .newFolder
        case .newFile: w.sheet = .newFile
        case .open: w.openSelection()
        case .rename: w.requestRename()
        case .copy: w.copy()
        case .cut: w.copy(cut: true)
        case .paste: w.paste()
        case .copyPath: NativeIntegration.copyPaths(w.selectedURLs)
        case .duplicate: w.duplicate()
        case .trash: w.delete()
        case .permanentDelete: w.delete(permanent: true)
        case .quickLook: w.quickLook()
        case .properties: w.sheet = .properties
        case .tags: w.sheet = .tags
        case .compress: w.compress()
        case .archive: w.extract()
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting(w.selectedURLs)
        case .selectAll: w.selectAll()
        case .invertSelection: w.invertSelection()
        case .clearSelection: w.current.selection = []
        case .selectMode: w.touchSelecting.toggle()
        case .back: w.current.back()
        case .forward: w.current.forward()
        case .up: w.current.up()
        case .home: w.navigate(.home)
        case .computer: w.navigate(.computer)
        case .search: w.searchFocused = true
        case .refresh: w.current.refresh()
        case .terminal: TerminalLauncher.shared.open(from: w)
        case .terminalOther: TerminalLauncher.shared.open(from: w, scope: .other)
        case .terminalBoth: TerminalLauncher.shared.open(from: w, scope: .both)
        case .connect: w.sheet = .connect
        case .details: w.current.options.view = .details
        case .icons: w.current.options.view = .large
        case .gallery: w.current.options.view = .gallery
        case .hidden: w.preferences.value.showHidden.toggle()
        case .extensions: w.preferences.value.showExtensions.toggle()
        case .previewPane: w.preferences.value.previewPane.toggle()
        case .detailsPane: w.preferences.value.inspector.toggle()
        case .compact: w.preferences.value.compact.toggle()
        case .touch: InputPreferences.shared.touchFriendly.toggle()
        case .gestures: InputPreferences.shared.gesturesEnabled.toggle()
        case .compareFolders: w.sheet = .compareFolders
        case .switchPane: if let p = w.paneController { p.focus(p.geometry.focused.other, files: true) }
        case .copyOther: w.paneController?.requestTransfer(from: w, move: false)
        case .moveOther: w.paneController?.requestTransfer(from: w, move: true)
        case .swapPanes: w.paneController?.swapLocations()
        case .equalPanes: w.paneController?.geometry.ratio = 0.5
        case .reopenTab: w.reopenClosedTab()
        case .undo: w.operations.undo()
        case .redo: w.operations.undo(redo: true)
        case .operations: w.sheet = .operations
        case .recovery: w.sheet = .recovery
        case .keyboard: w.sheet = .keyboardHelp
        }
    }
}

@MainActor struct CommandInvocation {
    private let command: ExplorerCommand
    private weak var owner: ExplorerWorkspace?
    private let tabID: UUID
    private let location: Location
    private let files: FileActionSnapshot?
    private let clipboardGeneration: Int?
    private let otherTerminalTab: UUID?
    private let otherTerminalLocation: Location?
    init(_ command: ExplorerCommand, workspace: ExplorerWorkspace) throws {
        if let reason = command.unavailable(in: workspace) { throw ExplorerError.message(reason) }
        self.command = command; owner = workspace; tabID = workspace.current.id; location = workspace.current.location
        files = command.needsFiles ? try FileActionSnapshot(workspace) : nil
        clipboardGeneration = command == .paste ? NSPasteboard.general.changeCount : nil
        let other = (command == .terminalBoth || command == .terminalOther) ? workspace.paneController?.other(than: workspace) : nil
        otherTerminalTab = other?.current.id; otherTerminalLocation = other?.current.location
    }
    func validate() throws {
        guard let owner, owner.current.id == tabID, owner.current.location == location,
              owner.windowRoot.routedWorkspace === owner,
              clipboardGeneration == nil || clipboardGeneration == NSPasteboard.general.changeCount else {
            throw ExplorerError.message("The active pane, tab, location, or clipboard changed. Choose the command again.")
        }
        if let otherTerminalTab {
            guard let other = owner.paneController?.other(than: owner), other.current.id == otherTerminalTab,
                  other.current.location == otherTerminalLocation else {
                throw ExplorerError.message("The other pane changed. Choose the Terminal command again.")
            }
        }
        try files?.validate()
        if let reason = command.unavailable(in: owner) { throw ExplorerError.message(reason) }
    }
    func enqueue() {
        guard let owner else { return }
        DeferredSheetAction.shared.enqueue(for: owner, validate: validate) { [command] workspace in command.perform(in: workspace) }
    }
}

@MainActor final class CommandPaletteModel: ObservableObject {
    static let index = CommandSearch(ExplorerCommand.allCases.map { command in
        let spec = command.spec
        return .init(id: command.rawValue, title: spec.title, category: spec.category, aliases: spec.aliases)
    })
    @Published var query: String { didSet { filter() } }
    @Published private(set) var matches: [ExplorerCommand] = []
    @Published var selection: ExplorerCommand?
    init(query: String = "") { self.query = query; filter() }
    private func filter() { matches = Self.index.results(for: query).compactMap { ExplorerCommand(rawValue: $0.id) }; selection = matches.first }
    func move(_ offset: Int) {
        guard !matches.isEmpty else { selection = nil; return }
        let index = selection.flatMap { matches.firstIndex(of: $0) } ?? 0
        let (next, overflow) = index.addingReportingOverflow(offset)
        selection = matches[min(matches.count - 1, max(0, overflow ? (offset > 0 ? matches.count - 1 : 0) : next))]
    }
}
