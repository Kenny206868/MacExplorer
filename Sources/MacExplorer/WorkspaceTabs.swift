import SwiftUI
import AppKit
import ExplorerCore

/// A value-based SwiftUI window request, independent of its location.
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
        query = session.query; allLocations = session.allLocations
        selection = Set(session.selection)
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
        let next = ((index + offset) % tabs.count + tabs.count) % tabs.count
        activeID = tabs[next].id
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
            tabs.insert(tab, at: index)
            source.saveSession()
        }
        activeID = tab.id; saveSession()
    }
}

/// Only a live tab from this process can consume the unguessable drag ticket.
@MainActor private final class TabDragSession {
    static let shared = TabDragSession()
    static let type = "com.wieslawsoltes.macexplorer.tab"
    private weak var source: ExplorerWorkspace?
    private var tabID: UUID?
    private var ticket: String?
    func begin(_ tab: BrowserTab, in workspace: ExplorerWorkspace) -> NSItemProvider {
        source = workspace; tabID = tab.id; ticket = UUID().uuidString
        let data = Data((ticket ?? "").utf8)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.type, visibility: .ownProcess) { completion in completion(data, nil); return nil }
        provider.suggestedName = tab.location.title
        return provider
    }
    func accept(_ providers: [NSItemProvider], into workspace: ExplorerWorkspace, before id: UUID?) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(Self.type) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: Self.type) { data, _ in
            Task { @MainActor in
                guard let data, String(data: data, encoding: .utf8) == self.ticket,
                      let source = self.source, let tabID = self.tabID else { return }
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
    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: 76, height: 1)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(workspace.tabs) { tab in ExplorerTabLabel(tab: tab, workspace: workspace).id(tab.id) }
                        Button { workspace.newTab() } label: { Image(systemName: "plus").frame(width: 30, height: 30) }
                            .buttonStyle(.plain).help("New tab (⌘T / Ctrl+T)")
                    }.padding(.top, 9)
                }
                .onChange(of: workspace.activeID) { _, id in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            Color.clear.frame(width: 26, height: 32).contentShape(Rectangle())
                .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 5).fill(.tint.opacity(0.15)) } }
                .onDrop(of: [TabDragSession.type], isTargeted: $dropTargeted) { TabDragSession.shared.accept($0, into: workspace, before: nil) }
            Menu {
                ForEach(workspace.tabs) { tab in
                    Button { workspace.activeID = tab.id } label: { Label(tab.location.title, systemImage: workspace.activeID == tab.id ? "checkmark" : tab.location.symbol) }
                }
                Divider()
                Button("Reopen Closed Tab") { workspace.reopenClosedTab() }.disabled(workspace.closedTabs.isEmpty)
            } label: { Image(systemName: "chevron.down").frame(width: 22) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).help("All tabs").padding(.trailing, 12)
        }.frame(height: 45).background(.bar)
    }
}

private struct ExplorerTabLabel: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var workspace: ExplorerWorkspace
    @Environment(\.openWindow) private var openWindow
    @State private var targeted = false
    var body: some View {
        HStack(spacing: 8) {
            Button { workspace.activeID = tab.id } label: {
                Label(tab.location.title, systemImage: tab.location.symbol).font(.system(size: 12))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button { workspace.closeTab(tab.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).frame(width: 18, height: 22)
            }.buttonStyle(.plain).help("Close tab")
        }
        .padding(.horizontal, 10).frame(width: 180, height: 35)
        .background(workspace.activeID == tab.id ? Color(nsColor: .textBackgroundColor) : .clear, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
        .overlay(alignment: .leading) { if targeted { Capsule().fill(.tint).frame(width: 3, height: 25) } }
        .onDrag { TabDragSession.shared.begin(tab, in: workspace) }
        .onDrop(of: [TabDragSession.type], isTargeted: $targeted) { TabDragSession.shared.accept($0, into: workspace, before: tab.id) }
        .help(tab.location.directory?.path ?? tab.location.title)
        .contextMenu {
            Button("Duplicate Tab") { workspace.duplicateTab(tab) }
            Button("Move to New Window") { openWindow(id: "detached", value: tab.session()); workspace.closeTab(tab.id) }
            Divider()
            Button("Close Tab") { workspace.closeTab(tab.id) }
            Button("Close Other Tabs") { workspace.closeOtherTabs(keeping: tab.id) }
            Button("Close Tabs to the Right") { workspace.closeOtherTabs(keeping: tab.id, toRightOnly: true) }
            Divider()
            Button("Reopen Closed Tab") { workspace.reopenClosedTab() }.disabled(workspace.closedTabs.isEmpty)
        }
    }
}
