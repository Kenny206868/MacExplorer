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
struct DualPaneShell: View {
    @ObservedObject var controller: DualPaneController
    @EnvironmentObject private var preferences: PreferenceStore
    @ObservedObject private var input = InputPreferences.shared
    @SceneStorage("MacExplorer.Design.SidebarWidth") private var sidebar = 211.0
    @SceneStorage("MacExplorer.Design.InspectorWidth") private var inspector = 254.0
    @State private var auxiliaryTab = "Details"
    var body: some View {
        GeometryReader { geometry in
            if let primary = controller.primary {
                let active = controller.active
                let auxiliary = (preferences.value.inspector || preferences.value.previewPane) && geometry.size.width >= 1540
                let plan = WorkspaceLayout(width: geometry.size.width, preview: false, inspector: auxiliary)
                let panes = plan.allocate(sidebar: sidebar, inspector: inspector, hasInspector: auxiliary, hasPreview: false)
                VStack(spacing: 0) {
                    ExplorerTabStrip(workspace: active).explorerRegion("tabs")
                    ExplorerRule()
                    ExplorerCommandBar(workspace: active, tab: active.current, compact: plan.compactToolbar || input.touchFriendly).explorerRegion("commands")
                    ExplorerRule()
                    ExplorerAddressBar(workspace: active, tab: active.current, searchWidth: plan.searchWidth).explorerRegion("address")
                    ExplorerRule()
                    HStack(spacing: 0) {
                        ExplorerSidebar(workspace: active, tab: active.current).frame(width: panes.sidebar).explorerRegion("sidebar")
                        PaneDivider(title: "Sidebar width", value: $sidebar, actual: panes.sidebar)
                        splitBrowsers(primary: primary).frame(width: panes.content).explorerRegion("files")
                        if auxiliary {
                            PaneDivider(title: "Inspector width", value: $inspector, actual: panes.auxiliary, reversed: true)
                            auxiliaryPane(workspace: active).frame(width: panes.auxiliary).explorerRegion("auxiliary")
                        }
                    }.frame(maxHeight: .infinity)
                    ExplorerRule()
                    transferBar(workspace: active, hidesAuxiliary: !auxiliary, width: geometry.size.width).frame(height: input.touchFriendly ? 54 : 40).explorerRegion("status")
                }.background(ExplorerDesign.canvas).foregroundStyle(ExplorerDesign.text)
                    .coordinateSpace(name: "Explorer.workspace")
                    .quickLookPreview(Binding(get: { controller.active.current.previewURL }, set: { controller.active.current.previewURL = $0 }))
            }
        }
    }
    private func splitBrowsers(primary: ExplorerWorkspace) -> some View {
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
    private func auxiliaryPane(workspace: ExplorerWorkspace) -> some View {
        VStack(spacing: 0) {
            if preferences.value.inspector && preferences.value.previewPane {
                Picker("Auxiliary pane", selection: $auxiliaryTab) { Text("Details").tag("Details"); Text("Preview").tag("Preview") }.labelsHidden().pickerStyle(.segmented).padding(12)
                ExplorerRule()
            }
            if preferences.value.previewPane && (!preferences.value.inspector || auxiliaryTab == "Preview") {
                if let url = workspace.selectedURLs.first { NativePreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { ContentUnavailableView("Select a file", systemImage: "doc.viewfinder").frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else { ExplorerInspector(workspace: workspace, tab: workspace.current) }
        }.background(ExplorerDesign.canvas)
    }
    private func transferBar(workspace: ExplorerWorkspace, hidesAuxiliary: Bool, width: CGFloat) -> some View {
        HStack(spacing: 10) {
            Button { controller.focus(controller.geometry.focused.other, files: true) } label: { Label("Switch pane", systemImage: "arrow.left.arrow.right") }.help("Tab switches file panes; each pane keeps its selection.")
            Menu {
                Picker("Pane orientation", selection: $controller.geometry.orientation) { Text("Side by Side").tag(PaneOrientation.sideBySide); Text("Stacked").tag(PaneOrientation.stacked) }
                Button("Equal Pane Sizes") { controller.geometry.ratio = 0.5 }
                Button("Swap Locations") { controller.swapLocations() }
                Button("Same Location in Other Pane") { controller.copyLocation(from: workspace) }
                Divider(); Button("Close Dual Panes") { workspace.toggleDualPane() }
            } label: { Image(systemName: "rectangle.split.2x1").frame(width: input.target, height: input.target) }.menuStyle(.borderlessButton).menuIndicator(.hidden).help("Pane layout")
            if width >= 1100 {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.right").font(.system(size: 10))
                    Text(controller.other(than: workspace)?.destination.map { "Destination: " + $0.path } ?? "Open a destination folder in the other pane")
                        .lineLimit(1).truncationMode(.middle)
                }.font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).frame(maxWidth: .infinity, alignment: .leading)
                    .help(controller.other(than: workspace)?.destination?.path ?? "No destination folder")
            } else { Spacer(minLength: 0) }
            if hidesAuxiliary && (preferences.value.inspector || preferences.value.previewPane) {
                Image(systemName: "sidebar.right").foregroundStyle(ExplorerDesign.muted).help("Auxiliary panes are preserved and appear when the window is at least 1540 points wide.")
            }
            Button { controller.requestTransfer(from: workspace, move: false) } label: { Label("Copy to other pane", systemImage: "doc.on.doc") }
                .disabled(workspace.selected.isEmpty || controller.other(than: workspace)?.destination == nil)
                .help("Copy to \(controller.other(than: workspace)?.destination?.path ?? "a folder in the other pane") · Cmd/Ctrl+Option+C")
            Button { controller.requestTransfer(from: workspace, move: true) } label: { Label("Move…", systemImage: "arrow.right.doc.on.clipboard") }
                .disabled(workspace.selected.isEmpty || controller.other(than: workspace)?.destination == nil)
                .help("Move to the other pane after confirmation · Cmd/Ctrl+Option+M")
        }.font(.system(size: 11)).buttonStyle(ExplorerButtonStyle()).padding(.horizontal, 12).background(ExplorerDesign.chrome)
    }
}
private struct DualFilePane: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var controller: DualPaneController
    let side: PaneSide
    @ObservedObject private var input = InputPreferences.shared
    @EnvironmentObject private var preferences: PreferenceStore
    private var active: Bool { controller.geometry.focused == side }
    var body: some View {
        VStack(spacing: 0) {
            header
            PaneLocationBar(workspace: workspace)
            FilePromiseDropHost(workspace: workspace) {
                VStack(spacing: 0) {
                    if !workspace.current.query.isEmpty { SearchControls(tab: workspace.current) }
                    if let error = workspace.current.error { ContentUnavailableView("Location unavailable", systemImage: "folder.badge.questionmark", description: Text(error)) }
                    else { ExplorerContent(workspace: workspace, tab: workspace.current) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ExplorerDesign.canvas)
                    .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                        guard let destination = workspace.destination else { return false }
                        return workspace.drop(providers, to: destination, move: NSEvent.modifierFlags.contains(.shift))
                    }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            ExplorerRule(); footer
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ExplorerDesign.canvas)
            .overlay(alignment: .top) { Rectangle().fill(active ? Color.accentColor : ExplorerDesign.separator).frame(height: active ? 2 : 1).allowsHitTesting(false) }
            .explorerRegion(side == .primary ? "pane.primary" : "pane.secondary")
            .onChange(of: workspace.activeID) { _, _ in workspace.current.refresh(); workspace.saveSession() }
            .onAppear { workspace.window = controller.primary?.window }
    }
    private var header: some View {
        HStack(spacing: 6) {
            Button { controller.focus(side, files: true) } label: {
                Text(side == .primary ? "1" : "2").font(.system(size: 10, weight: .bold)).frame(width: 22, height: 22)
                    .foregroundStyle(active ? Color.white : ExplorerDesign.muted)
                    .background(active ? Color.accentColor : ExplorerDesign.hover, in: RoundedRectangle(cornerRadius: 5))
                    .frame(width: input.touchFriendly ? 44 : 22, height: input.touchFriendly ? 44 : 22).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Focus \(side == .primary ? "first" : "second") pane")
            Menu {
                ForEach(workspace.tabs) { tab in
                    Button { controller.focus(side); workspace.activeID = tab.id } label: { Label(tab.location.title, systemImage: tab.id == workspace.activeID ? "checkmark" : tab.location.symbol) }
                }
                Divider(); Button("New Tab in This Pane") { controller.focus(side); workspace.newTab() }
                Button("Duplicate Tab") { controller.focus(side); workspace.duplicateTab(workspace.current) }
            } label: {
                HStack(spacing: 6) { Image(systemName: workspace.current.location.symbol).foregroundStyle(Color.accentColor); Text(workspace.current.location.title).lineLimit(1).fontWeight(.semibold) }
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth: .infinity, alignment: .leading)
                .help(workspace.current.location.directory?.path ?? workspace.current.location.title)
            if active { Text("ACTIVE").font(.system(size: 8, weight: .semibold)).tracking(0.6).foregroundStyle(Color.accentColor).accessibilityHidden(true) }
            CommandIcon("Back in this pane", "chevron.left", disabled: !workspace.current.history.canGoBack) { controller.focus(side); workspace.current.back() }
            CommandIcon("Up in this pane", "arrow.up", disabled: workspace.destination == nil) { controller.focus(side); workspace.current.up() }
            Menu {
                Button("Focus This Pane") { controller.focus(side, files: true) }
                Button("Edit Location") { controller.focus(side); workspace.addressFocused = true }
                Button("Search This Pane") { controller.focus(side); workspace.searchFocused = true }
                Picker("View", selection: Binding(get: { workspace.current.options.view }, set: { workspace.current.options.view = $0 })) { ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Button("Refresh") { workspace.current.refresh() }
            } label: { Image(systemName: "ellipsis").frame(width: input.target, height: input.target) }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Pane actions")
        }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: input.touchFriendly ? 54 : 44)
            .background(active ? ExplorerDesign.selection.opacity(0.3) : ExplorerDesign.chrome)
    }
    private var footer: some View {
        HStack(spacing: 8) {
            if workspace.current.loading { ProgressView().controlSize(.mini) }
            Text("\(workspace.current.entries.count) items").lineLimit(1)
            if !workspace.current.selection.isEmpty { Text("· \(workspace.current.selection.count) selected").lineLimit(1) }
            Spacer(minLength: 0)
            if input.touchFriendly {
                Button(workspace.touchSelecting ? "Done" : "Select") { workspace.activatePane(); workspace.touchSelecting.toggle() }
                Button("Open") { workspace.activatePane(); workspace.openSelection() }.disabled(workspace.selected.isEmpty)
                Button { workspace.activatePane(); workspace.sheet = .fileActions } label: { Image(systemName: "ellipsis.circle").frame(width: 30) }.disabled(workspace.selected.isEmpty)
            }
        }.font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).padding(.horizontal, 12)
            .buttonStyle(ExplorerButtonStyle()).frame(height: input.touchFriendly ? 48 : 27).background(ExplorerDesign.chrome)
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
            .help("Drag to resize. Double-click for equal sizes. Arrow keys adjust a focused divider.")
    }
    private func adjust(_ amount: Double) { controller.geometry.ratio = DualPaneLayout.normalizedRatio(controller.geometry.ratio + amount) }
}
