import SwiftUI
import AppKit
import QuickLook
import ExplorerCore

struct WorkspaceShell: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @ObservedObject private var operations = OperationCenter.shared
    @SceneStorage("MacExplorer.Design.SidebarWidth") private var sidebarWidth = 211.0
    @SceneStorage("MacExplorer.Design.InspectorWidth") private var inspectorWidth = 254.0
    @SceneStorage("MacExplorer.Design.PreviewWidth") private var previewWidth = 300.0
    @State private var compactPane = "Details"
    var body: some View {
        GeometryReader { geometry in
            let plan = WorkspaceLayout(width: geometry.size.width, preview: preferences.value.previewPane, inspector: preferences.value.inspector)
            let panes = plan.allocate(sidebar: sidebarWidth, inspector: inspectorWidth, preview: previewWidth,
                                      hasInspector: preferences.value.inspector, hasPreview: preferences.value.previewPane)
            VStack(spacing: 0) {
                ExplorerTabStrip(workspace: workspace).explorerRegion("tabs")
                ExplorerRule()
                ExplorerCommandBar(workspace: workspace, tab: tab, compact: plan.compactToolbar).explorerRegion("commands")
                ExplorerRule()
                ExplorerAddressBar(workspace: workspace, tab: tab, searchWidth: plan.searchWidth).explorerRegion("address")
                ExplorerRule()
                HStack(spacing: 0) {
                    ExplorerSidebar(workspace: workspace, tab: tab).frame(width: panes.sidebar).explorerRegion("sidebar")
                    PaneDivider(title: "Sidebar width", value: $sidebarWidth, actual: panes.sidebar)
                    FilePromiseDropHost(workspace: workspace) { fileContent }
                        .frame(width: panes.content).frame(maxHeight: .infinity).clipped().explorerRegion("files")
                    if plan.combinesAuxiliaryPanes {
                        PaneDivider(title: "Details and preview width", value: $inspectorWidth, actual: panes.auxiliary, reversed: true)
                        VStack(spacing: 0) {
                            Picker("Auxiliary pane", selection: $compactPane) {
                                Text("Details").tag("Details"); Text("Preview").tag("Preview")
                            }.labelsHidden().pickerStyle(.segmented).padding(12)
                            ExplorerRule()
                            if compactPane == "Preview" { preview } else { ExplorerInspector(workspace: workspace, tab: tab) }
                        }.frame(width: panes.auxiliary).explorerRegion("auxiliary")
                    } else {
                        if preferences.value.previewPane {
                            PaneDivider(title: "Preview width", value: $previewWidth, actual: panes.preview, reversed: true)
                            preview.frame(width: panes.preview).explorerRegion("preview")
                        }
                        if preferences.value.inspector {
                            PaneDivider(title: "Details width", value: $inspectorWidth, actual: panes.auxiliary, reversed: true)
                            ExplorerInspector(workspace: workspace, tab: tab).frame(width: panes.auxiliary).explorerRegion("inspector")
                        }
                    }
                }.frame(maxHeight: .infinity)
                ExplorerRule()
                statusBar.explorerRegion("status")
            }.coordinateSpace(name: "Explorer.workspace")
                .foregroundStyle(ExplorerDesign.text).background(ExplorerDesign.canvas)
                .quickLookPreview($tab.previewURL)
        }
    }
    private var fileContent: some View {
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
                    Text(tab.truncated ? "Showing the first 25,000 matches. Narrow your search for additional results." : tab.warnings[0])
                        .font(.caption).lineLimit(2).textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button("Details") { workspace.fail("Filesystem notices", tab.warnings.joined(separator: "\n")) }.font(.caption)
                }.padding(10).background(.orange.opacity(0.07))
            }
        }.background(ExplorerDesign.canvas).onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            guard let folder = workspace.destination else { return false }
            return workspace.drop(providers, to: folder, move: NSEvent.modifierFlags.contains(.shift))
        }
    }
    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview").font(.system(size: 12, weight: .semibold)); Spacer()
                CommandIcon("Close Preview", "xmark") { preferences.value.previewPane = false }
            }.padding(.leading, 20).padding(.trailing, 12).frame(height: 48)
            ExplorerRule()
            if let url = workspace.selectedURLs.first { NativePreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ContentUnavailableView("Select a file", systemImage: "doc.viewfinder", description: Text("Preview documents, images, audio, and video with Quick Look.")).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.background(ExplorerDesign.canvas)
    }
    private var statusBar: some View {
        HStack(spacing: 12) {
            if tab.loading { ProgressView().controlSize(.mini); Text("Loading…") } else { Text("\(tab.entries.count) items") }
            if !tab.selection.isEmpty { Text("\(tab.selection.count) selected · " + ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)).lineLimit(1) }
            Spacer(minLength: 4)
            Button { workspace.sheet = .operations } label: {
                HStack(spacing: 6) {
                    Circle().fill(operations.runningCount > 0 ? Color.accentColor : .green).frame(width: 5, height: 5)
                    Text(operations.runningCount > 0 ? "\(operations.runningCount) in progress" : "File operations")
                }
            }.help("Show transfer progress and operation history")
            Rectangle().fill(ExplorerDesign.separator).frame(width: 1, height: 16)
            Button { tab.options.view = .details } label: { Image(systemName: "list.bullet").frame(width: 26, height: 23) }
                .buttonStyle(ExplorerIconStyle(selected: tab.options.view == .details)).help("Details view").accessibilityLabel("Details view")
            Button { tab.options.view = .large } label: { Image(systemName: "square.grid.2x2").frame(width: 26, height: 23) }
                .buttonStyle(ExplorerIconStyle(selected: tab.options.view == .large)).help("Large icons").accessibilityLabel("Large icons view")
        }.font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).buttonStyle(.plain)
            .padding(.horizontal, 14).frame(height: ExplorerDesign.statusHeight).background(ExplorerDesign.chrome)
    }
    private var selectedBytes: Int64 {
        workspace.selected.reduce(0) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(max(0, entry.size)); return overflow ? .max : sum
        }
    }
}
