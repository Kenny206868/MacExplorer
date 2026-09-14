import AppKit

/// Menus and keyboard handlers must use the same modal boundary. Checking only
/// the key-event monitor leaves menu key equivalents free to mutate files
/// behind a sheet whose first responder happens not to be a text editor.
@MainActor enum WorkspaceCommandScope {
    static func target(_ candidate: ExplorerWorkspace?) -> ExplorerWorkspace? {
        guard let candidate else { return nil }
        let root = candidate.windowRoot
        let workspaces = [root] + (root.dualPane.map { [$0.secondary] } ?? [])
        guard root.pendingPaneTransfer == nil,
              workspaces.allSatisfy({ $0.sheet == nil && $0.message == nil && $0.conflict == nil && $0.pendingDeletion.isEmpty }),
              root.window?.attachedSheet == nil else { return nil }
        if let window = root.window, let key = NSApp.keyWindow, window !== key { return nil }
        if let modal = NSApp.modalWindow, modal !== root.window { return nil }
        return candidate.routedWorkspace
    }
    @discardableResult static func perform(on candidate: ExplorerWorkspace?, _ action: (ExplorerWorkspace) -> Void) -> Bool {
        guard let workspace = target(candidate) else { return false }
        action(workspace); return true
    }
}
