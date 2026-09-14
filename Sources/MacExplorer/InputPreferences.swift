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
    func rowHeight(compact: Bool) -> CGFloat { touchFriendly ? 44 : compact ? 28 : 36 }
}
@MainActor extension ExplorerWorkspace {
    func tapFile(_ url: URL) {
        let flags = NSEvent.modifierFlags
        select(url, extend: touchSelecting || !flags.intersection([.command, .control]).isEmpty, range: flags.contains(.shift))
    }
    func zoomFileView(_ direction: Int) {
        let modes: [ViewMode] = [.details, .small, .medium, .large, .extraLarge]
        let index = modes.firstIndex(of: current.options.view) ?? 2
        current.options.view = modes[min(modes.count - 1, max(0, index + (direction < 0 ? -1 : 1)))]
    }
    func focusFileSurface() {
        addressFocused = false; searchFocused = false; fileSurfaceFocused = true
        window?.makeFirstResponder(nil)
    }
    func cycleFocus(backwards: Bool) {
        let index = addressFocused ? 0 : searchFocused ? 1 : 2
        let next = (index + (backwards ? 2 : 1)) % 3
        addressFocused = false; searchFocused = false; fileSurfaceFocused = false
        switch next { case 0: addressFocused = true; case 1: searchFocused = true; default: focusFileSurface() }
    }
}
