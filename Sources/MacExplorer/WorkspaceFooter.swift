import SwiftUI
import ExplorerCore

/// Exactly one shared action shelf. Pane summaries stay beside their own data;
/// enabling Commander never appends another full-width row of duplicate tools.
struct WorkspaceFooter: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var settings = CommanderPreferences.shared
    var body: some View {
        if let panes = workspace.paneController {
            DualWorkspaceFooter(workspace: workspace, panes: panes)
        } else if settings.showCommandBar {
            WorkspaceActionShelf(workspace: workspace, tab: tab)
        } else {
            ExplorerStatusBar(workspace: workspace, tab: tab)
        }
    }
}
private struct DualWorkspaceFooter: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var panes: DualPaneController
    var body: some View {
        WorkspaceActionShelf(workspace: workspace, tab: workspace.current,
            preparing: panes.preparingTransfer, notice: panes.transferNotice,
            cancel: panes.cancelTransferPreparation)
    }
}
struct WorkspaceActionShelf: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var settings = CommanderPreferences.shared
    @ObservedObject private var input = InputPreferences.shared
    var preparing = false
    var notice: String?
    var cancel: () -> Void = {}
    @State private var showNotice = false
    var body: some View {
        GeometryReader { geometry in
            let layout = WorkspaceChromeLayout(width: geometry.size.width, touch: input.touchFriendly)
            HStack(spacing: layout.compactActions ? 8 : 12) {
                if settings.showCommandBar {
                    CommanderCommandBar(workspace: workspace, compact: layout.compactActions)
                        .explorerRegion("footer.commands")
                } else {
                    PaneLayoutMenu(workspace: workspace)
                    transferActions
                }
                Divider().frame(height: 18)
                context(layout: layout).frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(-1).explorerRegion("footer.context")
                if settings.showCommandBar {
                    Menu {
                        CommanderMenuActions(workspace: workspace, actions: [.selectMask, .invert, .sameExtension])
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                            .labelStyle(.titleOnly).frame(minHeight: input.touchFriendly ? 44 : 28)
                    }.menuStyle(.borderlessButton).fixedSize()
                        .disabled(WorkspaceCommandScope.target(workspace) !== workspace)
                        .accessibilityLabel("Selection tools").explorerRegion("footer.selectionTools")
                }
                FileActivityButton(compact: layout.compactActions).explorerRegion("footer.activity")
                PowerToolsMenu(workspace: workspace, compactLabel: true).explorerRegion("footer.tools")
            }.font(.system(size: 11)).foregroundStyle(ExplorerDesign.text)
                .padding(.horizontal, 12).frame(height: layout.footerHeight)
        }.frame(height: WorkspaceChromeLayout(width: 0, touch: input.touchFriendly).footerHeight)
            .background(ExplorerDesign.chrome).accessibilityIdentifier("explorer.actionShelf")
    }
    @ViewBuilder private func context(layout: WorkspaceChromeLayout) -> some View {
        if preparing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).accessibilityLabel("Checking transfer")
                if !layout.compactActions { Text("Checking transfer…").lineLimit(1) }
                Button("Cancel", action: cancel).buttonStyle(.plain)
                    .frame(minHeight: input.touchFriendly ? 44 : 28).fixedSize()
                    .accessibilityLabel("Cancel transfer preparation")
            }
        } else if let notice {
            Button { showNotice.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                    if !layout.compactActions { Text(notice).lineLimit(1) }
                }.frame(minHeight: input.touchFriendly ? 44 : 28)
            }.buttonStyle(.plain).help(notice).accessibilityLabel(notice)
                .popover(isPresented: $showNotice) { Text(notice).font(.callout).padding(18).frame(width: 310) }
        } else if let other = workspace.paneController?.other(than: workspace) {
            Button {
                guard WorkspaceCommandScope.target(workspace) === workspace else { return }
                other.editLocation()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.right").foregroundStyle(Color.accentColor)
                    if layout.showsDestination {
                        Text("TO").font(.system(size: 9, weight: .semibold)).foregroundStyle(ExplorerDesign.muted)
                    }
                    Text(other.current.location.title).lineLimit(1).truncationMode(.middle)
                    if !layout.compactActions { Text("Change…").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted) }
                }.frame(minHeight: input.touchFriendly ? 44 : 28)
            }.buttonStyle(.plain).disabled(WorkspaceCommandScope.target(workspace) !== workspace)
                .help("Transfer destination: " + other.current.location.displayPath + ". Click to edit the other pane's path.")
                .accessibilityLabel("Edit transfer destination: " + other.current.location.displayPath)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.location.isArchive ? "\(tab.archiveSelectionCount) selected" : "\(tab.selectionStatistics.count) selected")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit().lineLimit(1)
                if !layout.compactActions {
                    Text(tab.location.title).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(1)
                }
            }.help("Selection details remain available in Properties. File sizes do not scan folder contents.")
        }
    }
    private var transferActions: some View {
        HStack(spacing: 6) {
            ForEach([CommanderAction.copy, .move]) { action in
                Button { action.perform(in: workspace) } label: {
                    Label(action.title, systemImage: action.symbol).padding(.horizontal, 9)
                        .frame(minHeight: input.touchFriendly ? 44 : 28)
                }.buttonStyle(ExplorerIconStyle(selected: action == .copy))
                    .disabled(!action.enabled(in: workspace)).help(action.title + " to the other pane")
            }
        }.fixedSize()
    }
}
struct PaneLayoutMenu: View {
    @ObservedObject var workspace: ExplorerWorkspace
    var body: some View {
        Menu {
            ForEach([WorkspaceLayoutAction.single, .split, .stacked, .switchPane, .equalize, .swap, .sameLocation, .compare]) { action in
                Button { action.perform(workspace) } label: { Label(action.title, systemImage: action.symbol) }
                    .disabled(!action.enabled(workspace))
            }
        } label: { Label("Panes", systemImage: "rectangle.split.2x1") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Pane layout and navigation")
    }
}
