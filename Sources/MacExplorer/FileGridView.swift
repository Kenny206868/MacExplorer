import SwiftUI
import AppKit
import ExplorerCore

struct FileGridView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @State private var marquee: CGRect?
    @State private var marqueeOrigin: CGPoint?
    @StateObject private var autoScroller = MarqueeAutoScroller()
    @State private var baseSelection: Set<URL> = []
    @State private var selectionMode = 0
    @State private var ignoredDrag = false
    @ObservedObject private var input = InputPreferences.shared
    private var space: String { "MacExplorer.grid." + tab.id.uuidString }
    private var minimumWidth: CGFloat {
        switch tab.options.view { case .extraLarge: return 170; case .tiles, .small, .details: return 240; case .gallery: return 180; default: return 125 }
    }
    private var itemHeight: CGFloat { input.gridCellHeight(tab.options.view) }
    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                let groups = tab.groups, entries = tab.displayEntries
                let layout = ExplorerGridGeometry(counts: groups.map { $0.1.count }, width: viewport.size.width,
                                                  minimumWidth: minimumWidth, cellHeight: itemHeight, headers: tab.options.group != .none)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            if !group.0.isEmpty { Text(group.0).font(.headline).frame(height: 28, alignment: .leading) }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: layout.columns), alignment: .leading, spacing: 10) {
                                ForEach(group.1) { entry in FileTile(entry: entry, workspace: workspace, tab: tab).frame(height: itemHeight).id(entry.url) }
                            }.padding(.bottom, 15)
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading).contentShape(Rectangle())
                    .overlay(alignment: .topLeading) {
                        if let marquee {
                            Rectangle().fill(Color.accentColor.opacity(0.12)).overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                                .frame(width: marquee.width, height: marquee.height).offset(x: marquee.minX, y: marquee.minY).allowsHitTesting(false)
                        }
                    }
                    .background(MarqueeScrollBridge(controller: autoScroller, active: marquee != nil) { point in
                        if let origin = marqueeOrigin { updateMarquee(from: origin, to: point, layout: layout, entries: entries) }
                    }).coordinateSpace(name: space)
                    .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
                        .onChanged { value in
                            if marquee == nil {
                                ignoredDrag = layout.index(at: value.startLocation) != nil; guard !ignoredDrag else { return }
                                marqueeOrigin = value.startLocation; baseSelection = tab.selection
                                let flags = NSEvent.modifierFlags
                                selectionMode = !flags.intersection([.command, .control]).isEmpty ? 2 : flags.contains(.shift) ? 1 : 0
                            }
                            guard !ignoredDrag else { return }
                            updateMarquee(from: value.startLocation, to: value.location, layout: layout, entries: entries)
                        }.onEnded { _ in
                            if marquee != nil { tab.selectionAnchor = tab.focusedURL }; resetMarquee()
                        })
                    .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(space)).onEnded { value in
                        if !workspace.touchSelecting && layout.index(at: value.location) == nil && NSEvent.modifierFlags.intersection([.command, .control, .shift]).isEmpty {
                            tab.selection = []; tab.focusedURL = nil; tab.selectionAnchor = nil
                        }
                    })
                }.onDisappear { resetMarquee() }
                    .onAppear { tab.gridColumns = layout.columns }
                    .onChange(of: layout.columns) { _, count in tab.gridColumns = count }
                    .onChange(of: tab.focusedURL) { _, url in if marquee == nil, let url { proxy.scrollTo(url) } }
                    .onChange(of: tab.location) { _, _ in resetMarquee() }
            }
        }
    }
    private func resetMarquee() { marquee = nil; marqueeOrigin = nil; ignoredDrag = false; baseSelection = []; autoScroller.stop() }
    private func updateMarquee(from origin: CGPoint, to point: CGPoint, layout: ExplorerGridGeometry, entries: [FileEntry]) {
        let r = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        marquee = r
        let indices = layout.indices(intersecting: r)
        let hits = Set(indices.compactMap { entries.indices.contains($0) ? entries[$0].url : nil })
        tab.selection = selectionMode == 2 ? baseSelection.symmetricDifference(hits) : selectionMode == 1 ? baseSelection.union(hits) : hits
        if let index = indices.last, entries.indices.contains(index) { tab.focusedURL = entries[index].url }
    }
}
