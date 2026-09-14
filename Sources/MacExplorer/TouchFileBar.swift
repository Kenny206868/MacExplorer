import SwiftUI

/// Explicit alternatives to double-clicks, modifier keys and hover-only menus.
struct TouchFileBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    var body: some View {
        HStack(spacing: 8) {
            Button(workspace.touchSelecting ? "Done selecting" : "Select") { workspace.touchSelecting.toggle() }
                .accessibilityHint("Tap files to add or remove them from the selection")
            Spacer(minLength: 0)
            Button("Open") { workspace.openSelection() }.disabled(workspace.selected.isEmpty)
            Button { workspace.sheet = .fileActions } label: { Image(systemName: "ellipsis.circle").frame(width: 20) }
                .disabled(workspace.selected.isEmpty).accessibilityLabel("Actions for selected files")
        }.buttonStyle(ExplorerButtonStyle()).padding(.horizontal, 10).frame(height: 54)
            .background(ExplorerDesign.chrome).overlay(alignment: .top) { ExplorerRule() }
    }
}
