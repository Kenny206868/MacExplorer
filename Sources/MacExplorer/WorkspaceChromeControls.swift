import SwiftUI
import AppKit
import ExplorerCore

/// All chrome actions use the same window/modal boundary as keyboard commands.
/// These are commands, never direct filesystem work or unguarded pane mutations.
enum WorkspaceLayoutAction: String, CaseIterable, Identifiable {
    case single, split, stacked, primary, secondary, switchPane, equalize, swap, sameLocation, compare, path, commands
    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: return "Single Pane"; case .split: return "Side by Side"; case .stacked: return "Stacked Panes"
        case .primary: return "Focus First Pane"; case .secondary: return "Focus Second Pane"; case .switchPane: return "Switch Active Pane"
        case .equalize: return "Equal Pane Sizes"; case .swap: return "Swap Locations"; case .sameLocation: return "Same Location in Other Pane"
        case .compare: return "Compare Folders…"; case .path: return "Edit Active Path…"; case .commands: return "Search Commands…"
        }
    }
    var symbol: String {
        switch self {
        case .single: return "rectangle"; case .split: return "rectangle.split.2x1"; case .stacked: return "rectangle.split.1x2"
        case .primary: return "1.square"; case .secondary: return "2.square"; case .switchPane, .swap: return "arrow.left.arrow.right"
        case .equalize: return "equal"; case .sameLocation: return "arrow.right.to.line"; case .compare: return "doc.text.magnifyingglass"
        case .path: return "folder"; case .commands: return "magnifyingglass"
        }
    }
    @MainActor func enabled(_ root: ExplorerWorkspace?) -> Bool {
        guard let active = WorkspaceCommandScope.target(root) else { return false }
        let panes = active.paneController
        switch self {
        case .single: return panes == nil || active.operations.runningCount == 0
        case .primary, .secondary, .switchPane, .equalize, .sameLocation: return panes != nil
        case .swap: return panes?.preparingTransfer == false && active.operations.runningCount == 0
        case .compare: return ComparisonContext.unavailable(active) == nil
        default: return true
        }
    }
    @MainActor func perform(_ root: ExplorerWorkspace?) {
        guard enabled(root), let active = WorkspaceCommandScope.target(root) else { return }
        switch self {
        case .single: if active.paneController != nil { active.toggleDualPane() }
        case .split, .stacked:
            if active.paneController == nil { active.toggleDualPane() }
            active.paneController?.geometry.orientation = self == .split ? .sideBySide : .stacked
        case .primary, .secondary: active.paneController?.focus(self == .primary ? .primary : .secondary, files: true)
        case .switchPane: if let panes = active.paneController { panes.focus(panes.geometry.focused.other, files: true) }
        case .equalize: active.paneController?.geometry.ratio = 0.5
        case .swap: active.paneController?.swapLocations()
        case .sameLocation: active.paneController?.copyLocation(from: active)
        case .compare: active.sheet = .compareFolders
        case .path: active.editLocation()
        case .commands: active.sheet = .commandPalette
        }
    }
}

/// Only window identity/layout/availability is published to the titlebar host.
/// Selecting or hovering a file does not invalidate this independent view tree.
@MainActor final class WorkspaceChromeModel: ObservableObject {
    struct State: Equatable {
        var layout = WorkspaceChromeLayout(width: 1000)
        var primaryTitle = "MacExplorer", secondaryTitle = ""
        var primaryPath = "", secondaryPath = ""
        var dual = false
        var orientation = PaneOrientation.sideBySide
        var focused = PaneSide.primary
        var enabled = Set<WorkspaceLayoutAction>()
    }
    @Published private(set) var state = State()
    private(set) var publications = 0
    weak var owner: ExplorerWorkspace?
    func update(owner: ExplorerWorkspace, width: CGFloat) {
        self.owner = owner
        let panes = owner.dualPane
        let value = State(layout: WorkspaceChromeLayout(width: width, touch: InputPreferences.shared.touchFriendly),
            primaryTitle: owner.current.location.title, secondaryTitle: panes?.secondary.current.location.title ?? "",
            primaryPath: owner.current.location.displayPath, secondaryPath: panes?.secondary.current.location.displayPath ?? "",
            dual: panes != nil, orientation: panes?.geometry.orientation ?? .sideBySide,
            focused: panes?.geometry.focused ?? .primary,
            enabled: Set(WorkspaceLayoutAction.allCases.filter { $0.enabled(owner) }))
        if value != state { state = value; publications += 1 }
    }
    func perform(_ action: WorkspaceLayoutAction) { action.perform(owner) }
}

struct WorkspaceTitlebarControls: View {
    @ObservedObject var model: WorkspaceChromeModel
    private var state: WorkspaceChromeModel.State { model.state }
    private var wide: Bool { state.layout.titlebarShowsLocations }
    private var target: CGFloat { state.layout.touch ? 44 : 28 }
    var body: some View {
        HStack(spacing: wide ? 10 : 6) {
            layoutPicker
            if wide {
                Divider().frame(height: 16)
                if state.dual {
                    pane(.primary, title: state.primaryTitle, path: state.primaryPath)
                    icon(.swap)
                    pane(.secondary, title: state.secondaryTitle, path: state.secondaryPath)
                } else {
                    Button { model.perform(.path) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "folder")
                            Text("Go to folder…").lineLimit(1)
                            Spacer(minLength: 4)
                            Text("⌘L").foregroundStyle(ExplorerDesign.muted)
                        }.padding(.horizontal, 9).frame(height: target)
                    }.buttonStyle(ExplorerIconStyle()).disabled(!state.enabled.contains(.path))
                        .help("Edit the full active path · ⌘L")
                }
                if state.layout.titlebarShowsCompare && state.dual { icon(.compare) }
            }
            commandSearch
        }.font(.system(size: 11, weight: .medium)).foregroundStyle(ExplorerDesign.text)
            .frame(width: state.layout.titlebarWidth, height: state.layout.titlebarHeight)
            .accessibilityIdentifier("explorer.titlebarWorkspace")
    }
    private var layoutPicker: some View {
        HStack(spacing: 2) {
            ForEach([WorkspaceLayoutAction.single, .split, .stacked]) { action in
                let selected = action == .single ? !state.dual : state.dual && (action == .stacked ? state.orientation == .stacked : state.orientation == .sideBySide)
                Button { model.perform(action) } label: {
                    Image(systemName: action.symbol).font(.system(size: 13)).frame(width: target, height: target)
                }.buttonStyle(ExplorerIconStyle(selected: selected)).disabled(!state.enabled.contains(action))
                    .help(action.title).accessibilityLabel(action.title).accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityIdentifier("explorer.titlebar." + action.rawValue)
            }
        }.padding(2).background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 7))
            .contextMenu { layoutMenu }
    }
    private func pane(_ side: PaneSide, title: String, path: String) -> some View {
        let action: WorkspaceLayoutAction = side == .primary ? .primary : .secondary
        let selected = state.focused == side
        return Button { model.perform(action) } label: {
            HStack(spacing: 7) {
                Text(side == .primary ? "1" : "2").font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? Color.accentColor : ExplorerDesign.muted)
                Text(title).lineLimit(1).truncationMode(.middle)
            }.padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: target, alignment: .leading)
        }.buttonStyle(ExplorerIconStyle(selected: selected)).disabled(!state.enabled.contains(action))
            .help(action.title + ": " + path).accessibilityLabel(action.title + ": " + title)
            .accessibilityIdentifier("explorer.titlebar." + action.rawValue)
            .contextMenu { layoutMenu }
    }
    private func icon(_ action: WorkspaceLayoutAction) -> some View {
        Button { model.perform(action) } label: { Image(systemName: action.symbol).frame(width: target, height: target) }
            .buttonStyle(ExplorerIconStyle()).disabled(!state.enabled.contains(action)).help(action.title).accessibilityLabel(action.title)
            .accessibilityIdentifier("explorer.titlebar." + action.rawValue)
    }
    private var commandSearch: some View {
        Button { model.perform(.commands) } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                if wide { Text("Commands").lineLimit(1) }
                if state.layout.titlebarShowsCompare { Text("⇧⌘P").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted) }
            }.padding(.horizontal, 10).frame(minWidth: state.layout.touch ? 44 : 28, minHeight: target)
                .background(ExplorerDesign.canvas.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ExplorerDesign.separator, lineWidth: 1))
        }.buttonStyle(ExplorerIconStyle()).disabled(!state.enabled.contains(.commands))
            .help("Search all commands · ⇧⌘P").accessibilityLabel("Search all commands")
            .accessibilityIdentifier("explorer.titlebar.commands")
    }
    @ViewBuilder private var layoutMenu: some View {
        ForEach([WorkspaceLayoutAction.single, .split, .stacked, .switchPane, .equalize, .swap, .sameLocation, .compare]) { action in
            Button { model.perform(action) } label: { Label(action.title, systemImage: action.symbol) }.disabled(!state.enabled.contains(action))
        }
    }
}
