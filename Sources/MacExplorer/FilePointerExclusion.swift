import SwiftUI
import AppKit

/// Child controls handle their own clicks, including when Name is reordered.
/// The marker never intercepts input or replaces the SwiftUI control.
struct FilePointerExclusion: NSViewRepresentable {
    func makeNSView(context: Context) -> FilePointerExclusionView {
        let view = FilePointerExclusionView(); FileDragRouter.shared.exclude(view); return view
    }
    func updateNSView(_ view: FilePointerExclusionView, context: Context) {}
    static func dismantleNSView(_ view: FilePointerExclusionView, coordinator: ()) { FileDragRouter.shared.removeExclusion(view) }
}
@MainActor final class FilePointerExclusionView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
