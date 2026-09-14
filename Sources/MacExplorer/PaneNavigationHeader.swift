import SwiftUI
import AppKit
import ExplorerCore

struct PaneNavigationHeader: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var input = InputPreferences.shared
    @State private var path = ""
    @FocusState private var pathFocused: Bool
    @FocusState private var queryFocused: Bool
    @State private var showsSearch = false
    private var parents: [URL] {
        guard var value = tab.location.directory else { return [] }
        var result = [value]
        while value.path != "/" { value = value.deletingLastPathComponent(); result.insert(value, at: 0) }
        return result
    }
    private var side: String { workspace.parentWorkspace == nil ? "primary" : "secondary" }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                CommandIcon("Back", "chevron.left", disabled: !tab.history.canGoBack) { workspace.activatePane(); tab.back() }
                CommandIcon("Forward", "chevron.right", disabled: !tab.history.canGoForward) { workspace.activatePane(); tab.forward() }
                CommandIcon("Parent folder", "arrow.up", disabled: workspace.destination == nil) { workspace.activatePane(); tab.up() }
                pathControl.frame(maxWidth: .infinity).layoutPriority(1).explorerRegion("pane.address." + side)
                CommandIcon("Search this pane", "magnifyingglass", selected: showsSearch || !tab.query.isEmpty) {
                    workspace.activatePane(); showsSearch.toggle(); workspace.searchFocused = showsSearch; queryFocused = showsSearch
                }
                CommandIcon("Refresh", "arrow.clockwise") { tab.refresh() }
            }.padding(.horizontal, 10).padding(.vertical, 8)
            if showsSearch || !tab.query.isEmpty { searchControl }
            ExplorerRule()
        }.background(ExplorerDesign.canvas)
            .onChange(of: workspace.addressFocused) { _, value in if value { edit() } else { pathFocused = false } }
            .onChange(of: workspace.searchFocused) { _, value in if value { showsSearch = true }; queryFocused = value }
            .onChange(of: pathFocused) { _, value in workspace.addressFocused = value; if value { workspace.activatePane(); workspace.fileSurfaceFocused = false } }
            .onChange(of: queryFocused) { _, value in workspace.searchFocused = value; if value { workspace.activatePane(); workspace.fileSurfaceFocused = false } }
            .onChange(of: workspace.activeID) { _, _ in pathFocused = false; queryFocused = false }
    }
    private var pathControl: some View {
        HStack(spacing: 7) {
            Image(systemName: tab.location.symbol).foregroundStyle(Color.accentColor).font(.system(size: 12))
            if pathFocused || workspace.addressFocused {
                TextField("Folder path", text: $path).textFieldStyle(.plain).focused($pathFocused)
                    .onSubmit { let value = path; pathFocused = false; workspace.addressFocused = false; workspace.goToAddress(value) }
                    .onExitCommand { pathFocused = false; workspace.focusFileSurface() }
            } else {
                Button(action: edit) {
                    Text(tab.location.title).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: input.target).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Edit location: " + tab.location.title)
            }
            Menu {
                Button("Edit Location…", action: edit)
                if let url = workspace.destination { Button("Copy Path") { NativeIntegration.copyPaths([url]) } }
                Divider()
                ForEach(parents, id: \.self) { url in
                    Button(url.path == "/" ? "Macintosh HD" : url.lastPathComponent) { workspace.activatePane(); workspace.navigate(.folder(url)) }
                }
            } label: { Image(systemName: "chevron.down").font(.system(size: 8)).frame(width: 20, height: input.target) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Parent folders")
        }.font(.system(size: 12)).padding(.leading, 10).padding(.trailing, 5).frame(maxWidth: .infinity).frame(height: input.target)
            .background(ExplorerDesign.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(pathFocused ? Color.accentColor : ExplorerDesign.separator, lineWidth: 1))
            .help(tab.location.directory?.path ?? tab.location.title)
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
    private func edit() {
        workspace.activatePane(); path = tab.location.directory?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        workspace.addressFocused = true; workspace.fileSurfaceFocused = false; pathFocused = true
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
            Button { controller.focus(side, files: true) } label: {
                Text(side == .primary ? "1" : "2").font(.system(size: 10, weight: .semibold))
                    .frame(width: input.touchFriendly ? 36 : 22, height: input.target)
                    .foregroundStyle(active ? Color.accentColor : ExplorerDesign.muted)
            }.buttonStyle(.plain).accessibilityLabel("Focus pane \(side == .primary ? 1 : 2)")
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
