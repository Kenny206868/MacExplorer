import AppKit

@MainActor extension NSView {
    /// visibleRect describes drawing visibility, NOT hit-test bounds. In apps
    /// linked with macOS 14+ it can extend beyond bounds when clipsToBounds is
    /// false. Transparent input anchors must intersect both spaces explicitly.
    var inputHitRect: NSRect { bounds.intersection(visibleRect) }
}
