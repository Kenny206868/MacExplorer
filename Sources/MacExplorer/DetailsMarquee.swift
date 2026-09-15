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
    @State private var selectionSession: FileMarqueeSession?
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
                    origin = value.startLocation
                    let flags = NSEvent.modifierFlags
                    selectionSession = FileMarqueeSession(tab: tab,
                        mode: !flags.intersection([.command, .control]).isEmpty ? .toggle : flags.contains(.shift) ? .add : .replace)
                    workspace.activatePane(files: true)
                }
                guard !ignored, let origin else { return }; update(from: origin, to: value.location)
            }.onEnded { _ in finish() })
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(space)).onEnded { value in
                if value.location.y > geometry.height && NSEvent.modifierFlags.intersection([.command, .control, .shift]).isEmpty {
                    tab.selection = []; tab.focusedURL = nil; tab.selectionAnchor = nil
                }
            })
            .onDisappear { finish() }.onChange(of: tab.location) { _, _ in invalidate() }
            .onChange(of: tab.presentationBuilds) { _, _ in invalidate() }
            .onChange(of: tab.options) { _, _ in invalidate() }
            .onChange(of: tab.collapsedGroups) { _, _ in invalidate() }
            .onChange(of: geometry.rowHeight) { _, _ in invalidate() }
            .onChange(of: geometry.headerHeight) { _, _ in invalidate() }
    }
    private func update(from origin: CGPoint, to point: CGPoint) {
        rectangle = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        let indices = geometry.indexSet(from: origin.y, through: point.y)
        if case .invalidated = selectionSession?.update(hits: indices) { invalidate() }
    }
    private func invalidate() {
        let dragging = origin != nil || ignored
        rectangle = nil; origin = nil; selectionSession = nil; ignored = dragging; scroll.stop()
    }
    private func finish() {
        if rectangle != nil { tab.selectionAnchor = tab.selectedEntries.first?.url; tab.focusedURL = tab.selectionAnchor }
        rectangle = nil; origin = nil; selectionSession = nil; ignored = false; scroll.stop()
    }
}
