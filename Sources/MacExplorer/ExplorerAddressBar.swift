import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerAddressBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    var searchWidth: CGFloat = 230
    @State private var address = ""
    @FocusState private var pathFocus: Bool
    @FocusState private var searchFocus: Bool
    private var ancestors: [URL] {
        guard var url = tab.location.directory else { return [] }
        var result = [url]
        while url.path != "/" { url = url.deletingLastPathComponent(); result.insert(url, at: 0) }
        return result
    }
    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                CommandIcon("Back (Alt+Left)", "arrow.left", disabled: !tab.history.canGoBack) { tab.back() }
                CommandIcon("Forward (Alt+Right)", "arrow.right", disabled: !tab.history.canGoForward) { tab.forward() }
                CommandIcon("Up (Alt+Up)", "arrow.up", disabled: tab.location.directory == nil) { tab.up() }
                CommandIcon("Refresh (F5)", "arrow.clockwise") { tab.refresh() }
            }.padding(.trailing, 5)
            addressField
            searchField
        }.font(.system(size: 12)).foregroundStyle(ExplorerDesign.text).padding(.horizontal, 16)
            .frame(height: ExplorerDesign.addressHeight).background(ExplorerDesign.canvas)
            .onChange(of: workspace.addressFocused) { _, focused in
                if focused { address = tab.location.directory?.path ?? FileManager.default.homeDirectoryForCurrentUser.path }; pathFocus = focused
            }
            .onChange(of: pathFocus) { _, focused in if !focused { workspace.addressFocused = false } }
            .onChange(of: workspace.searchFocused) { _, focused in searchFocus = focused }
            .onChange(of: searchFocus) { _, focused in workspace.searchFocused = focused }
    }
    private var addressField: some View {
        HStack(spacing: 7) {
            Image(systemName: tab.location.symbol).font(.system(size: 13)).foregroundStyle(Color.accentColor).padding(.leading, 12)
            if workspace.addressFocused {
                TextField("Folder path", text: $address).textFieldStyle(.plain).focused($pathFocus)
                    .onSubmit { workspace.goToAddress(address); workspace.addressFocused = false }
                    .onExitCommand { workspace.addressFocused = false }.accessibilityIdentifier("explorer.pathEditor")
            } else {
                GeometryReader { geometry in
                    let values = ancestors
                    let tail = geometry.size.width > 560 ? 3 : geometry.size.width > 360 ? 2 : 1
                    HStack(spacing: 7) {
                        if values.isEmpty { Text(tab.location.title).lineLimit(1) }
                        else {
                            if values.count > tail {
                                Menu {
                                    ForEach(values.dropLast(tail), id: \.self) { url in Button(title(url)) { workspace.navigate(.folder(url)) } }
                                } label: { Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 18, height: 28) }
                                    .menuStyle(.borderlessButton).menuIndicator(.hidden).help("Parent folders").accessibilityLabel("Parent folders")
                                chevron
                            }
                            ForEach(values.suffix(tail), id: \.self) { url in
                                Button { workspace.navigate(.folder(url)) } label: {
                                    Text(title(url)).lineLimit(1).truncationMode(.middle).fontWeight(url == values.last ? .medium : .regular)
                                }.buttonStyle(.plain).help(url.path)
                                    .contextMenu { Button("Open in New Tab") { workspace.newTab(.folder(url)) }; Button("Copy Path") { NativeIntegration.copyPaths([url]) } }
                                if url != values.last { chevron }
                            }
                        }
                        Spacer(minLength: 0)
                    }.frame(height: 32).contentShape(Rectangle()).onTapGesture(count: 2) { workspace.addressFocused = true }
                }.frame(height: 32)
            }
            Menu {
                Button("Edit address") { workspace.addressFocused = true }
                if let url = tab.location.directory { Button("Copy Path") { NativeIntegration.copyPaths([url]) } }
                Divider()
                ForEach(Array(tab.history.locations.enumerated()), id: \.offset) { _, location in Button(location.directory?.path ?? location.title) { workspace.navigate(location) } }
            } label: { Image(systemName: "chevron.down").font(.system(size: 9)).frame(width: 25, height: 30) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Address history")
        }.frame(height: 33).background(ExplorerDesign.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(pathFocus ? Color.accentColor : ExplorerDesign.separator, lineWidth: pathFocus ? 1.5 : 1))
    }
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(ExplorerDesign.muted)
            TextField("Search \(tab.location.title)", text: $tab.query).textFieldStyle(.plain).focused($searchFocus)
                .onExitCommand { if tab.query.isEmpty { searchFocus = false } else { tab.query = "" } }
                .accessibilityLabel("Search files").accessibilityIdentifier("explorer.searchEditor")
            if !tab.query.isEmpty {
                Button { tab.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(ExplorerDesign.muted) }.buttonStyle(.plain).accessibilityLabel("Clear search")
            } else if searchWidth >= 240 {
                Text("⌘F").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).padding(.horizontal, 4).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(ExplorerDesign.separator, lineWidth: 1)).accessibilityHidden(true)
            }
        }.padding(.horizontal, 11).frame(width: searchWidth, height: 33)
            .background(ExplorerDesign.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(searchFocus ? Color.accentColor : ExplorerDesign.separator, lineWidth: searchFocus ? 1.5 : 1))
    }
    private var chevron: some View { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(ExplorerDesign.muted) }
    private func title(_ url: URL) -> String { url.path == "/" ? "Macintosh HD" : url == FileManager.default.homeDirectoryForCurrentUser ? NSUserName() : url.lastPathComponent }
}
struct SearchControls: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    var body: some View {
        ViewThatFits(in: .horizontal) { controls(showTitle: true); controls(showTitle: false) }
            .font(.system(size: 11)).padding(10).background(ExplorerDesign.selection.opacity(0.45))
    }
    private func controls(showTitle: Bool) -> some View {
        HStack(spacing: 8) {
            if showTitle { Label("Search results", systemImage: "magnifyingglass").fontWeight(.medium).fixedSize() }
            Picker("Search scope", selection: $tab.allLocations) { Text("This folder").tag(false); Text("This Mac").tag(true) }.labelsHidden().frame(width: 122)
            Spacer(minLength: 0)
            Menu("Refine") {
                ForEach(["kind:folder", "kind:image", "ext:pdf", "size:>10MB", "modified:today", "modified:week", "tag:Work", "content:\"text to find\""], id: \.self) { token in Button(token) { tab.query += " " + token } }
                Divider(); Button("Save Search") { if !preferences.value.savedSearches.contains(tab.query) { preferences.value.savedSearches.append(tab.query) } }
            }.fixedSize()
        }
    }
}
