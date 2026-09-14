import SwiftUI
import AppKit
import ExplorerCore

/// A stable editing identity belongs to the pane, not to whichever pane was
/// last active. Navigation and search remain independent during transfers.
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
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                CommandIcon("Back", "chevron.left", disabled: !tab.history.canGoBack) { workspace.activatePane(); tab.back() }
                CommandIcon("Forward", "chevron.right", disabled: !tab.history.canGoForward) { workspace.activatePane(); tab.forward() }
                CommandIcon("Parent folder", "arrow.up", disabled: workspace.destination == nil) { workspace.activatePane(); tab.up() }
                HStack(spacing: 7) {
                    Image(systemName: tab.location.symbol).foregroundStyle(Color.accentColor).font(.system(size: 12))
                    if pathFocused || workspace.addressFocused {
                        TextField("Folder path", text: $path).textFieldStyle(.plain).focused($pathFocused)
                            .onSubmit { let value = path; pathFocused = false; workspace.addressFocused = false; workspace.goToAddress(value) }
                            .onExitCommand { pathFocused = false; workspace.focusFileSurface() }
                    } else {
                        Menu {
                            Button("Edit Location…", action: edit)
                            if let url = workspace.destination { Button("Copy Path") { NativeIntegration.copyPaths([url]) } }
                            Divider()
                            ForEach(parents, id: \.self) { url in Button(url.path == "/" ? "Macintosh HD" : url.lastPathComponent) { workspace.activatePane(); workspace.navigate(.folder(url)) } }
                        } label: {
                            HStack(spacing: 6) {
                                if parents.count > 1 { Text("…").foregroundStyle(ExplorerDesign.muted); Image(systemName: "chevron.right").font(.system(size: 8)) }
                                Text(tab.location.title).lineLimit(1).truncationMode(.middle).fontWeight(.medium)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down").font(.system(size: 8))
                            }.contentShape(Rectangle())
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).help(tab.location.directory?.path ?? tab.location.title)
                    }
                }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: input.target)
                    .background(ExplorerDesign.canvas, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(pathFocused ? Color.accentColor : ExplorerDesign.separator, lineWidth: 1))
                CommandIcon("Search this pane", "magnifyingglass", selected: showsSearch || !tab.query.isEmpty) {
                    workspace.activatePane(); showsSearch.toggle(); workspace.searchFocused = showsSearch; queryFocused = showsSearch
                }
                CommandIcon("Refresh", "arrow.clockwise") { tab.refresh() }
            }.padding(.horizontal, 10).padding(.vertical, 8)
            if showsSearch || !tab.query.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(ExplorerDesign.muted)
                    TextField("Search \(tab.location.title)", text: $tab.query).textFieldStyle(.plain).focused($queryFocused)
                        .onExitCommand { if tab.query.isEmpty { showsSearch = false; workspace.focusFileSurface() } else { tab.query = "" } }
                    Button { tab.query = ""; showsSearch = false; workspace.focusFileSurface() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(ExplorerDesign.muted).accessibilityLabel("Clear search")
                }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: input.target)
                    .background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 6)).padding(.horizontal, 12).padding(.bottom, 8)
            }
            ExplorerRule()
        }.background(ExplorerDesign.canvas)
            .onChange(of: workspace.addressFocused) { _, value in if value { edit() } else { pathFocused = false } }
            .onChange(of: workspace.searchFocused) { _, value in if value { showsSearch = true }; queryFocused = value }
            .onChange(of: pathFocused) { _, value in workspace.addressFocused = value; if value { workspace.activatePane(); workspace.fileSurfaceFocused = false } }
            .onChange(of: queryFocused) { _, value in workspace.searchFocused = value; if value { workspace.activatePane(); workspace.fileSurfaceFocused = false } }
            .onChange(of: workspace.activeID) { _, _ in pathFocused = false; queryFocused = false }
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
                        ForEach(workspace.tabs) { tab in
                            PaneTabButton(workspace: workspace, tab: tab).id(tab.id)
                        }
                    }
                }.onChange(of: workspace.activeID) { _, id in proxy.scrollTo(id) }
            }
            CommandIcon("New tab in this pane", "plus") { workspace.activatePane(); workspace.newTab() }
            Menu {
                ForEach(workspace.tabs) { tab in Button(tab.location.title) { workspace.activatePane(); workspace.activeID = tab.id } }
                Divider(); Button("Reopen Closed Tab") { workspace.reopenClosedTab() }.disabled(workspace.closedTabs.isEmpty)
                Button("Swap Pane Locations") { controller.swapLocations() }
            } label: { Image(systemName: "chevron.down").font(.system(size: 9)).frame(width: input.target, height: input.target) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Pane tabs")
        }.padding(.horizontal, 8).frame(height: input.touchFriendly ? 54 : 44).background(ExplorerDesign.chrome)
    }
}
private struct PaneTabButton: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @Environment(\.openWindow) private var openWindow
    @State private var hovered = false
    private var selected: Bool { tab.id == workspace.activeID }
    var body: some View {
        HStack(spacing: 8) {
            Button { workspace.activatePane(); workspace.activeID = tab.id } label: {
                HStack(spacing: 7) {
                    Image(systemName: tab.location.symbol).foregroundStyle(selected ? Color.accentColor : ExplorerDesign.muted)
                    Text(tab.location.title).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { workspace.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 8)).frame(width: 20, height: 30) }
                .buttonStyle(ExplorerIconStyle()).accessibilityLabel("Close " + tab.location.title)
        }.font(.system(size: 12, weight: selected ? .medium : .regular)).padding(.horizontal, 9).frame(width: 176, height: 34)
            .background(selected ? ExplorerDesign.canvas : hovered ? ExplorerDesign.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? ExplorerDesign.separator : .clear, lineWidth: 1))
            .onHover { hovered = $0 }.help(tab.location.directory?.path ?? tab.location.title)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .contextMenu {
                Button("Duplicate Tab") { workspace.duplicateTab(tab) }
                Button("Move to Other Pane") { workspace.paneController?.other(than: workspace)?.receiveTab(from: workspace, id: tab.id, before: nil) }
                Button("Move to New Window") { openWindow(id: "detached", value: tab.session()); workspace.closeTab(tab.id) }
                Divider(); Button("Close Other Tabs") { workspace.closeOtherTabs(keeping: tab.id) }
                Button("Close Tabs to the Right") { workspace.closeOtherTabs(keeping: tab.id, toRightOnly: true) }
            }
    }
}
