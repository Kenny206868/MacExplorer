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
    func session() -> BrowserSession {
        BrowserSession(id: UUID(), history: history, options: options, query: query, allLocations: allLocations, selection: Array(selection))
    }
    func restore(_ session: BrowserSession) {
        history = session.history; options = session.options
        query = session.query; allLocations = session.allLocations; selection = Set(session.selection)
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
        guard !tabs.isEmpty else { return }
        activeID = tabs[((index + offset) % tabs.count + tabs.count) % tabs.count].id
    }
    func selectTab(number: Int) {
        guard !tabs.isEmpty, number >= 1, number <= 9 else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        if tabs.indices.contains(index) { activeID = tabs[index].id }
    }
    func closeOtherTabs(keeping id: UUID, toRightOnly: Bool = false) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = toRightOnly ? Array(tabs.dropFirst(index + 1)) : tabs.filter { $0.id != id }
        activeID = id
        for tab in closing { closeTab(tab.id) }
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

@MainActor private final class TabDragSession {
    static let shared = TabDragSession()
    static let type = "com.wieslawsoltes.macexplorer.tab"
    private weak var source: ExplorerWorkspace?
    private var tabID: UUID?
    private var ticket: String?
    func begin(_ tab: BrowserTab, in workspace: ExplorerWorkspace) -> NSItemProvider {
        source = workspace; tabID = tab.id; ticket = UUID().uuidString
        let data = Data((ticket ?? "").utf8), provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.type, visibility: .ownProcess) { completion in completion(data, nil); return nil }
        provider.suggestedName = tab.location.title; return provider
    }
    func accept(_ providers: [NSItemProvider], into workspace: ExplorerWorkspace, before id: UUID?) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(Self.type) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: Self.type) { data, _ in
            Task { @MainActor in
                guard let data, String(data: data, encoding: .utf8) == self.ticket, let source = self.source, let tabID = self.tabID else { return }
                workspace.receiveTab(from: source, id: tabID, before: id)
                self.source = nil; self.tabID = nil; self.ticket = nil
            }
        }
        return true
    }
}

struct ExplorerTabStrip: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @State private var dropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            Color.clear.frame(width: 84, height: 1).accessibilityHidden(true)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(workspace.tabs) { tab in ExplorerTabLabel(tab: tab, workspace: workspace).id(tab.id) }
                        CommandIcon("New tab (⌘T / Ctrl+T)", "plus") { workspace.newTab() }.padding(.bottom, 2)
                    }.padding(.top, 10)
                }.onChange(of: workspace.activeID) { _, id in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
            Color.clear.frame(width: 22, height: 36).contentShape(Rectangle())
                .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 5).fill(ExplorerDesign.selection) } }
                .onDrop(of: [TabDragSession.type], isTargeted: $dropTargeted) { TabDragSession.shared.accept($0, into: workspace, before: nil) }
            Menu {
                ForEach(workspace.tabs) { tab in Button { workspace.activeID = tab.id } label: { Label(tab.location.title, systemImage: workspace.activeID == tab.id ? "checkmark" : tab.location.symbol) } }
                Divider(); Button("Reopen Closed Tab") { workspace.reopenClosedTab() }.disabled(workspace.closedTabs.isEmpty)
            } label: { Image(systemName: "chevron.down").font(.system(size: 10)).frame(width: 30, height: 36) }
                .buttonStyle(ExplorerIconStyle()).menuStyle(.borderlessButton).menuIndicator(.hidden).help("All tabs").padding(.trailing, 12).padding(.bottom, 2)
        }.frame(height: ExplorerDesign.titleHeight).background(ExplorerDesign.chrome)
    }
}
private struct ExplorerTabLabel: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var workspace: ExplorerWorkspace
    @Environment(\.openWindow) private var openWindow
    @State private var targeted = false
    @State private var hovered = false
    private var active: Bool { workspace.activeID == tab.id }
    private var shape: UnevenRoundedRectangle { UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8) }
    var body: some View {
        HStack(spacing: 9) {
            Button { workspace.activeID = tab.id } label: {
                HStack(spacing: 9) {
                    Image(systemName: tab.location.symbol).foregroundStyle(active ? Color.accentColor : ExplorerDesign.muted).font(.system(size: 13))
                    Text(tab.location.title).lineLimit(1).font(.system(size: 12)).foregroundStyle(active ? ExplorerDesign.text : ExplorerDesign.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { workspace.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9)).frame(width: 20, height: 22) }
                .buttonStyle(ExplorerIconStyle()).help("Close tab").accessibilityLabel("Close " + tab.location.title)
        }.padding(.horizontal, 10).frame(width: 180, height: 37)
            .background(active ? ExplorerDesign.canvas : hovered ? ExplorerDesign.hover : .clear, in: shape)
            .overlay { shape.stroke(active ? ExplorerDesign.separator : .clear, lineWidth: 1) }
            .overlay(alignment: .bottom) { if active { Rectangle().fill(ExplorerDesign.canvas).frame(height: 1) } }
            .overlay(alignment: .leading) { if targeted { Capsule().fill(Color.accentColor).frame(width: 3, height: 26) } }
            .onHover { hovered = $0 }
            .onDrag { TabDragSession.shared.begin(tab, in: workspace) }
            .onDrop(of: [TabDragSession.type], isTargeted: $targeted) { TabDragSession.shared.accept($0, into: workspace, before: tab.id) }
            .help(tab.location.directory?.path ?? tab.location.title)
            .accessibilityAddTraits(active ? .isSelected : [])
            .contextMenu {
                Button("Duplicate Tab") { workspace.duplicateTab(tab) }
                Button("Move to New Window") { openWindow(id: "detached", value: tab.session()); workspace.closeTab(tab.id) }
                Divider(); Button("Close Tab") { workspace.closeTab(tab.id) }
                Button("Close Other Tabs") { workspace.closeOtherTabs(keeping: tab.id) }
                Button("Close Tabs to the Right") { workspace.closeOtherTabs(keeping: tab.id, toRightOnly: true) }
                Divider(); Button("Reopen Closed Tab") { workspace.reopenClosedTab() }.disabled(workspace.closedTabs.isEmpty)
            }
    }
}
