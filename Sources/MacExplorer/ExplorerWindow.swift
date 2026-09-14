import SwiftUI
import AppKit
import QuickLook
import ExplorerCore

struct ExplorerWindow: View {
    @StateObject private var workspace: ExplorerWorkspace
    init(session: BrowserSession? = nil) {
        _workspace = StateObject(wrappedValue: ExplorerWorkspace(session: session))
    }
    @EnvironmentObject private var preferences: PreferenceStore
    @ObservedObject private var operations = OperationCenter.shared
    var body: some View {
        WorkspaceShell(workspace: workspace, tab: workspace.current)
            .environmentObject(workspace)
            .focusedSceneValue(\.explorerWorkspace, workspace)
            .focusedSceneObject(workspace)
            .background(WindowAccessor(owner: workspace).frame(width: 0, height: 0))
            .frame(minWidth: 800, minHeight: 500)
            .onAppear { AppRouter.shared.active = workspace; workspace.current.refresh() }
            .onDisappear { workspace.answerCollision(.cancel); workspace.saveSession(); workspace.tabs.forEach { $0.stop() } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                if let window = notification.object as? NSWindow, window == workspace.window { AppRouter.shared.active = workspace; FileClipboard.shared.refresh() }
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in workspace.current.refresh(); workspace.objectWillChange.send() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in workspace.current.refresh(); workspace.objectWillChange.send() }
            .onChange(of: workspace.activeID) { _, _ in workspace.current.refresh(); workspace.saveSession() }
            .onChange(of: operations.revision) { _, _ in workspace.current.refresh() }
            .onChange(of: preferences.value.showHidden) { _, _ in workspace.current.refresh() }
            .sheet(item: $workspace.sheet) { sheet in ExplorerSheetView(sheet: sheet, workspace: workspace) }
            .sheet(item: $workspace.conflict) { prompt in CollisionView(prompt: prompt, workspace: workspace).interactiveDismissDisabled() }
            .alert(item: $workspace.message) { message in Alert(title: Text(message.title), message: Text(message.message), dismissButton: .default(Text("OK"))) }
            .confirmationDialog(workspace.permanentDeletion ? "Permanently delete \(workspace.pendingDeletion.count) item(s)?" : "Move \(workspace.pendingDeletion.count) item(s) to Trash?", isPresented: Binding(get: { !workspace.pendingDeletion.isEmpty }, set: { if !$0 { workspace.pendingDeletion = [] } }), titleVisibility: .visible) {
                Button(workspace.permanentDeletion ? "Delete Permanently" : "Move to Trash", role: .destructive) { workspace.confirmDeletion() }
                Button("Cancel", role: .cancel) { workspace.pendingDeletion = [] }
            } message: { Text(workspace.permanentDeletion ? "This bypasses Trash and cannot be undone. Backups are not created for permanent deletion." : "Items can be restored using Undo or Recovery History.") }
    }
}
