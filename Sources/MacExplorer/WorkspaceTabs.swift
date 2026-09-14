import SwiftUI
import AppKit
import ExplorerCore

struct BrowserSession: Codable, Hashable, Sendable {
    let id: UUID
    let history: NavigationHistory
    let options: FolderOptions
    let query: String
    let allLocations: Bool
    let selection: [URL]
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
@MainActor extension BrowserTab {
    func session() -> BrowserSession { BrowserSession(id: UUID(), history: history, options: options, query: query, allLocations: allLocations, selection: Array(selection)) }
    func restore(_ session: BrowserSession) {
        history = session.history; options = session.options; collapsedGroups = []
        query = session.query; allLocations = session.allLocations; selection = Set(session.selection)
        TabTransferCoordinator.shared.restored(session.id, as: self)
    }
}
@MainActor extension ExplorerWorkspace {
    func duplicateTab(_ tab: BrowserTab) {
        let copy = BrowserTab(tab.location); copy.restore(tab.session())
        let index = tabs.firstIndex { $0.id == tab.id } ?? tabs.count - 1
        tabs.insert(copy, at: index + 1); activeID = copy.id; saveSession()
    }
    func reopenClosedTab() {
        guard let session = closedTabs.popLast() else { return }
        let tab = BrowserTab(session.history.current); tab.restore(session)
        tabs.append(tab); activeID = tab.id; saveSession()
    }
    func cycleTab(_ offset: Int) {
        let index = tabs.firstIndex { $0.id == activeID } ?? 0
        guard !tabs.isEmpty else { return }; activeID = tabs[((index + offset) % tabs.count + tabs.count) % tabs.count].id
    }
    func selectTab(number: Int) {
        guard !tabs.isEmpty, number >= 1, number <= 9 else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        if tabs.indices.contains(index) { activeID = tabs[index].id }
    }
    func closeOtherTabs(keeping id: UUID, toRightOnly: Bool = false) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = toRightOnly ? Array(tabs.dropFirst(index + 1)) : tabs.filter { $0.id != id }
        activeID = id; for tab in closing { closeTab(tab.id) }
    }
    func receiveTab(from source: ExplorerWorkspace, id: UUID, before targetID: UUID?) {
        guard let sourceIndex = source.tabs.firstIndex(where: { $0.id == id }), !(source === self && id == targetID) else { return }
        let tab = source.tabs[sourceIndex]
        if source === self {
            var reordered = tabs; reordered.remove(at: sourceIndex)
            let index = targetID.flatMap { target in reordered.firstIndex { $0.id == target } } ?? reordered.count
            reordered.insert(tab, at: index); tabs = reordered
        } else {
            var remaining = source.tabs; remaining.remove(at: sourceIndex)
            if remaining.isEmpty { remaining = [BrowserTab(.home)] }
            source.tabs = remaining
            if source.activeID == id { source.activeID = remaining[min(sourceIndex, remaining.count - 1)].id }
            let index = targetID.flatMap { target in tabs.firstIndex { $0.id == target } } ?? tabs.count
            tabs.insert(tab, at: index); source.saveSession()
        }
        activeID = tab.id; saveSession()
    }
}
struct ExplorerTabStrip: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject private var input = InputPreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            Color.clear.frame(width: 8, height: 1).accessibilityHidden(true)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(workspace.tabs) { tab in WorkspaceTabItem(workspace: workspace, tab: tab, titlebar: true).id(tab.id) }
                        CommandIcon("New tab (⌘T / Ctrl+T)", "plus") { workspace.newTab() }
                            .modifier(TabDropTarget(workspace: workspace, before: nil))
                    }.padding(.vertical, 4)
                }.onChange(of: workspace.activeID) { _, id in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            Color.clear.frame(width: 16, height: 34).contentShape(Rectangle()).modifier(TabDropTarget(workspace: workspace, before: nil))
            Menu {
                ForEach(workspace.tabs) { tab in Button { workspace.activeID = tab.id } label: { Label(tab.location.title, systemImage: workspace.activeID == tab.id ? "checkmark" : tab.location.symbol) } }
                Divider(); Button("Reopen Closed Tab") { workspace.reopenClosedTab() }.disabled(workspace.closedTabs.isEmpty)
            } label: { Image(systemName: "chevron.down").font(.system(size: 10)).frame(width: input.target, height: input.target) }
                .buttonStyle(ExplorerIconStyle()).menuStyle(.borderlessButton).menuIndicator(.hidden).help("All tabs").padding(.trailing, 12).padding(.bottom, 4)
        }.frame(height: input.touchFriendly ? 52 : 42).background(ExplorerDesign.chrome)
    }
}
struct WorkspaceTabItem: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    var titlebar = false
    @ObservedObject private var input = InputPreferences.shared
    @State private var hovered = false
    private var active: Bool { workspace.activeID == tab.id }
    private var height: CGFloat { input.touchFriendly ? 44 : 34 }
    var body: some View {
        HStack(spacing: 8) {
            Button { workspace.activatePane(); workspace.activeID = tab.id } label: {
                HStack(spacing: 8) {
                    Image(systemName: tab.location.symbol).foregroundStyle(active ? Color.accentColor : ExplorerDesign.muted).font(.system(size: 13))
                    Text(tab.location.title).lineLimit(1).truncationMode(.middle).font(.system(size: 12, weight: active ? .medium : .regular))
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: height).contentShape(Rectangle())
                    .background(TabDragAnchor(tab: tab, workspace: workspace))
            }.buttonStyle(.plain)
            Button { workspace.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9)).frame(width: input.touchFriendly ? 32 : 20, height: height) }
                .buttonStyle(ExplorerIconStyle()).accessibilityLabel("Close " + tab.location.title)
        }.padding(.horizontal, 10).frame(width: input.touchFriendly ? 200 : 180, height: height)
            .background(active ? ExplorerDesign.canvas : hovered ? ExplorerDesign.hover : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? ExplorerDesign.separator : .clear, lineWidth: 1))
            .onHover { hovered = $0 }.modifier(TabDropTarget(workspace: workspace, before: tab.id))
            .help(tab.location.directory?.path ?? tab.location.title).accessibilityAddTraits(active ? .isSelected : [])
            .contextMenu {
                Button("Duplicate Tab") { workspace.duplicateTab(tab) }
                if let other = workspace.paneController?.other(than: workspace) {
                    Button("Move to Other Pane") { other.receiveTab(from: workspace, id: tab.id, before: nil); other.activatePane() }
                }
                Button("Move to New Window") { TabTransferCoordinator.shared.detach(tab, from: workspace) }
                Divider(); Button("Close Tab") { workspace.closeTab(tab.id) }
                Button("Close Other Tabs") { workspace.closeOtherTabs(keeping: tab.id) }
                Button("Close Tabs to the Right") { workspace.closeOtherTabs(keeping: tab.id, toRightOnly: true) }
                Divider(); Button("Reopen Closed Tab") { workspace.reopenClosedTab() }.disabled(workspace.closedTabs.isEmpty)
            }
    }
}
