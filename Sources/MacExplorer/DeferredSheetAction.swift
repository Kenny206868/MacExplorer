import Foundation
import AppKit
import ExplorerCore

/// Runs a selected action from SwiftUI's actual sheet dismissal callback,
/// never from a guessed animation delay. Each owner has one consumable action.
@MainActor final class DeferredSheetAction {
    static let shared = DeferredSheetAction()
    private struct Pending {
        weak var owner: ExplorerWorkspace?
        let validate: () throws -> Void
        let perform: (ExplorerWorkspace) -> Void
    }
    private var pending: [UUID: Pending] = [:]
    func enqueue(for workspace: ExplorerWorkspace, validate: @escaping () throws -> Void,
                 perform: @escaping (ExplorerWorkspace) -> Void) {
        pending[workspace.id] = Pending(owner: workspace, validate: validate, perform: perform)
        workspace.sheet = nil
    }
    func cancel(for workspace: ExplorerWorkspace) { pending.removeValue(forKey: workspace.id) }
    @discardableResult func didDismiss(_ workspace: ExplorerWorkspace) -> Bool {
        guard let action = pending.removeValue(forKey: workspace.id), action.owner === workspace else { return false }
        guard workspace.window?.isVisible != false, WorkspaceCommandScope.target(workspace) === workspace else { return false }
        do { try action.validate(); action.perform(workspace); return true }
        catch { workspace.fail("Action stopped", error.localizedDescription); return false }
    }
}
