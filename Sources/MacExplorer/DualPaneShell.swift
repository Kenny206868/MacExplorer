import SwiftUI
import AppKit
import QuickLook
import ExplorerCore

struct WindowWorkspaceShell: View {
    @ObservedObject var workspace: ExplorerWorkspace
    var body: some View {
        if let dual = workspace.dualPane { DualPaneShell(controller: dual) }
        else { WorkspaceShell(workspace: workspace, tab: workspace.current) }
    }
}
/// Native window chrome sits above independent file panes; neither pane needs
/// a third address bar or a second window title rendered inside the content.
struct DualPaneShell: View {
    @ObservedObject var controller: DualPaneController
    @EnvironmentObject private var preferences: PreferenceStore
    @SceneStorage("MacExplorer.Design.SidebarWidth") private var sidebar = 211.0
    @SceneStorage("MacExplorer.Design.InspectorWidth") private var inspector = 254.0
    @State private var auxiliaryTab = "Details"
    var body: some View {
        GeometryReader { geometry in
            if let primary = controller.primary {
                let active = controller.active
                let auxiliary = (preferences.value.inspector || preferences.value.previewPane) && geometry.size.width >= 1540
                let plan = WorkspaceLayout(width: geometry.size.width, preview: false, inspector: auxiliary)
                let allocation = plan.allocate(sidebar: sidebar, inspector: inspector, hasInspector: auxiliary, hasPreview: false)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ExplorerSidebar(workspace: active, tab: active.current).frame(width: allocation.sidebar).explorerRegion("sidebar")
                        PaneDivider(title: "Sidebar width", value: $sidebar, actual: allocation.sidebar)
                        browsers(primary: primary).frame(width: allocation.content).explorerRegion("files")
                        if auxiliary {
                            PaneDivider(title: "Inspector width", value: $inspector, actual: allocation.auxiliary, reversed: true)
                            auxiliaryPane(active).frame(width: allocation.auxiliary).explorerRegion("auxiliary")
                        }
                    }.frame(maxHeight: .infinity)
                    ExplorerRule()
                    DualTransferBar(controller: controller, workspace: active).explorerRegion("status")
                }.foregroundStyle(ExplorerDesign.text).background(ExplorerDesign.canvas)
                    .coordinateSpace(name: "Explorer.workspace")
                    .quickLookPreview(Binding(get: { controller.active.current.previewURL }, set: { controller.active.current.previewURL = $0 }))
            }
        }
    }
    private func browsers(primary: ExplorerWorkspace) -> some View {
        GeometryReader { geometry in
            let layout = DualPaneLayout(width: geometry.size.width, height: geometry.size.height, preferred: controller.geometry.orientation, ratio: controller.geometry.ratio)
            Group {
                if layout.orientation == .sideBySide {
                    HStack(spacing: 0) {
                        DualFilePane(workspace: primary, controller: controller, side: .primary).frame(width: layout.first)
                        DualPaneGrip(controller: controller, layout: layout)
                        DualFilePane(workspace: controller.secondary, controller: controller, side: .secondary).frame(width: layout.second)
                    }
                } else {
                    VStack(spacing: 0) {
                        DualFilePane(workspace: primary, controller: controller, side: .primary).frame(height: layout.first)
                        DualPaneGrip(controller: controller, layout: layout)
                        DualFilePane(workspace: controller.secondary, controller: controller, side: .secondary).frame(height: layout.second)
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func auxiliaryPane(_ workspace: ExplorerWorkspace) -> some View {
        VStack(spacing: 0) {
            if preferences.value.inspector && preferences.value.previewPane {
                Picker("Auxiliary pane", selection: $auxiliaryTab) { Text("Details").tag("Details"); Text("Preview").tag("Preview") }
                    .labelsHidden().pickerStyle(.segmented).padding(12)
                ExplorerRule()
            }
            if preferences.value.previewPane && (!preferences.value.inspector || auxiliaryTab == "Preview") {
                if let url = workspace.selectedURLs.first { NativePreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { ContentUnavailableView("Select a file", systemImage: "doc.viewfinder").frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else { ExplorerInspector(workspace: workspace, tab: workspace.current) }
        }.background(ExplorerDesign.canvas)
    }
}
private struct DualFilePane: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var controller: DualPaneController
    let side: PaneSide
    @ObservedObject private var input = InputPreferences.shared
    private var active: Bool { controller.geometry.focused == side }
    var body: some View {
        VStack(spacing: 0) {
            PaneTabHeader(workspace: workspace, controller: controller, side: side)
            PaneNavigationHeader(workspace: workspace, tab: workspace.current)
            FilePromiseDropHost(workspace: workspace) {
                VStack(spacing: 0) {
                    if !workspace.current.query.isEmpty { SearchControls(tab: workspace.current) }
                    if let error = workspace.current.error {
                        VStack(spacing: 12) {
                            ContentUnavailableView("Location unavailable", systemImage: "folder.badge.questionmark", description: Text(error))
                            Button("Try Again") { workspace.current.refresh() }.buttonStyle(ExplorerButtonStyle())
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { ExplorerContent(workspace: workspace, tab: workspace.current) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ExplorerDesign.canvas)
                    .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                        guard let destination = workspace.destination else { return false }
                        return workspace.drop(providers, to: destination, move: NSEvent.modifierFlags.contains(.shift))
                    }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            ExplorerRule()
            ExplorerStatusBar(workspace: workspace, tab: workspace.current, compact: true, active: active)
            if input.touchFriendly { TouchFileBar(workspace: workspace) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ExplorerDesign.canvas)
            .overlay(alignment: .top) { Rectangle().fill(active ? Color.accentColor : ExplorerDesign.separator).frame(height: active ? 2 : 1).allowsHitTesting(false) }
            .explorerRegion(side == .primary ? "pane.primary" : "pane.secondary")
            .onChange(of: workspace.activeID) { _, _ in workspace.current.refresh(); workspace.saveSession() }
            .onAppear { workspace.window = controller.primary?.window }
    }
}
private struct DualTransferBar: View {
    @ObservedObject var controller: DualPaneController
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject private var input = InputPreferences.shared
    var body: some View {
        ViewThatFits(in: .horizontal) { controls(detailed: true); controls(detailed: false) }
            .padding(.horizontal, 12).frame(height: input.touchFriendly ? 56 : 48).background(ExplorerDesign.chrome)
    }
    private func controls(detailed: Bool) -> some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Pane Arrangement", selection: $controller.geometry.orientation) {
                    Text("Side by Side").tag(PaneOrientation.sideBySide); Text("Stacked").tag(PaneOrientation.stacked)
                }
                Button("Switch Active Pane") { controller.focus(controller.geometry.focused.other, files: true) }
                Button("Equal Pane Sizes") { controller.geometry.ratio = 0.5 }
                Button("Swap Locations") { controller.swapLocations() }
                Button("Same Location in Other Pane") { controller.copyLocation(from: workspace) }
                Divider(); Button("Close Dual Panes") { workspace.toggleDualPane() }
            } label: { Label("Panes", systemImage: "rectangle.split.2x1").font(.system(size: 11)) }.menuStyle(.borderlessButton).fixedSize()
            if detailed {
                Text(workspace.current.location.title).fontWeight(.medium).lineLimit(1)
                Image(systemName: "arrow.right").foregroundStyle(Color.accentColor)
                Text(controller.other(than: workspace)?.current.location.title ?? "Choose destination").lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { workspace.sheet = .operations } label: { Image(systemName: "arrow.up.arrow.down.circle").frame(width: 20) }.help("File operations")
            Button { controller.requestTransfer(from: workspace, move: false) } label: { Label(detailed ? "Copy to other pane" : "Copy", systemImage: "doc.on.doc") }
                .buttonStyle(ExplorerButtonStyle(primary: true))
                .disabled(workspace.selected.isEmpty || controller.other(than: workspace)?.destination == nil)
                .help("Copy to the other pane · ⌘⌥C")
            Button { controller.requestTransfer(from: workspace, move: true) } label: { Label("Move…", systemImage: "arrow.right.doc.on.clipboard") }
                .disabled(workspace.selected.isEmpty || controller.other(than: workspace)?.destination == nil)
                .help("Confirm a move to the other pane · ⌘⌥M")
        }.font(.system(size: 11)).buttonStyle(ExplorerButtonStyle())
    }
}
private struct DualPaneGrip: View {
    @ObservedObject var controller: DualPaneController
    let layout: DualPaneLayout
    @State private var start: Double?
    @State private var hovered = false
    private var horizontal: Bool { layout.orientation == .sideBySide }
    var body: some View {
        Rectangle().fill(hovered ? ExplorerDesign.selection : ExplorerDesign.chrome)
            .frame(width: horizontal ? 7 : nil, height: horizontal ? nil : 7)
            .overlay { Capsule().fill(hovered ? Color.accentColor : ExplorerDesign.muted.opacity(0.5)).frame(width: horizontal ? 2 : 30, height: horizontal ? 30 : 2) }
            .contentShape(Rectangle()).focusable()
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global).onChanged { value in
                if start == nil { start = layout.first }
                let distance = horizontal ? value.translation.width : value.translation.height
                controller.geometry.ratio = DualPaneLayout.normalizedRatio(((start ?? layout.first) + distance) / max(1, layout.extent))
            }.onEnded { _ in start = nil })
            .onTapGesture(count: 2) { controller.geometry.ratio = 0.5 }.onHover { hovered = $0 }
            .onMoveCommand { direction in
                if direction == .left || direction == .up { adjust(-0.05) }
                else if direction == .right || direction == .down { adjust(0.05) }
            }
            .accessibilityLabel("Resize file panes").accessibilityValue("\(Int(controller.geometry.ratio * 100)) percent to first pane")
            .accessibilityAdjustableAction { adjust($0 == .increment ? 0.05 : -0.05) }
    }
    private func adjust(_ amount: Double) { controller.geometry.ratio = DualPaneLayout.normalizedRatio(controller.geometry.ratio + amount) }
}
