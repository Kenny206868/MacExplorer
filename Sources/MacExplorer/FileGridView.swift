import SwiftUI
import AppKit
import ExplorerCore

struct FileGridView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @State private var marquee: CGRect?
    @State private var marqueeOrigin: CGPoint?
    @StateObject private var autoScroller = MarqueeAutoScroller()
    @State private var selectionSession: FileMarqueeSession?
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
                let groups = tab.groups
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
                        if let origin = marqueeOrigin { updateMarquee(from: origin, to: point, layout: layout) }
                    }).coordinateSpace(name: space)
                    .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
                        .onChanged { value in
                            guard !ignoredDrag else { return }
                            if marquee == nil {
                                ignoredDrag = layout.index(at: value.startLocation) != nil; guard !ignoredDrag else { return }
                                marqueeOrigin = value.startLocation
                                let flags = NSEvent.modifierFlags
                                selectionSession = FileMarqueeSession(tab: tab,
                                    mode: !flags.intersection([.command, .control]).isEmpty ? .toggle : flags.contains(.shift) ? .add : .replace)
                                workspace.activatePane(files: true)
                            }
                            guard !ignoredDrag else { return }
                            updateMarquee(from: value.startLocation, to: value.location, layout: layout)
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
                    .onChange(of: layout.columns) { _, count in invalidateMarquee(); tab.gridColumns = count }
                    .onChange(of: tab.focusedURL) { _, url in if marquee == nil, let url { proxy.scrollTo(url) } }
                    .onChange(of: tab.location) { _, _ in invalidateMarquee() }
                    .onChange(of: tab.presentationBuilds) { _, _ in invalidateMarquee() }
                    .onChange(of: tab.options) { _, _ in invalidateMarquee() }
                    .onChange(of: viewport.size.width) { _, _ in invalidateMarquee() }
                    .onChange(of: itemHeight) { _, _ in invalidateMarquee() }
            }
        }
    }
    private func invalidateMarquee() {
        let dragging = marqueeOrigin != nil || ignoredDrag
        resetMarquee(); ignoredDrag = dragging
    }
    private func resetMarquee() { marquee = nil; marqueeOrigin = nil; ignoredDrag = false; selectionSession = nil; autoScroller.stop() }
    private func updateMarquee(from origin: CGPoint, to point: CGPoint, layout: ExplorerGridGeometry) {
        let r = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        marquee = r
        let indices = layout.indexSet(intersecting: r)
        switch selectionSession?.update(hits: indices) {
        case .changed(let lastHit): if let lastHit, tab.focusedURL != lastHit { tab.focusedURL = lastHit }
        case .invalidated: invalidateMarquee()
        default: break
        }
    }
}
