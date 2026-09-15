import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerAddressBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    var searchWidth: CGFloat = 230
    @FocusState private var searchFocus: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 2) {
                CommandIcon("Back (Alt+Left)", "arrow.left", disabled: !tab.history.canGoBack) { tab.back() }
                CommandIcon("Forward (Alt+Right)", "arrow.right", disabled: !tab.history.canGoForward) { tab.forward() }
                CommandIcon("Up (Alt+Up)", "arrow.up", disabled: tab.location.directory == nil && !tab.location.isArchive) { tab.up() }
                CommandIcon("Refresh (F5)", "arrow.clockwise") { tab.refresh() }
            }.padding(.trailing, 3)
            LocationPathControl(workspace: workspace, tab: tab).frame(maxWidth: .infinity).layoutPriority(1)
            searchField
        }.font(.system(size: 12)).foregroundStyle(ExplorerDesign.text).padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: ExplorerDesign.addressHeight).background(ExplorerDesign.canvas)
            .onChange(of: workspace.searchFocused) { _, value in searchFocus = value }
            .onChange(of: searchFocus) { _, value in workspace.searchFocused = value }
    }
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(ExplorerDesign.muted)
            TextField("Search \(tab.location.title)", text: $tab.query).textFieldStyle(.plain).focused($searchFocus)
                .onExitCommand { if tab.query.isEmpty { searchFocus = false } else { tab.query = "" } }
                .accessibilityLabel("Search files").accessibilityIdentifier("explorer.searchEditor")
            if !tab.query.isEmpty {
                Button { tab.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(ExplorerDesign.muted) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 11).frame(width: searchWidth, height: 33)
            .background(ExplorerDesign.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(searchFocus ? Color.accentColor : ExplorerDesign.separator, lineWidth: searchFocus ? 1.5 : 1))
    }
}
struct SearchControls: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    var body: some View {
        Group {
            if tab.location.isArchive { HStack { Label("Archive member names", systemImage: "doc.zipper"); Spacer(); Text("Current archive folder").foregroundStyle(.secondary) } }
            else { ViewThatFits(in: .horizontal) { controls(showTitle: true); controls(showTitle: false) } }
        }.font(.system(size: 11)).padding(10).background(ExplorerDesign.selection.opacity(0.45))
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
