import Foundation
import AppKit
import ExplorerCore

/// A sheet command runs once, after SwiftUI reports dismissal AND AppKit has
/// released the original sheet's modal/key-window boundary. Notifications and
/// the next main-run-loop turn drive handoff; no animation duration executes it.
@MainActor final class DeferredSheetAction {
    static let shared = DeferredSheetAction()
    @MainActor private final class Pending {
        let token = UUID()
        weak var owner: ExplorerWorkspace?
        weak var window: NSWindow?
        weak var originalSheet: NSWindow?
        let hadWindow: Bool
        let validate: @MainActor () throws -> Void
        let perform: @MainActor (ExplorerWorkspace) -> Void
        var dismissed = false
        var scheduled = false
        var observers: [NSObjectProtocol] = []
        var expiry: DispatchWorkItem?
        init(owner: ExplorerWorkspace, validate: @escaping @MainActor () throws -> Void,
             perform: @escaping @MainActor (ExplorerWorkspace) -> Void) {
            self.owner = owner; window = owner.window; originalSheet = owner.window?.attachedSheet
            hadWindow = owner.window != nil; self.validate = validate; self.perform = perform
        }
        func dispose() {
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            expiry?.cancel(); expiry = nil
        }
    }
    private var pending: [UUID: Pending] = [:]
    func enqueue(for workspace: ExplorerWorkspace, validate: @escaping @MainActor () throws -> Void,
                 perform: @escaping @MainActor (ExplorerWorkspace) -> Void) {
        remove(workspace.id)
        let action = Pending(owner: workspace, validate: validate, perform: perform)
        pending[workspace.id] = action
        if action.hadWindow {
            let id = workspace.id, token = action.token
            // Window focus may return before or after SwiftUI's onDismiss.
            // Observe both sides of that transition, but require onDismiss too.
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didBecomeMainNotification] {
                action.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.schedule(id, token: token) }
                })
            }
            action.observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: action.window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.remove(id, token: token) }
            })
            // Expiry only CANCELS an abandoned handoff. It never runs a command.
            let expiry = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.remove(id, token: token) } }
            action.expiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: expiry)
        }
        workspace.sheet = nil
    }
    func cancel(for workspace: ExplorerWorkspace) { remove(workspace.id) }
    @discardableResult func didDismiss(_ workspace: ExplorerWorkspace) -> Bool {
        guard let action = pending[workspace.id], action.owner === workspace, !action.dismissed else { return false }
        action.dismissed = true
        // Non-presented owners are useful for isolated command/state tests.
        // Real windows leave the SwiftUI dismissal transaction before handoff.
        if !action.hadWindow { return consumeIfReady(workspace.id, token: action.token) }
        schedule(workspace.id, token: action.token)
        return true
    }
    private func schedule(_ id: UUID, token: UUID) {
        guard let action = pending[id], action.token == token, action.dismissed, !action.scheduled else { return }
        action.scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let action = self.pending[id], action.token == token else { return }
            action.scheduled = false
            _ = self.consumeIfReady(id, token: token)
        }
    }
    @discardableResult private func consumeIfReady(_ id: UUID, token: UUID) -> Bool {
        guard let action = pending[id], action.token == token, action.dismissed,
              let owner = action.owner else { remove(id, token: token); return false }
        if action.hadWindow {
            guard let window = action.window, owner.window === window, window.isVisible else { remove(id); return false }
            if let sheet = window.attachedSheet {
                if sheet !== action.originalSheet { remove(id) }
                return false
            }
            if let key = NSApp.keyWindow, key !== window {
                if key !== action.originalSheet { remove(id) }
                return false
            }
            if let modal = NSApp.modalWindow, modal !== window {
                if modal !== action.originalSheet { remove(id) }
                return false
            }
        }
        guard WorkspaceCommandScope.target(owner) === owner else { remove(id); return false }
        remove(id)
        do { try action.validate(); action.perform(owner); return true }
        catch { owner.fail("Action stopped", error.localizedDescription); return false }
    }
    private func remove(_ id: UUID, token: UUID? = nil) {
        guard let action = pending[id], token == nil || action.token == token else { return }
        pending.removeValue(forKey: id); action.dispose()
    }
}