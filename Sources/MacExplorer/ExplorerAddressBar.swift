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
            CommandIcon("Back (Alt+Left)", "chevron.left", disabled: !tab.history.canGoBack) { tab.back() }
            CommandIcon("Forward (Alt+Right)", "chevron.right", disabled: !tab.history.canGoForward) { tab.forward() }
            CommandIcon("Up (Alt+Up)", "arrow.up", disabled: tab.location.directory == nil) { tab.up() }
            CommandIcon("Refresh (F5)", "arrow.clockwise") { tab.refresh() }
            HStack(spacing: 5) {
                Image(systemName: tab.location.symbol).foregroundStyle(.tint).padding(.leading, 11)
                if workspace.addressFocused {
                    TextField("Folder path", text: $address).textFieldStyle(.plain).focused($pathFocus)
                        .onSubmit { workspace.goToAddress(address); workspace.addressFocused = false }
                        .onExitCommand { workspace.addressFocused = false }
                        .accessibilityIdentifier("explorer.pathEditor")
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 3) {
                                if ancestors.isEmpty { Text(tab.location.title).padding(.horizontal, 5) }
                                else {
                                    ForEach(ancestors, id: \.self) { url in
                                        Button { workspace.navigate(.folder(url)) } label: {
                                            Text(url.path == "/" ? "Macintosh HD" : url.lastPathComponent).lineLimit(1)
                                        }.buttonStyle(.plain).padding(.horizontal, 4).id(url)
                                            .contextMenu {
                                                Button("Open in New Tab") { workspace.newTab(.folder(url)) }
                                                Button("Copy Path") { NativeIntegration.copyPaths([url]) }
                                            }
                                        if url != ancestors.last { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary) }
                                    }
                                }
                            }
                        }.onTapGesture(count: 2) { workspace.addressFocused = true }
                            .onAppear { if let last = ancestors.last { proxy.scrollTo(last, anchor: .trailing) } }
                            .onChange(of: tab.location) { _, _ in if let last = ancestors.last { proxy.scrollTo(last, anchor: .trailing) } }
                    }
                }
                Menu {
                    Button("Edit address") { workspace.addressFocused = true }
                    if let url = tab.location.directory { Button("Copy Path") { NativeIntegration.copyPaths([url]) } }
                    Divider()
                    ForEach(Array(tab.history.locations.enumerated()), id: \.offset) { _, location in
                        Button(location.directory?.path ?? location.title) { workspace.navigate(location) }
                    }
                } label: { Image(systemName: "chevron.down").font(.system(size: 9)).frame(width: 24, height: 30) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Address history")
            }.frame(height: 34).background(ExplorerDesign.surface, in: RoundedRectangle(cornerRadius: ExplorerDesign.radius))
                .overlay(RoundedRectangle(cornerRadius: ExplorerDesign.radius).stroke(pathFocus ? Color.accentColor : ExplorerDesign.separator, lineWidth: pathFocus ? 1.5 : 0.5))
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(tab.location.title)", text: $tab.query).textFieldStyle(.plain).focused($searchFocus)
                    .onExitCommand { if tab.query.isEmpty { searchFocus = false } else { tab.query = "" } }
                    .accessibilityLabel("Search files").accessibilityIdentifier("explorer.searchEditor")
                if !tab.query.isEmpty {
                    Button { tab.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(.horizontal, 11).frame(width: searchWidth, height: 34)
                .background(ExplorerDesign.surface, in: RoundedRectangle(cornerRadius: ExplorerDesign.radius))
                .overlay(RoundedRectangle(cornerRadius: ExplorerDesign.radius).stroke(searchFocus ? Color.accentColor : ExplorerDesign.separator, lineWidth: searchFocus ? 1.5 : 0.5))
        }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: ExplorerDesign.addressHeight).background(.bar)
            .onChange(of: workspace.addressFocused) { _, focused in
                if focused { address = tab.location.directory?.path ?? FileManager.default.homeDirectoryForCurrentUser.path }
                pathFocus = focused
            }
            .onChange(of: pathFocus) { _, focused in if !focused { workspace.addressFocused = false } }
            .onChange(of: workspace.searchFocused) { _, focused in searchFocus = focused }
            .onChange(of: searchFocus) { _, focused in workspace.searchFocused = focused }
    }
}

struct SearchControls: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    var body: some View {
        ViewThatFits(in: .horizontal) {
            controls(showTitle: true)
            controls(showTitle: false)
        }.font(.caption).padding(10).background(.tint.opacity(0.06))
    }
    private func controls(showTitle: Bool) -> some View {
        HStack(spacing: 8) {
            if showTitle { Label("Search results", systemImage: "magnifyingglass").fontWeight(.medium).fixedSize() }
            Picker("Search scope", selection: $tab.allLocations) { Text("This folder").tag(false); Text("This Mac").tag(true) }
                .labelsHidden().frame(width: 122)
            Spacer(minLength: 0)
            Menu("Refine") {
                ForEach(["kind:folder", "kind:image", "ext:pdf", "size:>10MB", "modified:today", "modified:week", "tag:Work", "content:\"text to find\""], id: \.self) { token in Button(token) { tab.query += " " + token } }
                Divider()
                Button("Save Search") { if !preferences.value.savedSearches.contains(tab.query) { preferences.value.savedSearches.append(tab.query) } }
            }.fixedSize()
        }
    }
}
