import SwiftUI
import ExplorerCore

enum ExplorerSheet: String, Identifiable { case newFolder, newFile, rename, properties, tags, connect, operations, recovery, archive, fileActions, keyboardHelp, commandPalette; var id: String { rawValue } }

struct ExplorerSheetView: View {
    let sheet: ExplorerSheet
    @ObservedObject var workspace: ExplorerWorkspace
    var body: some View {
        Group {
            switch sheet {
            case .newFolder, .newFile: NewItemSheet(workspace: workspace, folder: sheet == .newFolder)
            case .rename: RenameSheet(workspace: workspace)
            case .properties: PropertiesSheet(workspace: workspace)
            case .tags: TagsSheet(workspace: workspace)
            case .connect: ConnectSheet(workspace: workspace)
            case .operations: OperationsView(workspace: workspace)
            case .recovery: RecoveryView(workspace: workspace)
            case .fileActions: FileActionSheet(workspace: workspace)
            case .keyboardHelp: KeyboardHelpView()
            case .commandPalette: CommandPaletteView(workspace: workspace)
            case .archive: if let source = workspace.selectedURLs.first { ArchiveBrowserSheet(workspace: workspace, source: source) }
            }
        }.environmentObject(workspace.preferences).foregroundStyle(ExplorerDesign.text).background(ExplorerDesign.canvas)
    }
}
