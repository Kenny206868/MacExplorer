import SwiftUI
import AppKit
import ExplorerCore

extension Notification.Name { static let explorerEditPath = Notification.Name("MacExplorer.editPath") }
@MainActor extension ExplorerWorkspace {
    func editLocation() {
        activatePane(); fileSurfaceFocused = false; addressFocused = true
        NotificationCenter.default.post(name: .explorerEditPath, object: id)
    }
}

/// Identical full-path entry in Explorer and both Commander panes. Completion
/// is an inline SwiftUI shelf, not another key window or modal menu loop.
@MainActor struct LocationPathControl: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @StateObject private var editor: PathEditorModel
    @ObservedObject private var input = InputPreferences.shared
    init(workspace: ExplorerWorkspace, tab: BrowserTab, editor: PathEditorModel? = nil) {
        self.workspace = workspace; self.tab = tab; _editor = StateObject(wrappedValue: editor ?? PathEditorModel())
    }
    private var base: URL { tab.location.directory ?? tab.location.archiveSource?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser }
    private var display: String {
        guard let directory = tab.location.directory else { return tab.location.displayPath }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if directory.path == home { return "~" }
        return directory.path.hasPrefix(home + "/") ? "~" + directory.path.dropFirst(home.count) : directory.path
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            if editor.editing && (!editor.suggestions.isEmpty || editor.error != nil || editor.completionNote != nil || editor.completing) { completionShelf }
        }.onChange(of: workspace.addressFocused) { _, value in
            if value { begin() } else if editor.editing { editor.cancel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .explorerEditPath)) { event in if event.object as? UUID == workspace.id { begin() } }
        .onChange(of: editor.editing) { _, editing in if !editing && workspace.addressFocused { workspace.addressFocused = false } }
        .onChange(of: tab.location) { _, _ in editor.cancel(); workspace.addressFocused = false }
        .onChange(of: workspace.activeID) { _, _ in editor.cancel(); workspace.addressFocused = false }
        .onDisappear { editor.cancel() }
        .onAppear { if workspace.addressFocused { begin() } }
    }
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.location.symbol).font(.system(size: 13)).foregroundStyle(Color.accentColor)
            if editor.editing {
                NativePathField(model: editor, label: "Folder path for " + tab.location.title).frame(minWidth: 40).accessibilityIdentifier("explorer.pathEditor")
            } else {
                Button(action: begin) {
                    Text(display).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: input.target).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Edit full path · ⌘L / Ctrl+L / F4").accessibilityLabel("Edit location: " + display)
            }
            if editor.resolving { ProgressView().controlSize(.mini).accessibilityLabel("Checking location") }
            if editor.editing {
                Button { editor.cancel(); workspace.focusFileSurface() } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 22, height: input.target) }
                    .buttonStyle(.plain).accessibilityLabel("Cancel path editing")
            } else {
                Menu {
                    Button("Edit Full Path…", action: begin)
                    Button("Copy Path") { NativeIntegration.copyPaths([tab.location.archiveSource ?? base]) }
                    Button("Open Location in New Tab") { workspace.newTab(tab.location) }
                    Divider()
                    ForEach(ancestors, id: \.self) { url in Button(url.path == "/" ? "Macintosh HD" : url.lastPathComponent) { workspace.activatePane(); workspace.navigate(.folder(url)) } }
                } label: { Image(systemName: "chevron.down").font(.system(size: 9)).frame(width: 22, height: input.target) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Location history and parent folders")
            }
        }.padding(.leading, 11).padding(.trailing, 5).frame(height: input.target)
            .foregroundStyle(ExplorerDesign.text).background(ExplorerDesign.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(editor.error != nil ? Color.orange : editor.editing ? Color.accentColor : ExplorerDesign.separator, lineWidth: editor.editing ? 1.5 : 1))
    }
    private var completionShelf: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let error = editor.error {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).padding(8)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(editor.suggestions.enumerated()), id: \.element.id) { index, item in
                                Button { editor.acceptCompletion(index) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder").foregroundStyle(Color.accentColor); Text(item.title).lineLimit(1); Spacer(minLength: 0)
                                        if editor.highlighted == index { Text("↩").foregroundStyle(ExplorerDesign.muted) }
                                    }.font(.system(size: 12)).padding(.horizontal, 9).frame(height: input.touchFriendly ? 44 : 28)
                                        .background(editor.highlighted == index ? ExplorerDesign.selection : .clear, in: RoundedRectangle(cornerRadius: 4))
                                }.buttonStyle(.plain).id(index).accessibilityLabel("Complete folder " + item.title)
                            }
                        }
                    }.frame(height: min(CGFloat(editor.suggestions.count) * (input.touchFriendly ? 46 : 30), input.touchFriendly ? 184 : 120))
                        .onChange(of: editor.highlighted) { _, value in if let value { proxy.scrollTo(value) } }
                }
                if editor.completing { HStack { ProgressView().controlSize(.mini); Text("Finding folders…").font(.caption) }.padding(6) }
                Text(editor.completionNote ?? "Tab completes · Return opens · ⌘Return opens a new tab · Esc cancels")
                    .font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).fixedSize(horizontal: false, vertical: true).padding(7)
            }
        }.padding(4).background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(ExplorerDesign.separator, lineWidth: 1)).padding(.top, 5)
            .accessibilityIdentifier("explorer.pathSuggestions")
    }
    private var ancestors: [URL] {
        var value = base, result = [base]
        while value.path != "/" { value = value.deletingLastPathComponent(); result.append(value) }; return result
    }
    private func begin() {
        guard workspace.current === tab, WorkspaceCommandScope.target(workspace) != nil else { return }
        workspace.activatePane(); workspace.fileSurfaceFocused = false; workspace.addressFocused = true
        if editor.editing { editor.requestFocus(selectAll: true); return }
        let origin = tab.location, tabID = tab.id
        editor.committed = { [weak workspace, weak tab] result, newTab in
            guard let workspace, let tab, workspace.current.id == tabID, tab.location == origin,
                  WorkspaceCommandScope.target(workspace) === workspace else { return }
            workspace.addressFocused = false
            switch result {
            case .folder(let url): workspace.navigate(.folder(url), newTab: newTab)
            case .file(let url):
                workspace.navigate(.folder(url.deletingLastPathComponent()), newTab: newTab); workspace.current.refresh(selecting: [url])
            case .server(let url): NativeIntegration.connect(url.absoluteString, owner: workspace)
            }
            workspace.focusFileSurface()
        }
        editor.begin(text: base.path, base: base, showHidden: workspace.preferences.value.showHidden)
    }
}
