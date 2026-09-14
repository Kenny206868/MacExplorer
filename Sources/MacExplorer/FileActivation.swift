import SwiftUI
import AppKit
import ExplorerCore

/// One activation contract for Details, list, icon, tile and Gallery items.
/// Native dragging remains a separate AppKit session; long press cancels when
/// the pointer moves beyond eight points, so it cannot become a second drop.
struct FileActivation: ViewModifier {
    let entry: FileEntry
    let workspace: ExplorerWorkspace
    @ObservedObject private var input = InputPreferences.shared
    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 2) { workspace.activateFile(entry, doubleClick: true) }
            .onTapGesture { workspace.activateFile(entry) }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.65, maximumDistance: 8)
                .onEnded { _ in if input.touchFriendly { workspace.showFileActions(for: entry) } })
    }
}
