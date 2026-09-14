import SwiftUI
import AppKit
import ExplorerCore

/// Window controls are owned and rendered by AppKit. Using standard symbol/menu
/// items avoids nested NSHostingView materials losing glyph contrast on macOS 26.
/// All application panels and file surfaces remain SwiftUI.
@MainActor final class NativeWindowChrome: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation, NSMenuDelegate {
    static let identifier = NSToolbar.Identifier("MacExplorer.FileToolbar.v2")
    var persistsConfiguration = true
    weak var owner: ExplorerWorkspace?
    private weak var installedWindow: NSWindow?
    private var toolbar: NSToolbar?
    func attach(to window: NSWindow, owner: ExplorerWorkspace) {
        self.owner = owner
        if installedWindow !== window {
            installedWindow = window
            let toolbar = NSToolbar(identifier: Self.identifier)
            toolbar.delegate = self; toolbar.allowsUserCustomization = true
            toolbar.autosavesConfiguration = persistsConfiguration; toolbar.displayMode = .iconOnly
            self.toolbar = toolbar; window.toolbar = toolbar
            window.toolbarStyle = .unifiedCompact; window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false; window.titlebarSeparatorStyle = .automatic
            window.isMovableByWindowBackground = false
        }
        refresh()
    }
    func refresh() {
        guard let root = owner, let window = installedWindow else { return }
        let workspace = root.routedWorkspace, location = workspace.current.location
        window.title = location.title
        window.subtitle = root.dualPane == nil ? "MacExplorer" : (workspace.parentWorkspace == nil ? "Left pane" : "Right pane") + " · MacExplorer"
        window.representedURL = location.directory; window.isDocumentEdited = false
        switch root.preferences.value.theme {
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        case "light": window.appearance = NSAppearance(named: .aqua)
        default: window.appearance = nil
        }
        toolbar?.validateVisibleItems()
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("back"), .init("forward"), .flexibleSpace, .init("new"), .init("copy"), .init("paste"), .init("view"), .init("dual"), .init("inspector"), .init("more")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { WindowChromeAction.allCases.map { .init($0.rawValue) } + [.flexibleSpace, .space] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let action = WindowChromeAction(rawValue: identifier.rawValue) else { return nil }
        let item: NSToolbarItem
        if action.isMenu {
            let menuItem = NSMenuToolbarItem(itemIdentifier: identifier)
            menuItem.menu = menu(action); item = menuItem
        } else {
            item = NSToolbarItem(itemIdentifier: identifier)
            item.target = self; item.action = #selector(invokeToolbar(_:))
        }
        item.label = action.title; item.paletteLabel = action.title; item.toolTip = action.title
        item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title)
        item.image?.isTemplate = true
        item.isBordered = true
        item.isNavigational = action == .back || action == .forward || action == .up
        let overflow = NSMenuItem(title: action.title, action: #selector(invokeMenu(_:)), keyEquivalent: "")
        overflow.target = self; overflow.representedObject = action.rawValue
        if action.isMenu { overflow.submenu = menu(action) }
        item.menuFormRepresentation = overflow
        return item
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { WindowChromeAction(rawValue: item.itemIdentifier.rawValue)?.enabled(for: owner) ?? false }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let key = item.representedObject as? String else { return true }
        if let action = WindowChromeAction(rawValue: key) { return action.enabled(for: owner) }
        return WorkspaceCommandScope.target(owner) != nil
    }
    @objc private func invokeToolbar(_ item: NSToolbarItem) { WindowChromeAction(rawValue: item.itemIdentifier.rawValue)?.perform(on: owner) }
    @objc private func invokeMenu(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String else { return }
        if let action = WindowChromeAction(rawValue: key) { action.perform(on: owner); return }
        WorkspaceCommandScope.perform(on: owner) { workspace in
            if key.hasPrefix("view:"), let mode = ViewMode(rawValue: String(key.dropFirst(5))) { workspace.current.options.view = mode }
            else if key.hasPrefix("sort:"), let field = SortField(rawValue: String(key.dropFirst(5))) { workspace.current.options.sort = field }
            else if key.hasPrefix("group:"), let field = GroupField(rawValue: String(key.dropFirst(6))) { workspace.current.options.group = field }
            else if key == "descending" { workspace.current.options.descending.toggle() }
            else if key == "foldersFirst" { workspace.current.options.foldersFirst.toggle() }
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let workspace = owner?.routedWorkspace else { return }
        for item in menu.items {
            guard let key = item.representedObject as? String else { continue }
            let checked = key == "view:" + workspace.current.options.view.rawValue || key == "sort:" + workspace.current.options.sort.rawValue || key == "group:" + workspace.current.options.group.rawValue
                || key == "descending" && workspace.current.options.descending || key == "foldersFirst" && workspace.current.options.foldersFirst
                || key == "dual" && workspace.paneController != nil || key == "inspector" && workspace.preferences.value.inspector || key == "preview" && workspace.preferences.value.previewPane
                || key == "hidden" && workspace.preferences.value.showHidden || key == "extensions" && workspace.preferences.value.showExtensions
                || key == "checkboxes" && workspace.preferences.value.checkboxes || key == "compact" && workspace.preferences.value.compact
            item.state = checked ? .on : .off
        }
    }
    private func menu(_ action: WindowChromeAction) -> NSMenu {
        let result = NSMenu(title: action.title); result.delegate = self
        func add(_ title: String, _ key: String) {
            let item = NSMenuItem(title: title, action: #selector(invokeMenu(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = key; result.addItem(item)
        }
        func command(_ action: WindowChromeAction) { add(action.title, action.rawValue) }
        if action == .new { command(.newFolder); command(.newFile) }
        else if action == .view {
            for mode in ViewMode.allCases { add(mode.rawValue, "view:" + mode.rawValue) }
            result.addItem(.separator())
            for field in SortField.allCases { add("Sort by " + field.rawValue, "sort:" + field.rawValue) }
            add("Descending", "descending"); add("Folders First", "foldersFirst")
            result.addItem(.separator())
            for field in GroupField.allCases { add("Group: " + field.rawValue, "group:" + field.rawValue) }
            result.addItem(.separator())
            for action in [WindowChromeAction.dual, .inspector, .preview, .hidden, .extensions, .checkboxes, .compact] { command(action) }
        } else {
            for action in [WindowChromeAction.commands, .rename, .cut, .copy, .paste, .trash, .share] { command(action) }
            result.addItem(.separator()); command(.properties); command(.operations); command(.keyboard)
        }
        return result
    }
}

enum WindowChromeAction: String, CaseIterable {
    case back, forward, up, refresh, new, newFolder, newFile, cut, copy, paste, trash, rename
    case view, details, icons, dual, inspector, preview, share, operations, properties, keyboard, more, commands
    case hidden, extensions, checkboxes, compact
    var title: String {
        switch self {
        case .back: return "Back"; case .forward: return "Forward"; case .up: return "Enclosing Folder"; case .refresh: return "Refresh"
        case .new: return "New"; case .newFolder: return "New Folder…"; case .newFile: return "New Text Document…"
        case .cut: return "Cut"; case .copy: return "Copy"; case .paste: return "Paste"; case .trash: return "Move to Trash"; case .rename: return "Rename…"
        case .view: return "View and Sort"; case .details: return "Details View"; case .icons: return "Icon View"; case .dual: return "Dual Panes"
        case .inspector: return "Details Pane"; case .preview: return "Preview Pane"; case .share: return "Share"
        case .operations: return "File Operations…"; case .properties: return "Properties…"; case .keyboard: return "Keyboard and Gestures…"; case .more: return "More Actions"
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
        case .commands: return "command"; case .hidden: return "eye.slash"; case .extensions: return "doc.text"; case .checkboxes: return "checkmark.square"; case .compact: return "line.3.horizontal.decrease"
        }
    }
    var isMenu: Bool { self == .new || self == .view || self == .more }
    @MainActor func enabled(for root: ExplorerWorkspace?) -> Bool {
        guard let w = WorkspaceCommandScope.target(root) else { return false }
        switch self {
        case .back: return w.current.history.canGoBack
        case .forward: return w.current.history.canGoForward
        case .up: return w.destination != nil
        case .newFolder, .newFile, .paste: return w.destination != nil
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
            case .operations: w.sheet = .operations; case .properties: w.sheet = .properties; case .keyboard: w.sheet = .keyboardHelp; case .commands: w.sheet = .commandPalette
            case .share: if let view = w.window?.contentView { NSSharingServicePicker(items: w.selectedURLs).show(relativeTo: view.bounds, of: view, preferredEdge: .minY) }
            case .hidden: w.preferences.value.showHidden.toggle(); case .extensions: w.preferences.value.showExtensions.toggle(); case .checkboxes: w.preferences.value.checkboxes.toggle(); case .compact: w.preferences.value.compact.toggle()
            case .view, .more: break
            }
        }
    }
}
