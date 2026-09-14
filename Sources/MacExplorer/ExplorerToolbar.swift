import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerCommandBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    var compact = false
    @EnvironmentObject private var preferences: PreferenceStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing: compact ? 4 : 7) {
            Menu {
                Button("Folder", systemImage: "folder.badge.plus") { workspace.sheet = .newFolder }.disabled(workspace.destination == nil)
                Button("Text Document", systemImage: "doc.badge.plus") { workspace.sheet = .newFile }.disabled(workspace.destination == nil)
                Divider(); Button("Tab") { workspace.newTab() }; Button("Window") { openWindow(id: "explorer") }
            } label: { ExplorerMenuLabel(title: "New", symbol: "plus") }.fixedSize()
            barDivider
            CommandIcon("Cut", "scissors", disabled: workspace.selected.isEmpty) { workspace.copy(cut: true) }
            CommandIcon("Copy", "square.on.square", disabled: workspace.selected.isEmpty) { workspace.copy() }
            CommandIcon("Paste", "doc.on.clipboard", disabled: workspace.destination == nil) { workspace.paste() }
            if !compact {
                CommandIcon("Rename (F2)", "character.cursor.ibeam", disabled: workspace.selected.isEmpty) { workspace.sheet = .rename }
                ShareLink(items: workspace.selectedURLs) { Image(systemName: "square.and.arrow.up").font(.system(size: 14)).frame(width: 32, height: 32) }
                    .buttonStyle(ExplorerIconStyle()).disabled(workspace.selected.isEmpty).help("Share / AirDrop").accessibilityLabel("Share selected files")
            }
            CommandIcon("Move to Trash", "trash", disabled: workspace.selected.isEmpty) { workspace.delete() }
            barDivider
            Menu {
                Picker("Sort by", selection: $tab.options.sort) { ForEach(SortField.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("Descending", isOn: $tab.options.descending); Toggle("Folders first", isOn: $tab.options.foldersFirst)
                Divider()
                Picker("Group by", selection: $tab.options.group) { ForEach(GroupField.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            } label: { ExplorerMenuLabel(title: "Sort", symbol: "arrow.up.arrow.down") }.fixedSize()
            Menu {
                Picker("Layout", selection: $tab.options.view) { ForEach(ViewMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                Divider()
                Toggle("Compact view", isOn: $preferences.value.compact); Toggle("Item check boxes", isOn: $preferences.value.checkboxes)
                Toggle("File name extensions", isOn: $preferences.value.showExtensions); Toggle("Hidden items", isOn: $preferences.value.showHidden)
                Divider()
                Toggle("Preview pane", isOn: $preferences.value.previewPane); Toggle("Details pane", isOn: $preferences.value.inspector)
            } label: { ExplorerMenuLabel(title: "View", symbol: "square.grid.2x2") }.fixedSize()
            Menu {
                if compact {
                    Button("Rename…") { workspace.sheet = .rename }.disabled(workspace.selected.isEmpty)
                    ShareLink(items: workspace.selectedURLs) { Text("Share…") }.disabled(workspace.selected.isEmpty)
                    Divider()
                }
                Button("Select All") { workspace.selectAll() }; Button("Invert Selection") { workspace.invertSelection() }; Button("Clear Selection") { tab.selection = [] }
                Divider()
                Button("Duplicate") { workspace.duplicate() }.disabled(workspace.selected.isEmpty)
                Button("Compress to ZIP") { workspace.compress() }.disabled(workspace.selected.isEmpty)
                Button("Properties…") { workspace.sheet = .properties }.disabled(workspace.selected.isEmpty)
                Divider()
                Button("Open in Terminal") { if let url = workspace.destination { NativeIntegration.terminal(url, owner: workspace) } }.disabled(workspace.destination == nil)
                Button("Connect to Server…") { workspace.sheet = .connect }; Button("File Operations…") { workspace.sheet = .operations }; Button("Recovery History…") { workspace.sheet = .recovery }
                Divider(); SettingsLink { Text("Folder Options…") }
            } label: { Image(systemName: "ellipsis").frame(width: 30, height: 32) }.help("More actions").accessibilityLabel("More file actions")
            Spacer(minLength: 4)
            CommandIcon("Preview pane", "rectangle.and.text.magnifyingglass", selected: preferences.value.previewPane) { preferences.value.previewPane.toggle() }
            Button { preferences.value.inspector.toggle() } label: {
                HStack(spacing: 8) { Image(systemName: "sidebar.right").font(.system(size: 14)); if !compact { Text("Details").font(.system(size: 12)) } }
                    .padding(.horizontal, 9).frame(height: 32)
            }.buttonStyle(ExplorerIconStyle(selected: preferences.value.inspector)).help("Toggle Details pane").accessibilityLabel("Details pane")
        }.foregroundStyle(ExplorerDesign.text).buttonStyle(ExplorerIconStyle()).menuStyle(.borderlessButton).menuIndicator(.hidden)
            .padding(.horizontal, 16).frame(height: ExplorerDesign.toolbarHeight).background(ExplorerDesign.canvas)
    }
    private var barDivider: some View { Rectangle().fill(ExplorerDesign.separator).frame(width: 1, height: 21).padding(.horizontal, 5) }
}
