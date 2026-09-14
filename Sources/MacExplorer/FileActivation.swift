import SwiftUI
import AppKit
import ExplorerCore

/// The filename's native field editor owns taps, text selection and composition
/// while active; the surrounding file item must not also open or start a drag.
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
            .onTapGesture(count: 2) { if !editingThisItem { workspace.activateFile(entry, doubleClick: true) } }
            .onTapGesture { if !editingThisItem { workspace.activateFile(entry) } }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.65, maximumDistance: 8)
                .onEnded { _ in if input.touchFriendly && !editingThisItem { workspace.showFileActions(for: entry) } })
    }
}
