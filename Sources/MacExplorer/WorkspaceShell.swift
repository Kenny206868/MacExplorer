import SwiftUI
import AppKit
import QuickLook
import ExplorerCore

struct WorkspaceShell: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @ObservedObject private var operations = OperationCenter.shared
    @State private var compactPane = "Details"
    var body: some View {
        GeometryReader { geometry in
            let plan = WorkspaceLayout(width: geometry.size.width, preview: preferences.value.previewPane, inspector: preferences.value.inspector)
            VStack(spacing: 0) {
                ExplorerTabStrip(workspace: workspace).explorerRegion("tabs")
                Divider()
                ExplorerCommandBar(workspace: workspace, tab: tab, compact: plan.compactToolbar).explorerRegion("commands")
                Divider()
                ExplorerAddressBar(workspace: workspace, tab: tab, searchWidth: plan.searchWidth).explorerRegion("address")
                Divider()
                HSplitView {
                    ExplorerSidebar(workspace: workspace, tab: tab)
                        .frame(minWidth: plan.sidebarMinimum, idealWidth: plan.sidebarIdeal, maxWidth: 264)
                        .background(InitialPaneSizing(plan: plan, preview: preferences.value.previewPane, inspector: preferences.value.inspector))
                        .explorerRegion("sidebar")
                    FilePromiseDropHost(workspace: workspace) { fileContent }
                        .frame(minWidth: plan.contentMinimum, maxWidth: .infinity, maxHeight: .infinity)
                        .explorerRegion("files")
                    if plan.combinesAuxiliaryPanes {
                        VStack(spacing: 0) {
                            Picker("Auxiliary pane", selection: $compactPane) {
                                Text("Details").tag("Details"); Text("Preview").tag("Preview")
                            }.pickerStyle(.segmented).labelsHidden().padding(12)
                            Divider()
                            if compactPane == "Preview" { preview }
                            else { ExplorerInspector(workspace: workspace, tab: tab) }
                        }.frame(minWidth: plan.auxiliaryMinimum, idealWidth: 270, maxWidth: 380)
                            .explorerRegion("auxiliary")
                    } else {
                        if preferences.value.previewPane {
                            preview.frame(minWidth: plan.auxiliaryMinimum, idealWidth: 310, maxWidth: 650).explorerRegion("preview")
                        }
                        if preferences.value.inspector {
                            ExplorerInspector(workspace: workspace, tab: tab)
                                .frame(minWidth: plan.auxiliaryMinimum, idealWidth: 270, maxWidth: 380).explorerRegion("inspector")
                        }
                    }
                }
                Divider()
                statusBar.explorerRegion("status")
            }
            .coordinateSpace(name: "Explorer.workspace")
            .background(ExplorerDesign.canvas)
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
        }.onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            guard let folder = workspace.destination else { return false }
            return workspace.drop(providers, to: folder, move: NSEvent.modifierFlags.contains(.shift))
        }
    }
    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview").font(.system(size: 12, weight: .semibold)); Spacer()
                CommandIcon("Close Preview", "xmark") { preferences.value.previewPane = false }
            }.padding(.leading, 16).padding(.trailing, 8).frame(height: 46)
            Divider()
            if let url = workspace.selectedURLs.first {
                NativePreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a file", systemImage: "doc.viewfinder", description: Text("Preview documents, images, audio, and video with Quick Look."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(ExplorerDesign.surface.opacity(0.3))
    }
    private var statusBar: some View {
        HStack(spacing: 12) {
            if tab.loading { ProgressView().controlSize(.mini); Text("Loading…") }
            else { Text("\(tab.entries.count) items") }
            if !tab.selection.isEmpty {
                Text("\(tab.selection.count) selected").foregroundStyle(.primary)
                Text(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { workspace.sheet = .operations } label: {
                Label(operations.runningCount > 0 ? "\(operations.runningCount) in progress" : "File operations", systemImage: operations.runningCount > 0 ? "arrow.triangle.2.circlepath" : "checkmark.circle")
            }.help("Show transfer progress and operation history")
            Divider().frame(height: 13)
            Button { tab.options.view = .details } label: { Image(systemName: "list.bullet").foregroundStyle(tab.options.view == .details ? Color.accentColor : .secondary) }.help("Details view").accessibilityLabel("Details view")
            Button { tab.options.view = .large } label: { Image(systemName: "square.grid.2x2").foregroundStyle(tab.options.view == .large ? Color.accentColor : .secondary) }.help("Large icons").accessibilityLabel("Large icons view")
        }.font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain)
            .padding(.horizontal, 16).frame(height: ExplorerDesign.statusHeight).background(.bar)
    }
    private var selectedBytes: Int64 {
        workspace.selected.reduce(0) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(max(0, entry.size)); return overflow ? .max : sum
        }
    }
}
