import SwiftUI
import AppKit
import Combine
import ExplorerCore

/// Native window identity changes only when its visible state changes, not on
/// every selection/focus publication from a file row.
@MainActor final class NativeWindowChrome: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation, NSMenuDelegate {
    static let identifier = NSToolbar.Identifier("MacExplorer.FileToolbar.v2")
    var persistsConfiguration = true
    weak var owner: ExplorerWorkspace?
    private weak var installedWindow: NSWindow?
    private var toolbar: NSToolbar?
    private var settingsObservation: AnyCancellable?
    private var inputObservation: AnyCancellable?
    let workspaceModel = WorkspaceChromeModel()
    private struct HostConstraints {
        weak var view: NSView?
        weak var width: NSLayoutConstraint?
        weak var height: NSLayoutConstraint?
    }
    private var workspaceHosts: [HostConstraints] = []
    private var windowObservers: [NSObjectProtocol] = []
    private var lastAvailability: [Bool]?
    private(set) var chromeMutationCount = 0
    private(set) var validationPasses = 0
    func attach(to window: NSWindow, owner: ExplorerWorkspace) {
        self.owner = owner
        workspaceModel.update(owner: owner, width: window.frame.width)
        if installedWindow !== window {
            windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
            installedWindow = window; lastAvailability = nil
            settingsObservation = CommanderPreferences.shared.objectWillChange.sink { [weak self] _ in
                // Published emits before assignment; read the committed settings on the next UI turn.
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
            inputObservation = InputPreferences.shared.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didResizeNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
            }
            // autosavesConfiguration=false disables disk persistence, not AppKit's
            // in-process synchronization of toolbars with the same identifier.
            // Isolate nonpersistent previews/tests from each other and real windows.
            let identifier = persistsConfiguration ? Self.identifier
                : NSToolbar.Identifier(Self.identifier + ".isolated." + UUID().uuidString)
            let toolbar = NSToolbar(identifier: identifier)
            toolbar.delegate = self; toolbar.allowsUserCustomization = true
            toolbar.autosavesConfiguration = persistsConfiguration; toolbar.displayMode = .iconOnly
            toolbar.centeredItemIdentifiers = [.init("workspace")]
            self.toolbar = toolbar; window.toolbar = toolbar
            migrateLegacyDefault(toolbar)
            window.toolbarStyle = CommanderPreferences.shared.compactTitlebar ? .unifiedCompact : .unified; window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false; window.titlebarSeparatorStyle = .automatic
            window.isMovableByWindowBackground = false
        }
        refresh()
    }
    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }
    func refresh() {
        guard let root = owner, let window = installedWindow else { return }
        workspaceModel.update(owner: root, width: window.frame.width)
        let layout = workspaceModel.state.layout
        workspaceHosts.removeAll { $0.view == nil }
        for host in workspaceHosts {
            let width = CGFloat(layout.titlebarWidth), height = CGFloat(layout.titlebarHeight)
            if let constraint = host.width, constraint.constant != width { constraint.constant = width }
            if let constraint = host.height, constraint.constant != height { constraint.constant = height }
        }
        let workspace = root.routedWorkspace, location = workspace.current.location
        let title = location.title
        let style: NSWindow.ToolbarStyle = CommanderPreferences.shared.compactTitlebar ? .unifiedCompact : .unified
        if window.toolbarStyle != style { window.toolbarStyle = style; chromeMutationCount += 1 }
        let stacked = root.dualPane?.geometry.orientation == .stacked
        let side = workspace.parentWorkspace == nil ? (stacked ? "Top pane" : "Left pane") : (stacked ? "Bottom pane" : "Right pane")
        let subtitle = root.dualPane == nil ? "MacExplorer" : side + " · MacExplorer"
        let represented = location.archiveSource ?? location.directory
        if window.title != title { window.title = title; chromeMutationCount += 1 }
        if window.subtitle != subtitle { window.subtitle = subtitle; chromeMutationCount += 1 }
        if window.representedURL != represented { window.representedURL = represented; chromeMutationCount += 1 }
        if window.isDocumentEdited { window.isDocumentEdited = false; chromeMutationCount += 1 }
        let name: NSAppearance.Name? = root.preferences.value.theme == "dark" ? .darkAqua : root.preferences.value.theme == "light" ? .aqua : nil
        if window.appearance?.name != name { window.appearance = name.flatMap(NSAppearance.init(named:)); chromeMutationCount += 1 }
        let available = WindowChromeAction.allCases.map { $0.enabled(for: root) }
        if lastAvailability != available { lastAvailability = available; toolbar?.validateVisibleItems(); validationPasses += 1 }
    }
    static var legacyDefaultItems: [NSToolbarItem.Identifier] {
        [.init("back"), .init("forward"), .flexibleSpace, .init("new"), .init("view"), .init("dual"), .init("terminal"), .init("power"), .init("inspector"), .init("more")]
    }
    /// Upgrade only the exact previously shipped default. Never reset an
    /// owner's custom toolbar; Workspace Navigation is available in Customize.
    func migrateLegacyDefault(_ toolbar: NSToolbar) {
        guard toolbar.items.map(\.itemIdentifier) == Self.legacyDefaultItems else { return }
        toolbar.insertItem(withItemIdentifier: .init("workspace"), at: 3)
        toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: 4)
        if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue == "dual" }) { toolbar.removeItem(at: index) }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("back"), .init("forward"), .flexibleSpace, .init("workspace"), .flexibleSpace, .init("new"), .init("view"), .init("terminal"), .init("power"), .init("inspector"), .init("more")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { WindowChromeAction.allCases.map { .init($0.rawValue) } + [.flexibleSpace, .space] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let action = WindowChromeAction(rawValue: identifier.rawValue) else { return nil }
        lastAvailability = nil
        let item: NSToolbarItem
        if action == .workspace {
            // All app-created controls remain SwiftUI; AppKit only installs the
            // view in the native customizable toolbar and constrains its size.
            let host = NSHostingView(rootView: WorkspaceTitlebarControls(model: workspaceModel))
            host.translatesAutoresizingMaskIntoConstraints = false
            host.setAccessibilityIdentifier("explorer.titlebarWorkspaceHost")
            let width = host.widthAnchor.constraint(equalToConstant: workspaceModel.state.layout.titlebarWidth)
            let height = host.heightAnchor.constraint(equalToConstant: workspaceModel.state.layout.titlebarHeight)
            NSLayoutConstraint.activate([width, height])
            // A customization-palette copy must not steal the installed item's
            // sizing handles. Track every live host without retaining its view.
            workspaceHosts.append(HostConstraints(view: host, width: width, height: height))
            item = NSToolbarItem(itemIdentifier: identifier); item.view = host
        }
        else if action.isMenu { let menuItem = NSMenuToolbarItem(itemIdentifier: identifier); menuItem.menu = menu(action); item = menuItem }
        else { item = NSToolbarItem(itemIdentifier: identifier); item.target = self; item.action = #selector(invokeToolbar(_:)) }
        item.label = action.title; item.paletteLabel = action.title; item.toolTip = action.title
        item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title); item.image?.isTemplate = true
        item.visibilityPriority = [.workspace, .dual, .terminal, .power].contains(action) ? .high : .standard
        if action == .dual { item.toolTip = "Toggle dual panes · ⇧⌘D" }
        item.isBordered = false; item.isNavigational = action == .back || action == .forward || action == .up
        let overflow = NSMenuItem(title: action.title, action: #selector(invokeMenu(_:)), keyEquivalent: "")
        overflow.target = self; overflow.representedObject = action.rawValue
        if action.isMenu || action == .workspace { overflow.submenu = menu(action) }; item.menuFormRepresentation = overflow
        return item
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { WindowChromeAction(rawValue: item.itemIdentifier.rawValue)?.enabled(for: owner) ?? false }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let key = item.representedObject as? String else { return true }
        if let action = WindowChromeAction(rawValue: key) { return action.enabled(for: owner) }
        guard let workspace = WorkspaceCommandScope.target(owner) else { return false }
        if key.hasPrefix("layout:"), let command = WorkspaceLayoutAction(rawValue: String(key.dropFirst(7))) { return command.enabled(owner) }
        if key.hasPrefix("commander:"), let command = CommanderAction(rawValue: String(key.dropFirst(10))) { return command.enabled(in: workspace) }
        if key.hasPrefix("power:") { return true }
        return !workspace.current.location.isArchive
    }
    @objc private func invokeToolbar(_ item: NSToolbarItem) { WindowChromeAction(rawValue: item.itemIdentifier.rawValue)?.perform(on: owner) }
    @objc private func invokeMenu(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String else { return }
        if let action = WindowChromeAction(rawValue: key) { action.perform(on: owner); return }
        if key.hasPrefix("layout:"), let action = WorkspaceLayoutAction(rawValue: String(key.dropFirst(7))) { action.perform(owner); return }
        WorkspaceCommandScope.perform(on: owner) { workspace in
            if key.hasPrefix("commander:"), let command = CommanderAction(rawValue: String(key.dropFirst(10))) { command.perform(in: workspace); return }
            let settings = CommanderPreferences.shared
            switch key {
            case "power:enable": settings.showCommandBar = true; if workspace.paneController == nil { workspace.toggleDualPane() }; return
            case "power:bar": settings.showCommandBar.toggle(); return
            case "power:keys": settings.classicFunctionKeys.toggle(); return
            case "power:compact": settings.compactTitlebar.toggle(); return
            case "power:storage": settings.paneStorage.toggle(); return
            case "power:terminal": settings.paneTerminalButtons.toggle(); return
            default: break
            }
            guard !workspace.current.location.isArchive else { return }
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
            let settings = CommanderPreferences.shared
            let powerChecked = key == "power:bar" && settings.showCommandBar || key == "power:keys" && settings.classicFunctionKeys
                || key == "power:compact" && settings.compactTitlebar || key == "power:storage" && settings.paneStorage
                || key == "power:terminal" && settings.paneTerminalButtons
            item.state = checked || powerChecked ? .on : .off
        }
    }
    private func menu(_ action: WindowChromeAction) -> NSMenu {
        let result = NSMenu(title: action.title); result.delegate = self
        func add(_ title: String, _ key: String) {
            let item = NSMenuItem(title: title, action: #selector(invokeMenu(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = key; result.addItem(item)
        }
        func command(_ action: WindowChromeAction) { add(action.title, action.rawValue) }
        if action == .workspace {
            for action in WorkspaceLayoutAction.allCases { add(action.title, "layout:" + action.rawValue) }
        }
        else if action == .power {
            add("Enable Commander Workspace", "power:enable")
            add("Show Commander Command Bar", "power:bar"); add("Classic F3–F8 File Commands", "power:keys")
            result.addItem(.separator())
            for action in [CommanderAction.selectMask, .invert, .sameExtension, .compare, .rename, .pack, .extract] { add(action.title, "commander:" + action.rawValue) }
            result.addItem(.separator())
            add("Compact Title Bar", "power:compact"); add("Storage in Each Pane", "power:storage"); add("Terminal Button in Each Pane", "power:terminal")
            result.addItem(.separator()); add(CommanderAction.settings.title, "commander:settings")
        }
        else if action == .new { command(.newFolder); command(.newFile) }
        else if action == .view {
            for mode in ViewMode.allCases { add(mode.rawValue, "view:" + mode.rawValue) }
            result.addItem(.separator())
            for field in SortField.allCases { add("Sort by " + field.rawValue, "sort:" + field.rawValue) }
            add("Descending", "descending"); add("Folders First", "foldersFirst"); result.addItem(.separator())
            for field in GroupField.allCases { add("Group: " + field.rawValue, "group:" + field.rawValue) }
            result.addItem(.separator())
            for action in [WindowChromeAction.dual, .inspector, .preview, .hidden, .extensions, .checkboxes, .compact] { command(action) }
        } else {
            for action in [WindowChromeAction.commands, .rename, .cut, .copy, .paste, .trash, .share] { command(action) }
            result.addItem(.separator()); command(.terminal); command(.properties); command(.operations); command(.recovery); command(.keyboard)
        }
        return result
    }
}
