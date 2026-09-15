import AppKit
import ExplorerCore

/// UI buttons, optional function keys and power menus share one guarded route.
/// No action ever substitutes the opposite pane's selection as its source.
enum CommanderAction: String, CaseIterable, Identifiable {
    case quickLook, edit, copy, move, newFolder, trash
    case selectMask, invert, sameExtension, compare, rename, pack, extract, settings
    var id: String { rawValue }
    static let functionActions: [Self] = [.quickLook, .edit, .copy, .move, .newFolder, .trash]
    static func functionKey(_ keyCode: UInt16) -> Self? {
        switch keyCode { case 99: return .quickLook; case 118: return .edit; case 96: return .copy; case 97: return .move; case 98: return .newFolder; case 100: return .trash; default: return nil }
    }
    var key: String { Self.functionActions.firstIndex(of: self).map { "F\($0 + 3)" } ?? "" }
    var title: String {
        switch self {
        case .quickLook: return "View"; case .edit: return "Edit"; case .copy: return "Copy"; case .move: return "Move…"
        case .newFolder: return "New Folder…"; case .trash: return "Trash…"; case .selectMask: return "Select by Pattern…"
        case .invert: return "Invert Selection"; case .sameExtension: return "Select Same Extension"
        case .compare: return "Compare Folders…"; case .rename: return "Multi-Rename…"
        case .pack: return "Compress to ZIP"; case .extract: return "Browse / Extract Archive…"; case .settings: return "Commander Settings…"
        }
    }
    var symbol: String {
        switch self {
        case .quickLook: return "eye"; case .edit: return "pencil"; case .copy: return "doc.on.doc"; case .move: return "arrow.right.doc.on.clipboard"
        case .newFolder: return "folder.badge.plus"; case .trash: return "trash"; case .selectMask: return "line.3.horizontal.decrease.circle"
        case .invert: return "square.on.circle"; case .sameExtension: return "doc.on.doc.fill"; case .compare: return "doc.text.magnifyingglass"
        case .rename: return "character.cursor.ibeam"; case .pack, .extract: return "archivebox"; case .settings: return "slider.horizontal.3"
        }
    }
    @MainActor func enabled(in workspace: ExplorerWorkspace) -> Bool {
        guard WorkspaceCommandScope.target(workspace) === workspace else { return false }
        if self == .settings { return true }
        guard !workspace.current.location.isArchive else { return false }
        switch self {
        case .quickLook, .trash, .rename: return !workspace.selected.isEmpty
        case .edit: return workspace.selected.count == 1 && workspace.selected.allSatisfy { !$0.isDirectory && !$0.isPackage }
        case .copy, .move: return workspace.paneController?.preparingTransfer == false && !workspace.selected.isEmpty && workspace.paneController?.other(than: workspace)?.destination != nil
        case .newFolder: return workspace.destination != nil
        case .selectMask, .invert: return !workspace.current.navigation.entries.isEmpty
        case .sameExtension: return workspace.selected.count == 1 && workspace.selected.first?.isDirectory == false
        case .compare: return workspace.destination != nil && workspace.paneController?.other(than: workspace)?.destination != nil
        case .pack: return !workspace.selected.isEmpty && workspace.destination != nil
        case .extract: return workspace.selected.count == 1 && workspace.selected.first?.isDirectory == false
        case .settings: return true
        }
    }
    @MainActor func perform(in workspace: ExplorerWorkspace) {
        guard enabled(in: workspace) else { return }
        switch self {
        case .quickLook: workspace.quickLook()
        case .edit:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
                workspace.fail("Editor unavailable", "TextEdit is not installed on this Mac."); return
            }
            NativeIntegration.openWith(workspace.selectedURLs, application: app, owner: workspace)
        case .copy, .move: workspace.paneController?.requestTransfer(from: workspace, move: self == .move)
        case .newFolder: workspace.sheet = .newFolder
        case .trash: workspace.delete()
        case .selectMask: workspace.sheet = .selectionMask
        case .invert: workspace.invertSelection()
        case .sameExtension:
            guard let entry = workspace.selected.first else { return }
            workspace.current.selectSameExtension(entry.url.pathExtension)
        case .compare: workspace.sheet = .compareFolders
        case .rename: workspace.sheet = .rename
        case .pack: workspace.compress()
        case .extract: workspace.sheet = .archive
        case .settings: workspace.sheet = .commanderSettings
        }
    }
}
