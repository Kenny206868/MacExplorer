import SwiftUI
import AppKit
import ExplorerCore

/// AppKit owns the real title bar, standard window buttons, customization,
/// overflow, proxy icon and fullscreen transitions. Every custom control is a
/// SwiftUI view; no faux traffic lights or reparented system buttons are used.
@MainActor final class NativeWindowChrome: NSObject, NSToolbarDelegate, NSMenuItemValidation {
    static let identifier = NSToolbar.Identifier("MacExplorer.FileToolbar.v1")
    var persistsConfiguration = true
    weak var owner: ExplorerWorkspace?
    private weak var installedWindow: NSWindow?
    private var toolbar: NSToolbar?

    func attach(to window: NSWindow, owner: ExplorerWorkspace) {
        self.owner = owner
        if installedWindow !== window {
            installedWindow = window
            let toolbar = NSToolbar(identifier: Self.identifier)
            toolbar.delegate = self
            toolbar.allowsUserCustomization = true
            toolbar.autosavesConfiguration = persistsConfiguration
            toolbar.displayMode = .iconOnly
            self.toolbar = toolbar
            window.toolbar = toolbar
            window.toolbarStyle = .unifiedCompact
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .automatic
            window.isMovableByWindowBackground = false
        }
        refresh()
    }
    func refresh() {
        guard let root = owner, let window = installedWindow else { return }
        let workspace = root.routedWorkspace, location = workspace.current.location
        window.title = location.title
        window.subtitle = root.dualPane == nil ? "MacExplorer" : (workspace.parentWorkspace == nil ? "Left pane" : "Right pane") + " · MacExplorer"
        window.representedURL = location.directory
        window.isDocumentEdited = false
        toolbar?.validateVisibleItems()
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("back"), .init("forward"), .flexibleSpace, .init("new"), .init("copy"), .init("paste"), .init("view"), .init("dual"), .init("inspector"), .init("more")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        WindowChromeAction.allCases.map { .init($0.rawValue) } + [.flexibleSpace, .space]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let action = WindowChromeAction(rawValue: identifier.rawValue), let owner else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = action.title; item.paletteLabel = action.title; item.toolTip = action.title
        let host = NSHostingView(rootView: NativeToolbarControl(owner: owner, action: action))
        host.frame = NSRect(x: 0, y: 0, width: action.isMenu ? 42 : 34, height: 32)
        item.view = host
        let menu = NSMenuItem(title: action.title, action: #selector(invokeMenu(_:)), keyEquivalent: "")
        menu.target = self; menu.representedObject = action.rawValue
        if action.isMenu { menu.submenu = overflowMenu(action) }
        item.menuFormRepresentation = menu
        return item
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let id = menuItem.representedObject as? String, let action = WindowChromeAction(rawValue: id) else { return true }
        return action.enabled(for: owner)
    }
    @objc private func invokeMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let action = WindowChromeAction(rawValue: id) else { return }
        action.perform(on: owner)
    }
    private func overflowMenu(_ action: WindowChromeAction) -> NSMenu {
        let menu = NSMenu(title: action.title)
        let actions: [WindowChromeAction]
        switch action {
        case .new: actions = [.newFolder, .newFile]
        case .view: actions = [.details, .icons, .dual, .inspector, .preview]
        default: actions = [.rename, .cut, .copy, .paste, .trash, .properties, .operations, .keyboard]
        }
        for child in actions {
            let item = NSMenuItem(title: child.title, action: #selector(invokeMenu(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = child.rawValue; menu.addItem(item)
        }
        return menu
    }
}

enum WindowChromeAction: String, CaseIterable {
    case back, forward, up, refresh, new, newFolder, newFile, cut, copy, paste, trash, rename
    case view, details, icons, dual, inspector, preview, share, operations, properties, keyboard, more
    var title: String {
        switch self {
        case .back: return "Back"; case .forward: return "Forward"; case .up: return "Enclosing Folder"; case .refresh: return "Refresh"
        case .new: return "New"; case .newFolder: return "New Folder…"; case .newFile: return "New Text Document…"
        case .cut: return "Cut"; case .copy: return "Copy"; case .paste: return "Paste"; case .trash: return "Move to Trash"; case .rename: return "Rename…"
        case .view: return "View and Sort"; case .details: return "Details View"; case .icons: return "Icon View"; case .dual: return "Dual Panes"
        case .inspector: return "Details Pane"; case .preview: return "Preview Pane"; case .share: return "Share"
        case .operations: return "File Operations…"; case .properties: return "Properties…"; case .keyboard: return "Keyboard and Gestures…"; case .more: return "More Actions"
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
            case .operations: w.sheet = .operations; case .properties: w.sheet = .properties; case .keyboard: w.sheet = .keyboardHelp
            case .share:
                if let view = w.window?.contentView { NSSharingServicePicker(items: w.selectedURLs).show(relativeTo: view.bounds, of: view, preferredEdge: .minY) }
            case .view, .more: break
            }
        }
    }
}
private struct NativeToolbarControl: View {
    @ObservedObject var owner: ExplorerWorkspace
    let action: WindowChromeAction
    @ObservedObject private var preferences = PreferenceStore.shared
    private var workspace: ExplorerWorkspace { owner.routedWorkspace }
    var body: some View {
        Group {
            if action == .new {
                Menu { command(.newFolder); command(.newFile) } label: { glyph }
            } else if action == .view {
                Menu {
                    Picker("View", selection: Binding(get: { workspace.current.options.view }, set: { workspace.current.options.view = $0 })) {
                        ForEach(ViewMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Sort by", selection: Binding(get: { workspace.current.options.sort }, set: { workspace.current.options.sort = $0 })) {
                        ForEach(SortField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Descending", isOn: Binding(get: { workspace.current.options.descending }, set: { workspace.current.options.descending = $0 }))
                    Divider(); command(.dual); command(.inspector); command(.preview)
                    Toggle("Hidden Items", isOn: $preferences.value.showHidden)
                } label: { glyph }
            } else if action == .more {
                Menu {
                    command(.rename); command(.cut); command(.copy); command(.paste); command(.trash)
                    Divider(); ShareLink(items: workspace.selectedURLs) { Text("Share…") }.disabled(workspace.selected.isEmpty)
                    command(.properties); command(.operations); command(.keyboard)
                } label: { glyph }
            } else if action == .share {
                ShareLink(items: workspace.selectedURLs) { glyph }
            } else { Button { action.perform(on: owner) } label: { glyph } }
        }.buttonStyle(.plain).menuStyle(.borderlessButton).menuIndicator(.hidden)
            .disabled(!action.enabled(for: owner)).help(action.title).accessibilityLabel(action.title)
            .environment(\.colorScheme, preferences.colorScheme ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light))
    }
    private var glyph: some View {
        Image(systemName: action.symbol).font(.system(size: 15, weight: .regular))
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .frame(width: action.isMenu ? 42 : 34, height: 32).contentShape(Rectangle())
    }
    private var selected: Bool {
        action == .dual && owner.dualPane != nil || action == .inspector && preferences.value.inspector || action == .preview && preferences.value.previewPane
    }
    private func command(_ command: WindowChromeAction) -> some View {
        Button(command.title, systemImage: command.symbol) { command.perform(on: owner) }.disabled(!command.enabled(for: owner))
    }
}
