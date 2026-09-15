import SwiftUI
import AppKit
import ExplorerCore

@MainActor final class InputPreferences: ObservableObject {
    static let shared = InputPreferences()
    @Published var touchFriendly: Bool { didSet { defaults.set(touchFriendly, forKey: "MacExplorer.input.touchFriendly") } }
    @Published var gesturesEnabled: Bool { didSet { defaults.set(gesturesEnabled, forKey: "MacExplorer.input.gesturesEnabled") } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        touchFriendly = defaults.bool(forKey: "MacExplorer.input.touchFriendly")
        gesturesEnabled = defaults.object(forKey: "MacExplorer.input.gesturesEnabled") as? Bool ?? true
    }
    var target: CGFloat { touchFriendly ? 44 : 32 }
    var headerHeight: CGFloat { touchFriendly ? 44 : 34 }
    var fileFontSize: CGFloat { touchFriendly ? 13 : 12 }
    func gridCellHeight(_ mode: ViewMode) -> CGFloat {
        switch mode { case .small: return touchFriendly ? 44 : 36; case .tiles, .details: return 80; default: return CGFloat(mode.iconSize) + 63 }
    }
    func rowHeight(compact: Bool) -> CGFloat { touchFriendly ? 44 : compact ? 28 : 36 }
}
@MainActor extension ExplorerWorkspace {
    func tapFile(_ url: URL, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        guard current.navigation.order.contains(url) else { return }
        activatePane(files: true)
        select(url, extend: touchSelecting || !modifiers.intersection([.command, .control]).isEmpty, range: modifiers.contains(.shift))
    }
    func activateFile(_ entry: FileEntry, doubleClick: Bool = false, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        guard current.navigation.order.contains(entry.url) else { return }
        if doubleClick { guard !touchSelecting else { return }; activatePane(files: true); open(entry) }
        else {
            tapFile(entry.url, modifiers: modifiers)
            if preferences.value.singleClickOpen && !touchSelecting && modifiers.intersection([.command, .control, .shift]).isEmpty { open(entry) }
        }
    }
    func showFileActions(for entry: FileEntry) {
        guard current.navigation.order.contains(entry.url) else { return }
        activatePane(files: true)
        if !current.selection.contains(entry.url) { select(entry.url, extend: false, range: false) }; sheet = .fileActions
    }
    func zoomFileView(_ direction: Int) {
        let modes: [ViewMode] = [.details, .small, .medium, .large, .extraLarge]
        let index = modes.firstIndex(of: current.options.view) ?? 2
        current.options.view = modes[min(modes.count - 1, max(0, index + (direction < 0 ? -1 : 1)))]
    }
    func focusFileSurface() {
        if addressFocused { addressFocused = false }; if searchFocused { searchFocused = false }
        fileSurfaceFocused = true
        if let window, window.firstResponder !== window { window.makeFirstResponder(nil) }
    }
    func cycleFocus(backwards: Bool) {
        let index = addressFocused ? 0 : searchFocused ? 1 : 2
        let next = (index + (backwards ? 2 : 1)) % 3
        addressFocused = false; searchFocused = false; fileSurfaceFocused = false
        switch next { case 0: addressFocused = true; case 1: searchFocused = true; default: focusFileSurface() }
    }
}
