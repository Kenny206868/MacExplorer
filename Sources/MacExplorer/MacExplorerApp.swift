import SwiftUI
import AppKit
import Sparkle
import ExplorerCore

@main struct MacExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var preferences = PreferenceStore.shared
    @StateObject private var updater = AppUpdater()
    var body: some Scene {
        WindowGroup("MacExplorer", id: "explorer") {
            ExplorerWindow().environmentObject(preferences).environmentObject(updater)
                .preferredColorScheme(preferences.colorScheme)
        }
        .defaultSize(width: 1260, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands { ExplorerCommands(updater: updater) }
        WindowGroup("MacExplorer", id: "detached", for: BrowserSession.self) { session in
            ExplorerWindow(session: session.wrappedValue)
                .environmentObject(preferences).environmentObject(updater)
                .preferredColorScheme(preferences.colorScheme)
        }
        .defaultSize(width: 1260, height: 800)
        .windowStyle(.hiddenTitleBar)
        Settings { PreferencesView().environmentObject(preferences).environmentObject(updater).preferredColorScheme(preferences.colorScheme) }
    }
}

@MainActor final class AppUpdater: ObservableObject {
    let controller: SPUStandardUpdaterController
    let configured: Bool
    @Published var canCheck = false
    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        configured = Data(base64Encoded: key)?.count == 32 && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        if configured { controller.startUpdater() }
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }
    func check() { if configured { controller.checkForUpdates(nil) } }
    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }
}

struct WorkspaceFocusKey: FocusedValueKey { typealias Value = ExplorerWorkspace }
extension FocusedValues {
    var explorerWorkspace: ExplorerWorkspace? {
        get { self[WorkspaceFocusKey.self] }
        set { self[WorkspaceFocusKey.self] = newValue }
    }
}

struct ExplorerCommands: Commands {
    @FocusedObject(\.explorerWorkspace) private var workspace
    @ObservedObject var updater: AppUpdater
    @ObservedObject private var operations = OperationCenter.shared
    @ObservedObject private var preferences = PreferenceStore.shared
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .appInfo) { Button("Check for Updates…") { updater.check() }.disabled(!updater.configured || !updater.canCheck) }
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "explorer") }.keyboardShortcut("n")
            Button("New Tab") { workspace?.newTab() }.keyboardShortcut("t").disabled(workspace == nil)
            Button("Reopen Closed Tab") { workspace?.reopenClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(workspace?.closedTabs.isEmpty != false)
            Button("New Folder") { workspace?.sheet = .newFolder }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(workspace?.destination == nil)
            Divider()
            Button("Open") { workspace?.openSelection() }.keyboardShortcut("o").disabled(workspace?.selected.isEmpty != false)
            Button("Open Folder…") { if let workspace { NativeIntegration.chooseFolder(owner: workspace) } }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Close Tab") { if let workspace { workspace.closeTab(workspace.activeID) } }.keyboardShortcut("w")
        }
        CommandGroup(replacing: .undoRedo) {
            Button(TextEditingCommands.isEditing ? "Undo" : "Undo" + (operations.undoStack.last.map { " " + $0.title } ?? "")) { if !TextEditingCommands.undo() { operations.undo() } }.keyboardShortcut("z").disabled(TextEditingCommands.isEditing ? TextEditingCommands.editor?.undoManager?.canUndo != true : operations.undoStack.isEmpty || operations.runningCount > 0 || operations.historyBusy)
            Button(TextEditingCommands.isEditing ? "Redo" : "Redo" + (operations.redoStack.last.map { " " + $0.title } ?? "")) { if !TextEditingCommands.undo(redo: true) { operations.undo(redo: true) } }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(TextEditingCommands.isEditing ? TextEditingCommands.editor?.undoManager?.canRedo != true : operations.redoStack.isEmpty || operations.runningCount > 0 || operations.historyBusy)
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { if !TextEditingCommands.send("cut:") { workspace?.copy(cut: true) } }.keyboardShortcut("x").disabled(!TextEditingCommands.isEditing && workspace?.selected.isEmpty != false)
            Button("Copy") { if !TextEditingCommands.send("copy:") { workspace?.copy() } }.keyboardShortcut("c").disabled(!TextEditingCommands.isEditing && workspace?.selected.isEmpty != false)
            Button("Paste") { if !TextEditingCommands.send("paste:") { workspace?.paste() } }.keyboardShortcut("v").disabled(!TextEditingCommands.isEditing && workspace?.destination == nil)
            Button("Copy as Path") { if let workspace { NativeIntegration.copyPaths(workspace.selectedURLs) } }.keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Button("Select All") { if !TextEditingCommands.send("selectAll:") { workspace?.selectAll() } }.keyboardShortcut("a")
            Button("Invert Selection") { workspace?.invertSelection() }
            Button("Clear Selection") { workspace?.current.selection = [] }
        }
        CommandMenu("File Actions") {
            Button("Rename…") { workspace?.sheet = .rename }.disabled(workspace?.selected.isEmpty != false)
            Button("Duplicate") { workspace?.duplicate() }.keyboardShortcut("d")
            Button("Move to Trash") { workspace?.delete() }.keyboardShortcut(.delete)
            Button("Delete Permanently…") { workspace?.delete(permanent: true) }.keyboardShortcut(.delete, modifiers: [.command, .shift])
            Divider()
            Button("Quick Look") { workspace?.quickLook() }.keyboardShortcut("y")
            Button("Properties…") { workspace?.sheet = .properties }.keyboardShortcut("i")
            Button("Tags…") { workspace?.sheet = .tags }
            Button("Compress to ZIP") { workspace?.compress() }
            Button("Extract Archive") { workspace?.extract() }
        }
        CommandMenu("Go") {
            Button("Back") { workspace?.current.back() }.keyboardShortcut("[")
            Button("Forward") { workspace?.current.forward() }.keyboardShortcut("]")
            Button("Up") { workspace?.current.up() }.keyboardShortcut(.upArrow)
            Divider()
            Button("Home") { workspace?.navigate(.home) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("This Mac") { workspace?.navigate(.computer) }
            Button("Go to Folder…") { workspace?.addressFocused = true }.keyboardShortcut("l")
            Button("Search") { workspace?.searchFocused = true }.keyboardShortcut("f")
            Button("Connect to Server…") { workspace?.sheet = .connect }.keyboardShortcut("k")
            Button("Open in Terminal") { if let workspace, let url = workspace.destination { NativeIntegration.terminal(url, owner: workspace) } }
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Toggle("Details Pane", isOn: $preferences.value.inspector)
            Toggle("Preview Pane", isOn: $preferences.value.previewPane)
            Toggle("Hidden Items", isOn: $preferences.value.showHidden).keyboardShortcut(".", modifiers: [.command, .shift])
            Toggle("File Name Extensions", isOn: $preferences.value.showExtensions)
            Toggle("Compact View", isOn: $preferences.value.compact)
            Button("Refresh") { workspace?.current.refresh() }.keyboardShortcut("r")
        }
        CommandGroup(after: .windowArrangement) {
            Button("Next Tab") { workspace?.cycleTab(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { workspace?.cycleTab(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            Button("File Operations…") { workspace?.sheet = .operations }.keyboardShortcut("j")
            Button("Recovery History…") { workspace?.sheet = .recovery }
        }
        CommandGroup(replacing: .help) {
            Link("MacExplorer User Guide", destination: URL(string: "https://github.com/wieslawsoltes/MacExplorer/blob/main/docs/USER-GUIDE.md")!)
            Link("Report an Issue", destination: URL(string: "https://github.com/wieslawsoltes/MacExplorer/issues")!)
        }
    }
}
