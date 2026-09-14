import SwiftUI
import AppKit
import ExplorerCore

struct DetailsMarquee: ViewModifier {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    let geometry: DetailsRowGeometry
    let entries: [FileEntry]
    @State private var rectangle: CGRect?
    @State private var origin: CGPoint?
    @State private var baseline: Set<URL> = []
    @State private var mode = 0
    @State private var ignored = false
    @StateObject private var scroll = MarqueeAutoScroller()
    private var space: String { "details-selection." + tab.id.uuidString }
    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if let rectangle {
                    Rectangle().fill(Color.accentColor.opacity(0.1)).overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                        .frame(width: rectangle.width, height: rectangle.height).offset(x: rectangle.minX, y: rectangle.minY).allowsHitTesting(false)
                }
            }
            .background(MarqueeScrollBridge(controller: scroll, active: rectangle != nil) { point in if let origin { update(from: origin, to: point) } })
            .coordinateSpace(name: space)
            .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named(space)).onChanged { value in
                if origin == nil && !ignored {
                    ignored = value.startLocation.y < geometry.headerHeight || geometry.index(at: value.startLocation.y) != nil
                    guard !ignored else { return }
                    origin = value.startLocation; baseline = tab.selection
                    let flags = NSEvent.modifierFlags
                    mode = !flags.intersection([.command, .control]).isEmpty ? 2 : flags.contains(.shift) ? 1 : 0
                    workspace.activatePane(files: true)
                }
                guard !ignored, let origin else { return }; update(from: origin, to: value.location)
            }.onEnded { _ in finish() })
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(space)).onEnded { value in
                if value.location.y > geometry.height && NSEvent.modifierFlags.intersection([.command, .control, .shift]).isEmpty {
                    tab.selection = []; tab.focusedURL = nil; tab.selectionAnchor = nil
                }
            })
            .onDisappear { finish() }.onChange(of: tab.location) { _, _ in finish() }
    }
    private func update(from origin: CGPoint, to point: CGPoint) {
        rectangle = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        let indices = geometry.indices(from: origin.y, through: point.y)
        let hits = Set(indices.compactMap { entries.indices.contains($0) ? entries[$0].url : nil })
        tab.selection = mode == 2 ? baseline.symmetricDifference(hits) : mode == 1 ? baseline.union(hits) : hits
    }
    private func finish() {
        if rectangle != nil { tab.selectionAnchor = entries.first(where: { tab.selection.contains($0.url) })?.url; tab.focusedURL = tab.selectionAnchor }
        rectangle = nil; origin = nil; baseline = []; ignored = false; scroll.stop()
    }
}
