import SwiftUI
import AppKit
import ExplorerCore

struct PaneNavigationHeader: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var input = InputPreferences.shared
    @ObservedObject private var commander = CommanderPreferences.shared
    @FocusState private var queryFocused: Bool
    @State private var showsSearch = false
    private var side: String { workspace.parentWorkspace == nil ? "primary" : "secondary" }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                CommandIcon("Back", "chevron.left", disabled: !tab.history.canGoBack) { workspace.activatePane(); tab.back() }
                CommandIcon("Forward", "chevron.right", disabled: !tab.history.canGoForward) { workspace.activatePane(); tab.forward() }
                CommandIcon("Parent folder", "arrow.up", disabled: workspace.destination == nil && !tab.location.isArchive) { workspace.activatePane(); tab.up() }
                LocationPathControl(workspace: workspace, tab: tab).frame(maxWidth: .infinity).layoutPriority(1).explorerRegion("pane.address." + side)
                CommandIcon("Search this pane", "magnifyingglass", selected: showsSearch || !tab.query.isEmpty) {
                    workspace.activatePane(); showsSearch.toggle(); workspace.searchFocused = showsSearch; queryFocused = showsSearch
                }
                if commander.paneTerminalButtons {
                    CommandIcon("Terminal in this pane · ⌥⌘↩", "terminal", disabled: TerminalRequest.directory(for: workspace) == nil) {
                        workspace.activatePane(); TerminalLauncher.shared.open(from: workspace)
                    }.accessibilityIdentifier("explorer.terminal." + side)
                }
                CommandIcon("Refresh", "arrow.clockwise") { tab.refresh() }
            }.padding(.horizontal, 10).padding(.vertical, 8)
            if showsSearch || !tab.query.isEmpty { searchControl }
            ExplorerRule()
        }.background(ExplorerDesign.canvas)
            .onChange(of: workspace.searchFocused) { _, value in if value { showsSearch = true }; queryFocused = value }
            .onChange(of: queryFocused) { _, value in workspace.searchFocused = value; if value { workspace.activatePane(); workspace.fileSurfaceFocused = false } }
            .onChange(of: workspace.activeID) { _, _ in queryFocused = false }
    }
    private var searchControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(ExplorerDesign.muted)
            TextField("Search \(tab.location.title)", text: $tab.query).textFieldStyle(.plain).focused($queryFocused)
                .onExitCommand { if tab.query.isEmpty { showsSearch = false; workspace.focusFileSurface() } else { tab.query = "" } }
            Button { tab.query = ""; showsSearch = false; workspace.focusFileSurface() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(ExplorerDesign.muted).accessibilityLabel("Clear search")
        }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: input.target)
            .background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 6)).padding(.horizontal, 12).padding(.bottom, 8)
    }
}
struct PaneTabHeader: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var controller: DualPaneController
    let side: PaneSide
    @ObservedObject private var input = InputPreferences.shared
    private var active: Bool { controller.geometry.focused == side }
    var body: some View {
        HStack(spacing: 6) {
            Button { controller.focus(side, files: true) } label: { Text(side == .primary ? "1" : "2").font(.system(size: 10, weight: .semibold)).frame(width: input.touchFriendly ? 36 : 22, height: input.target).foregroundStyle(active ? Color.accentColor : ExplorerDesign.muted) }
                .buttonStyle(.plain).accessibilityLabel("Focus pane \(side == .primary ? 1 : 2)")
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(workspace.tabs) { tab in WorkspaceTabItem(workspace: workspace, tab: tab).id(tab.id) }
                        Color.clear.frame(width: 20, height: input.target).contentShape(Rectangle()).modifier(TabDropTarget(workspace: workspace, before: nil))
                    }
                }.onChange(of: workspace.activeID) { _, id in proxy.scrollTo(id) }
            }
            CommandIcon("New tab in this pane", "plus") { workspace.activatePane(); workspace.newTab() }.modifier(TabDropTarget(workspace: workspace, before: nil))
            Menu {
                ForEach(workspace.tabs) { tab in Button(tab.location.title) { workspace.activatePane(); workspace.activeID = tab.id } }
                Divider(); Button("Reopen Closed Tab") { workspace.reopenClosedTab() }.disabled(workspace.closedTabs.isEmpty)
                Button("Swap Pane Locations") { controller.swapLocations() }
            } label: { Image(systemName: "chevron.down").font(.system(size: 9)).frame(width: input.target, height: input.target) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Pane tabs")
        }.padding(.horizontal, 8).frame(height: input.touchFriendly ? 54 : 44).background(ExplorerDesign.chrome)
    }
}
