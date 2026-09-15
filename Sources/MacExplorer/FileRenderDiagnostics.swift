import Foundation

/// Debug-only aggregate counters. No file paths, content or user identifiers.
/// They do not publish UI changes and are inert in distribution builds.
@MainActor enum FileRenderDiagnostics {
    private(set) static var detailsRowBodies: UInt64 = 0
    @inline(__always) static func detailsRowBody() {
        #if DEBUG
        detailsRowBodies &+= 1
        #endif
    }
}
