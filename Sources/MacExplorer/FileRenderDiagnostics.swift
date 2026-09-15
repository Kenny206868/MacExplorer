import Foundation

/// Aggregate counters, enabled only for debug or an explicitly instrumented
/// performance build. No paths, content, identifiers or UI publications.
@MainActor enum FileRenderDiagnostics {
    private(set) static var detailsRowBodies: UInt64 = 0
    @inline(__always) static func detailsRowBody() {
        #if DEBUG || MACEXPLORER_PERFORMANCE_DIAGNOSTICS
        detailsRowBodies &+= 1
        #endif
    }
}
