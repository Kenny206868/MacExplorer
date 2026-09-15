import AppKit
import ExplorerCore

enum WindowChromeAction: String, CaseIterable {
    case back, forward, up, refresh, new, newFolder, newFile, cut, copy, paste, trash, rename
    case view, details, icons, dual, inspector, preview, share, operations, properties, keyboard, more, commands
    case hidden, extensions, checkboxes, compact, recovery, terminal, power, workspace
    var title: String {
        switch self {
        case .back: return "Back"; case .forward: return "Forward"; case .up: return "Enclosing Folder"; case .refresh: return "Refresh"
        case .new: return "New"; case .newFolder: return "New Folder…"; case .newFile: return "New Text Document…"
        case .cut: return "Cut"; case .copy: return "Copy"; case .paste: return "Paste"; case .trash: return "Move to Trash"; case .rename: return "Rename…"
        case .view: return "View and Sort"; case .details: return "Details View"; case .icons: return "Icon View"; case .dual: return "Dual Panes"
        case .inspector: return "Details Pane"; case .preview: return "Preview Pane"; case .share: return "Share"
        case .operations: return "File Operations…"; case .properties: return "Properties…"; case .keyboard: return "Keyboard and Gestures…"; case .more: return "More Actions"
        case .recovery: return "Recovery & History…"; case .terminal: return "Open Location in Terminal (⌥⌘↩)"
        case .power: return "Power Tools"
        case .workspace: return "Workspace Navigation"
        case .commands: return "Command Palette…"; case .hidden: return "Hidden Items"; case .extensions: return "File Name Extensions"; case .checkboxes: return "Item Checkboxes"; case .compact: return "Compact Rows"
        }
    }
    var symbol: String {
        switch self {
        case .back: return "chevron.left"; case .forward: return "chevron.right"; case .up: return "arrow.up"; case .refresh: return "arrow.clockwise"
        case .new, .newFolder: return "folder.badge.plus"; case .newFile: return "doc.badge.plus"; case .cut: return "scissors"
        case .copy: return "doc.on.doc"; case .paste: return "doc.on.clipboard"; case .trash: return "trash"; case .rename: return "character.cursor.ibeam"
        case .view, .icons: return "square.grid.2x2"; case .details: return "list.bullet"; case .dual: return "rectangle.split.2x1"
        case .inspector: return "sidebar.right"; case .preview: return "doc.viewfinder"; case .share: return "square.and.arrow.up"
        case .operations: return "arrow.up.arrow.down.circle"; case .properties: return "info.circle"; case .keyboard: return "keyboard"; case .more: return "ellipsis.circle"
        case .recovery: return "clock.arrow.circlepath"; case .terminal: return "terminal"
        case .power: return "command.square"
        case .workspace: return "rectangle.split.2x1"
        case .commands: return "command"; case .hidden: return "eye.slash"; case .extensions: return "doc.text"; case .checkboxes: return "checkmark.square"; case .compact: return "line.3.horizontal.decrease"
        }
    }
    var isMenu: Bool { self == .new || self == .view || self == .more || self == .power }
    @MainActor func enabled(for root: ExplorerWorkspace?) -> Bool {
        guard let w = WorkspaceCommandScope.target(root) else { return false }
        switch self {
        case .back: return w.current.history.canGoBack; case .forward: return w.current.history.canGoForward
        case .up: return w.destination != nil || w.current.location.isArchive
        case .newFolder, .newFile, .paste: return w.destination != nil
        case .terminal: return TerminalRequest.directory(for: w) != nil
        case .details, .icons: return !w.current.location.isArchive
        case .copy, .cut, .trash, .rename, .properties, .share: return !w.selected.isEmpty
        default: return true
        }
    }
    @MainActor func perform(on root: ExplorerWorkspace?) {
        guard enabled(for: root) else { return }
        WorkspaceCommandScope.perform(on: root) { w in
            switch self {
            case .back: w.current.back(); case .forward: w.current.forward(); case .up: w.current.up(); case .refresh: w.current.refresh()
            case .new, .newFolder: w.sheet = .newFolder; case .newFile: w.sheet = .newFile
            case .cut: w.copy(cut: true); case .copy: w.copy(); case .paste: w.paste(); case .trash: w.delete(); case .rename: w.requestRename()
            case .details: w.current.options.view = .details; case .icons: w.current.options.view = .large
            case .dual: w.toggleDualPane(); case .inspector: w.preferences.value.inspector.toggle(); case .preview: w.preferences.value.previewPane.toggle()
            case .operations: w.sheet = .operations; case .properties: w.sheet = .properties; case .recovery: w.sheet = .recovery
            case .terminal: TerminalLauncher.shared.open(from: w)
            case .keyboard: w.sheet = .keyboardHelp; case .commands: w.sheet = .commandPalette
            case .share: if let view = w.window?.contentView { NSSharingServicePicker(items: w.selectedURLs).show(relativeTo: view.bounds, of: view, preferredEdge: .minY) }
            case .hidden: w.preferences.value.showHidden.toggle(); case .extensions: w.preferences.value.showExtensions.toggle(); case .checkboxes: w.preferences.value.checkboxes.toggle(); case .compact: w.preferences.value.compact.toggle()
            case .view, .more, .power, .workspace: break
            }
        }
    }
}
