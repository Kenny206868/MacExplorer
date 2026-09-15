import SwiftUI

/// Canonical presentation entry point shared by menu/keyboard routes and native
/// snapshots. The touch-action content retains FileActionSnapshot validation
/// and DeferredSheetAction's dismissal boundary before executing commands.
struct FileActionSheet: View {
    @ObservedObject var workspace: ExplorerWorkspace

    var body: some View {
        TouchFileActions(workspace: workspace)
            .accessibilityIdentifier("explorer.fileActionSheet")
    }
}
