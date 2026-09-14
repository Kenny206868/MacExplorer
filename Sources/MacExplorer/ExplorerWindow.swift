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
            .onDisappear { workspace.answerCollision(.cancel); workspace.saveSession() }
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

struct WorkspaceShell: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @ObservedObject private var operations = OperationCenter.shared
    var body: some View {
        VStack(spacing: 0) {
            ExplorerTabStrip(workspace: workspace)
            Divider()
            ExplorerCommandBar(workspace: workspace, tab: tab)
            Divider()
            ExplorerAddressBar(workspace: workspace, tab: tab)
            Divider()
            HSplitView {
                ExplorerSidebar(workspace: workspace, tab: tab).frame(minWidth: 160, idealWidth: 210, maxWidth: 310)
                VStack(spacing: 0) {
                    if !tab.query.isEmpty { SearchControls(tab: tab) }
                    if let error = tab.error {
                        ContentUnavailableView {
                            Label("This location is unavailable", systemImage: "folder.badge.questionmark")
                        } description: { Text(error).textSelection(.enabled) } actions: {
                            Button("Try Again") { tab.refresh() }
                            Button("Privacy Settings") { NativeIntegration.privacySettings() }
                            Button("Choose Folder…") { NativeIntegration.chooseFolder(owner: workspace) }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { ExplorerContent(workspace: workspace, tab: tab) }
                    if !tab.warnings.isEmpty || tab.truncated {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text(tab.truncated ? "Showing the first 25,000 matches. Narrow your search for additional results." : tab.warnings[0]).font(.caption).lineLimit(2).textSelection(.enabled)
                            Spacer()
                            Button("Details") { workspace.fail("Filesystem notices", tab.warnings.joined(separator: "\n")) }.font(.caption)
                        }.padding(10).background(.orange.opacity(0.07))
                    }
                }
                .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                    guard let folder = workspace.destination else { return false }
                    return workspace.drop(providers, to: folder, move: NSEvent.modifierFlags.contains(.shift))
                }
                if preferences.value.previewPane {
                    VStack(spacing: 0) {
                        HStack { Text("Preview").font(.headline); Spacer(); Button { preferences.value.previewPane = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close Preview") }.padding(14)
                        Divider()
                        if let url = workspace.selectedURLs.first { NativePreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity) }
                        else { ContentUnavailableView("Select a file", systemImage: "doc.viewfinder", description: Text("Preview documents, images, audio, and video with macOS Quick Look.")) }
                    }.frame(minWidth: 240, idealWidth: 350, maxWidth: 650)
                }
                if preferences.value.inspector { ExplorerInspector(workspace: workspace, tab: tab).frame(minWidth: 220, idealWidth: 260, maxWidth: 380) }
            }
            Divider()
            HStack(spacing: 16) {
                if tab.loading { ProgressView().controlSize(.mini); Text("Loading…") }
                else { Text("\(tab.entries.count) items") }
                if !tab.selection.isEmpty { Text("\(tab.selection.count) selected"); Text(ByteCountFormatter.string(fromByteCount: workspace.selected.reduce(0) { $0 + $1.size }, countStyle: .file)) }
                Spacer(minLength: 10)
                if operations.runningCount > 0 { Button { workspace.sheet = .operations } label: { Label("\(operations.runningCount) operation(s)", systemImage: "arrow.triangle.2.circlepath") } }
                else { Button { workspace.sheet = .operations } label: { Label("File operations", systemImage: "checkmark.circle") } }
                Button { tab.options.view = .details } label: { Image(systemName: "list.bullet") }.help("Details")
                Button { tab.options.view = .large } label: { Image(systemName: "square.grid.2x2") }.help("Large icons")
            }.font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain).padding(.horizontal, 14).frame(height: 29).background(.bar)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .quickLookPreview($tab.previewURL)
    }
}

struct ExplorerCommandBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Folder", systemImage: "folder.badge.plus") { workspace.sheet = .newFolder }.disabled(workspace.destination == nil)
                Button("Text Document", systemImage: "doc.badge.plus") { workspace.sheet = .newFile }.disabled(workspace.destination == nil)
                Divider(); Button("Tab") { workspace.newTab() }; Button("Window") { openWindow(id: "explorer") }
            } label: { Label("New", systemImage: "plus") }.fixedSize()
            barDivider
            CommandIcon("Cut", "scissors", disabled: workspace.selected.isEmpty) { workspace.copy(cut: true) }
            CommandIcon("Copy", "doc.on.doc", disabled: workspace.selected.isEmpty) { workspace.copy() }
            CommandIcon("Paste", "doc.on.clipboard", disabled: workspace.destination == nil) { workspace.paste() }
            CommandIcon("Rename (F2)", "character.cursor.ibeam", disabled: workspace.selected.isEmpty) { workspace.sheet = .rename }
            ShareLink(items: workspace.selectedURLs) { Image(systemName: "square.and.arrow.up").frame(width: 28, height: 30) }.disabled(workspace.selected.isEmpty).help("Share / AirDrop")
            CommandIcon("Move to Trash", "trash", disabled: workspace.selected.isEmpty) { workspace.delete() }
            barDivider
            Menu {
                Picker("Sort by", selection: $tab.options.sort) { ForEach(SortField.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("Descending", isOn: $tab.options.descending)
                Toggle("Folders first", isOn: $tab.options.foldersFirst)
                Divider()
                Picker("Group by", selection: $tab.options.group) { ForEach(GroupField.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }.fixedSize()
            Menu {
                Picker("Layout", selection: $tab.options.view) { ForEach(ViewMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                Divider()
                Toggle("Compact view", isOn: $preferences.value.compact)
                Toggle("Item check boxes", isOn: $preferences.value.checkboxes)
                Toggle("File name extensions", isOn: $preferences.value.showExtensions)
                Toggle("Hidden items", isOn: $preferences.value.showHidden)
                Divider()
                Toggle("Preview pane", isOn: $preferences.value.previewPane)
                Toggle("Details pane", isOn: $preferences.value.inspector)
            } label: { Label("View", systemImage: "square.grid.2x2") }.fixedSize()
            Menu {
                Button("Select All") { workspace.selectAll() }; Button("Invert Selection") { workspace.invertSelection() }
                Button("Clear Selection") { tab.selection = [] }
                Divider()
                Button("Open in Terminal") { if let url = workspace.destination { NativeIntegration.terminal(url, owner: workspace) } }.disabled(workspace.destination == nil)
                Button("Connect to Server…") { workspace.sheet = .connect }
                Button("File Operations…") { workspace.sheet = .operations }
                Button("Recovery History…") { workspace.sheet = .recovery }
                Divider(); SettingsLink { Text("Folder Options…") }
            } label: { Image(systemName: "ellipsis").frame(width: 24) }.menuIndicator(.hidden)
            Spacer(minLength: 0)
            Button { preferences.value.inspector.toggle() } label: { Label("Details", systemImage: "sidebar.right") }.help("Toggle details pane")
        }.font(.system(size: 12)).buttonStyle(.borderless).menuStyle(.borderlessButton).padding(.horizontal, 14).frame(height: 51)
    }
    private var barDivider: some View { Divider().frame(height: 22).padding(.horizontal, 3) }
}

struct CommandIcon: View {
    let title: String
    let symbol: String
    var disabled: Bool
    let action: () -> Void
    init(_ title: String, _ symbol: String, disabled: Bool = false, action: @escaping () -> Void) { self.title = title; self.symbol = symbol; self.disabled = disabled; self.action = action }
    var body: some View { Button(action: action) { Image(systemName: symbol).font(.system(size: 15)).frame(width: 28, height: 30).contentShape(Rectangle()) }.buttonStyle(.borderless).disabled(disabled).help(title).accessibilityLabel(title) }
}

struct ExplorerAddressBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @State private var address = ""
    @FocusState private var pathFocus: Bool
    @FocusState private var searchFocus: Bool
    var ancestors: [URL] {
        guard var url = tab.location.directory else { return [] }
        var result = [url]
        while url.path != "/" { url = url.deletingLastPathComponent(); result.insert(url, at: 0) }
        return result
    }
    var body: some View {
        HStack(spacing: 8) {
            CommandIcon("Back (Alt+Left)", "chevron.left", disabled: !tab.history.canGoBack) { tab.back() }
            CommandIcon("Forward (Alt+Right)", "chevron.right", disabled: !tab.history.canGoForward) { tab.forward() }
            CommandIcon("Up (Alt+Up)", "arrow.up") { tab.up() }
            CommandIcon("Refresh (F5)", "arrow.clockwise") { tab.refresh() }
            HStack(spacing: 5) {
                Image(systemName: tab.location.symbol).foregroundStyle(.tint).padding(.leading, 9)
                if workspace.addressFocused {
                    TextField("Folder path", text: $address).textFieldStyle(.plain).focused($pathFocus)
                        .onSubmit { workspace.goToAddress(address); workspace.addressFocused = false }
                        .onExitCommand { workspace.addressFocused = false }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            if ancestors.isEmpty { Text(tab.location.title).padding(.horizontal, 5) }
                            else {
                                ForEach(ancestors, id: \.self) { url in
                                    Button { workspace.navigate(.folder(url)) } label: { Text(url.path == "/" ? "This Mac" : url.lastPathComponent).lineLimit(1) }.buttonStyle(.plain).padding(.horizontal, 5)
                                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }.onTapGesture(count: 2) { workspace.addressFocused = true }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Edit address") { workspace.addressFocused = true }
                    Divider()
                    ForEach(Array(tab.history.locations.enumerated()), id: \.offset) { _, location in Button(location.directory?.path ?? location.title) { workspace.navigate(location) } }
                } label: { Image(systemName: "chevron.down").font(.system(size: 9)).frame(width: 20) }.menuStyle(.borderlessButton).menuIndicator(.hidden)
            }.frame(height: 32).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(tab.location.title)", text: $tab.query).textFieldStyle(.plain).focused($searchFocus)
                if !tab.query.isEmpty { Button { tab.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
            }.padding(.horizontal, 9).frame(width: 210, height: 32).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }.font(.system(size: 12)).padding(.horizontal, 14).frame(height: 52)
            .onChange(of: workspace.addressFocused) { _, focused in if focused { address = tab.location.directory?.path ?? FileManager.default.homeDirectoryForCurrentUser.path }; pathFocus = focused }
            .onChange(of: workspace.searchFocused) { _, focused in searchFocus = focused }
            .onChange(of: searchFocus) { _, focused in workspace.searchFocused = focused }
    }
}

struct SearchControls: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.tint)
            Text("Search results").fontWeight(.medium)
            Picker("Scope", selection: $tab.allLocations) { Text("This folder").tag(false); Text("This Mac · Spotlight").tag(true) }.labelsHidden().frame(width: 190)
            Spacer()
            Menu("Refine") {
                ForEach(["kind:folder", "kind:image", "ext:pdf", "size:>10MB", "modified:today", "modified:week", "tag:Work", "content:\"text to find\""], id: \.self) { token in Button(token) { tab.query += " " + token } }
            }.fixedSize()
            Button("Save Search") { if !preferences.value.savedSearches.contains(tab.query) { preferences.value.savedSearches.append(tab.query) } }
        }.font(.caption).padding(10).background(.tint.opacity(0.06))
    }
}
