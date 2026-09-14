import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerCommands: Commands {
    @FocusedObject private var workspace: ExplorerWorkspace?
    @ObservedObject var updater: AppUpdater
    @ObservedObject private var sessions = WorkspaceSessionCoordinator.shared
    @ObservedObject private var operations = OperationCenter.shared
    @ObservedObject private var preferences = PreferenceStore.shared
    @ObservedObject private var input = InputPreferences.shared
    @Environment(\.openWindow) private var openWindow
    private var target: ExplorerWorkspace? { WorkspaceCommandScope.target(workspace) }
    private var hasSelection: Bool { target?.selected.isEmpty == false }
    private var canUndo: Bool { target != nil && !operations.undoStack.isEmpty && operations.runningCount == 0 && !operations.historyBusy }
    private var canRedo: Bool { target != nil && !operations.redoStack.isEmpty && operations.runningCount == 0 && !operations.historyBusy }
    private var canTransfer: Bool {
        guard let target else { return false }; return target.paneController?.other(than: target)?.destination != nil
    }
    var body: some Commands {
        CommandGroup(after: .appInfo) { Button("Check for Updates…") { updater.check() }.disabled(!updater.configured || !updater.canCheck) }
        CommandGroup(replacing: .newItem) { newItems }
        CommandGroup(replacing: .undoRedo) { undoItems }
        CommandGroup(replacing: .pasteboard) { clipboardItems }
        CommandMenu("File Actions") { fileActions.disabled(!hasSelection || TextEditingCommands.isEditing) }
        CommandMenu("Go") { navigationItems.disabled(target == nil) }
        CommandGroup(after: .toolbar) { viewItems }
        CommandGroup(after: .windowArrangement) { windowItems }
        CommandGroup(replacing: .help) {
            Button("Keyboard & Gestures…") { target?.sheet = .keyboardHelp }.disabled(target == nil)
            Link("MacExplorer User Guide", destination: URL(string: "https://github.com/wieslawsoltes/MacExplorer/blob/main/docs/USER-GUIDE.md")!)
            Link("Report an Issue", destination: URL(string: "https://github.com/wieslawsoltes/MacExplorer/issues")!)
        }
    }
    @ViewBuilder private var newItems: some View {
        Button("New Window") { openWindow(id: "explorer") }.keyboardShortcut("n")
        Button("New Tab") { target?.newTab() }.keyboardShortcut("t").disabled(target == nil)
        Button("Reopen Closed Tab") { target?.reopenClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(target?.closedTabs.isEmpty != false)
        Button("New Folder") { target?.sheet = .newFolder }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(target?.destination == nil)
        Divider()
        Button("Open") { target?.openSelection() }.keyboardShortcut("o").disabled(!hasSelection)
        Button("Open Folder…") { if let target { NativeIntegration.chooseFolder(owner: target) } }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(target == nil)
        Button("Close Tab") { if let target { target.closeTab(target.activeID) } }.keyboardShortcut("w").disabled(target == nil)
    }
    @ViewBuilder private var undoItems: some View {
        Button(TextEditingCommands.isEditing ? "Undo" : "Undo" + (operations.undoStack.last.map { " " + $0.title } ?? "")) {
            if !TextEditingCommands.undo(), canUndo { operations.undo() }
        }.keyboardShortcut("z").disabled(TextEditingCommands.isEditing ? TextEditingCommands.editor?.undoManager?.canUndo != true : !canUndo)
        Button(TextEditingCommands.isEditing ? "Redo" : "Redo" + (operations.redoStack.last.map { " " + $0.title } ?? "")) {
            if !TextEditingCommands.undo(redo: true), canRedo { operations.undo(redo: true) }
        }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(TextEditingCommands.isEditing ? TextEditingCommands.editor?.undoManager?.canRedo != true : !canRedo)
    }
    @ViewBuilder private var clipboardItems: some View {
        Button("Cut") { if !TextEditingCommands.send("cut:") { target?.copy(cut: true) } }.keyboardShortcut("x").disabled(!TextEditingCommands.isEditing && !hasSelection)
        Button("Copy") { if !TextEditingCommands.send("copy:") { target?.copy() } }.keyboardShortcut("c").disabled(!TextEditingCommands.isEditing && !hasSelection)
        Button("Paste") { if !TextEditingCommands.send("paste:") { target?.paste() } }.keyboardShortcut("v").disabled(!TextEditingCommands.isEditing && target?.destination == nil)
        Button("Copy as Path") { if let target { NativeIntegration.copyPaths(target.selectedURLs) } }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(!hasSelection || TextEditingCommands.isEditing)
        Divider()
        Button("Select All") { if !TextEditingCommands.send("selectAll:") { target?.selectAll() } }.keyboardShortcut("a").disabled(!TextEditingCommands.isEditing && target == nil)
        Button("Invert Selection") { target?.invertSelection() }.disabled(target == nil || TextEditingCommands.isEditing)
        Button("Clear Selection") { target?.current.selection = [] }.disabled(!hasSelection || TextEditingCommands.isEditing)
    }
    @ViewBuilder private var fileActions: some View {
        Button("Rename…") { target?.sheet = .rename }
        Button("Duplicate") { target?.duplicate() }.keyboardShortcut("d")
        Button("Move to Trash") { target?.delete() }.keyboardShortcut(.delete)
        Button("Delete Permanently…") { target?.delete(permanent: true) }.keyboardShortcut(.delete, modifiers: [.command, .shift])
        Divider()
        Button("Quick Look") { target?.quickLook() }.keyboardShortcut("y")
        Button("Properties…") { target?.sheet = .properties }.keyboardShortcut("i")
        Button("Tags…") { target?.sheet = .tags }
        Button("Compress to ZIP") { target?.compress() }
        Button("Browse / Extract Archive…") { target?.extract() }
        Divider()
        Button("Copy to Other Pane") { if let target { target.paneController?.requestTransfer(from: target, move: false) } }.keyboardShortcut("c", modifiers: [.command, .option]).disabled(!canTransfer)
        Button("Move to Other Pane…") { if let target { target.paneController?.requestTransfer(from: target, move: true) } }.keyboardShortcut("m", modifiers: [.command, .option]).disabled(!canTransfer)
    }
    @ViewBuilder private var navigationItems: some View {
        Button("Back") { target?.current.back() }.keyboardShortcut("[").disabled(target?.current.history.canGoBack != true)
        Button("Forward") { target?.current.forward() }.keyboardShortcut("]").disabled(target?.current.history.canGoForward != true)
        Button("Up") { target?.current.up() }.keyboardShortcut(.upArrow).disabled(target?.destination == nil)
        Divider()
        Button("Home") { target?.navigate(.home) }.keyboardShortcut("h", modifiers: [.command, .shift])
        Button("This Mac") { target?.navigate(.computer) }
        Button("Go to Folder…") { target?.addressFocused = true }.keyboardShortcut("l")
        Button("Search") { target?.searchFocused = true }.keyboardShortcut("f")
        Button("Connect to Server…") { target?.sheet = .connect }.keyboardShortcut("k")
        Button("Open in Terminal") { if let target, let url = target.destination { NativeIntegration.terminal(url, owner: target) } }.disabled(target?.destination == nil)
    }
    @ViewBuilder private var viewItems: some View {
        Divider()
        Toggle("Dual Panes", isOn: Binding(get: { target?.paneController != nil }, set: { _ in target?.toggleDualPane() })).keyboardShortcut("d", modifiers: [.command, .shift]).disabled(target == nil)
        Toggle("Touch-friendly Controls", isOn: $input.touchFriendly)
        Toggle("Trackpad Gestures", isOn: $input.gesturesEnabled)
        Divider()
        Toggle("Details Pane", isOn: $preferences.value.inspector)
        Toggle("Preview Pane", isOn: $preferences.value.previewPane)
        Toggle("Hidden Items", isOn: $preferences.value.showHidden).keyboardShortcut(".", modifiers: [.command, .shift])
        Toggle("File Name Extensions", isOn: $preferences.value.showExtensions)
        Toggle("Compact View", isOn: $preferences.value.compact)
        Button("Refresh") { target?.current.refresh() }.keyboardShortcut("r").disabled(target == nil)
    }
    @ViewBuilder private var windowItems: some View {
        Button("Reopen Closed Window") { if let value = sessions.reopen() { openWindow(id: "restored-session", value: value) } }.disabled(sessions.closedWindows.isEmpty)
        Button("Window History…") { openWindow(id: "session-history") }
        Divider()
        Button("Next Tab") { target?.cycleTab(1) }.keyboardShortcut("]", modifiers: [.command, .shift]).disabled(target == nil)
        Button("Previous Tab") { target?.cycleTab(-1) }.keyboardShortcut("[", modifiers: [.command, .shift]).disabled(target == nil)
        Button("Switch File Pane") { if let dual = target?.paneController { dual.focus(dual.geometry.focused.other, files: true) } }.disabled(target?.paneController == nil)
        Divider()
        Button("File Operations…") { target?.sheet = .operations }.keyboardShortcut("j").disabled(target == nil)
        Button("Recovery History…") { target?.sheet = .recovery }.disabled(target == nil)
    }
}
