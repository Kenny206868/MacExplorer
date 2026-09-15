import SwiftUI

/// Each power feature is independent. Existing Explorer shortcuts remain the
/// default; opting into a command strip never silently remaps function keys.
@MainActor final class CommanderPreferences: ObservableObject {
    static let shared = CommanderPreferences()
    @Published var showCommandBar: Bool { didSet { save("bar", showCommandBar) } }
    @Published var classicFunctionKeys: Bool { didSet { save("functionKeys", classicFunctionKeys) } }
    @Published var compactTitlebar: Bool { didSet { save("compactTitlebar", compactTitlebar) } }
    @Published var paneStorage: Bool { didSet { save("paneStorage", paneStorage) } }
    @Published var paneTerminalButtons: Bool { didSet { save("paneTerminal", paneTerminalButtons) } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showCommandBar = defaults.bool(forKey: "MacExplorer.commander.bar")
        classicFunctionKeys = defaults.bool(forKey: "MacExplorer.commander.functionKeys")
        compactTitlebar = defaults.bool(forKey: "MacExplorer.commander.compactTitlebar")
        paneStorage = defaults.object(forKey: "MacExplorer.commander.paneStorage") as? Bool ?? true
        paneTerminalButtons = defaults.bool(forKey: "MacExplorer.commander.paneTerminal")
    }
    private func save(_ key: String, _ value: Bool) { defaults.set(value, forKey: "MacExplorer.commander." + key) }
}
