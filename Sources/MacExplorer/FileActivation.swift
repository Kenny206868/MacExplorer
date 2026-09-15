import SwiftUI
import AppKit
import ExplorerCore

/// The native filename field owns taps and text selection while editing.
struct FileActivation: ViewModifier {
    let entry: FileEntry
    let workspace: ExplorerWorkspace
    @ObservedObject private var input = InputPreferences.shared
    @ObservedObject private var editor: FilenameEditor
    init(entry: FileEntry, workspace: ExplorerWorkspace) {
        self.entry = entry; self.workspace = workspace
        _editor = ObservedObject(wrappedValue: FilenameEditorRegistry.shared.editor(for: workspace.current))
    }
    private var editingThisItem: Bool { editor.session?.source == entry.url }
    func body(content: Content) -> some View {
        content
            // Native mouse-down owns single selection; it must not wait for a
            // competing double-tap recognizer to time out.
            .onTapGesture(count: 2) {
                if !editingThisItem && !workspace.preferences.value.singleClickOpen { workspace.activateFile(entry, doubleClick: true) }
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.65, maximumDistance: 8)
                .onEnded { _ in if input.touchFriendly && !editingThisItem { workspace.showFileActions(for: entry) } })
    }
}
