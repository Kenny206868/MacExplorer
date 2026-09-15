import SwiftUI
import AppKit
import QuickLook
import ExplorerCore

struct ExplorerWindow: View {
    @StateObject private var workspace: ExplorerWorkspace
    init(session: BrowserSession? = nil, windowSession: WindowSession? = nil) { _workspace = StateObject(wrappedValue: ExplorerWorkspace(session: session, windowSession: windowSession)) }
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var preferences: PreferenceStore
    @ObservedObject private var operations = OperationCenter.shared
    var body: some View {
        WindowWorkspaceShell(workspace: workspace)
            .environmentObject(workspace.routedWorkspace)
            .focusedSceneValue(\.explorerWorkspace, workspace.routedWorkspace)
            .focusedSceneObject(workspace.routedWorkspace)
            .background(WindowAccessor(owner: workspace).frame(width: 0, height: 0))
            .frame(minWidth: 800, minHeight: 500)
            .modifier(WorkspaceDialogs(workspace: workspace.routedWorkspace))
            .modifier(TabDetachmentHost(workspace: workspace))
            .onAppear {
                AppRouter.shared.active = workspace.routedWorkspace
                WorkspaceSessionCoordinator.shared.register(workspace)
                WorkspaceSessionCoordinator.shared.restoreAdditionalWindows { openWindow(id: "restored-session", value: $0) }
                refreshVisible()
                Task { @MainActor in
                    await Task.yield(); workspace.dualPane?.secondary.window = workspace.window
                    if let frame = workspace.restorationFrame, let window = workspace.window { window.restoreExplorerFrame(frame); workspace.restorationFrame = nil }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                if let window = notification.object as? NSWindow, window == workspace.window { WorkspaceSessionCoordinator.shared.close(workspace) }
            }
            .onDisappear {
                workspace.dualPane?.cancelTransferPreparation()
                DeferredSheetAction.shared.cancel(for: workspace)
                if let second = workspace.dualPane?.secondary { DeferredSheetAction.shared.cancel(for: second) }
                workspace.answerCollision(.cancel); workspace.dualPane?.secondary.answerCollision(.cancel)
                workspace.saveSession(); workspace.tabs.forEach { $0.stop() }; workspace.dualPane?.secondary.tabs.forEach { $0.stop() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                if let window = notification.object as? NSWindow, window == workspace.window {
                    workspace.dualPane?.secondary.window = window; AppRouter.shared.active = workspace.routedWorkspace; FileClipboard.shared.refresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .explorerNewWindow)) { notification in if notification.object as? UUID == workspace.id { openWindow(id: "explorer") } }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in refreshVisible(); workspace.objectWillChange.send() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in refreshVisible(); workspace.objectWillChange.send() }
            .onChange(of: workspace.activeID) { _, _ in if workspace.dualPane == nil { workspace.current.refresh() }; workspace.saveSession() }
            .onChange(of: operations.revision) { _, _ in refreshVisible() }
            .onChange(of: preferences.value.showHidden) { _, _ in refreshVisible() }
            .confirmationDialog("Move to the other pane?", isPresented: Binding(get: { workspace.pendingPaneTransfer != nil }, set: { if !$0 { workspace.pendingPaneTransfer = nil } }), titleVisibility: .visible) {
                Button("Move Items") { workspace.confirmPaneTransfer() }
                Button("Cancel", role: .cancel) { workspace.pendingPaneTransfer = nil }
            } message: {
                if let request = workspace.pendingPaneTransfer { Text("Move \(request.job.sources.count) item(s) to \(request.job.destination?.path ?? ""). Existing items require a separate collision decision.") }
            }
    }
    private func refreshVisible() { if let dual = workspace.dualPane { dual.refreshVisible() } else { workspace.current.refresh() } }
}
struct WorkspaceDialogs: ViewModifier {
    @ObservedObject var workspace: ExplorerWorkspace
    func body(content: Content) -> some View {
        content.sheet(item: $workspace.sheet, onDismiss: { DeferredSheetAction.shared.didDismiss(workspace) }) { sheet in ExplorerSheetView(sheet: sheet, workspace: workspace) }
            .sheet(item: $workspace.conflict) { prompt in CollisionView(prompt: prompt, workspace: workspace).interactiveDismissDisabled() }
            .alert(item: $workspace.message) { message in Alert(title: Text(message.title), message: Text(message.message), dismissButton: .default(Text("OK"))) }
            .confirmationDialog(workspace.permanentDeletion ? "Permanently delete \(workspace.pendingDeletion.count) item(s)?" : "Move \(workspace.pendingDeletion.count) item(s) to Trash?", isPresented: Binding(get: { !workspace.pendingDeletion.isEmpty }, set: { if !$0 { workspace.pendingDeletion = [] } }), titleVisibility: .visible) {
                Button(workspace.permanentDeletion ? "Delete Permanently" : "Move to Trash", role: .destructive) { workspace.confirmDeletion() }
                Button("Cancel", role: .cancel) { workspace.pendingDeletion = [] }
            } message: { Text(workspace.permanentDeletion ? "This bypasses Trash and cannot be undone. Backups are not created for permanent deletion." : "Items can be restored using Undo or Recovery History.") }
    }
}
