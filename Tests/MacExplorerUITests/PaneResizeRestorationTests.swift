import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

/// Tests the production SwiftUI pane allocator through an actual resizable
/// native window. The retired NSSplitView initializer is no longer in the app.
final class PaneResizeRestorationTests: XCTestCase {
    @MainActor private final class Probe { var regions: [String: CGRect] = [:] }
    @MainActor func testNarrowWindowClampsAndWideningRestoresPreferredSizes() async throws {
        _ = NSApplication.shared
        let preferences = PreferenceStore.shared, saved = PreferenceStore.shared.value
        defer { preferences.value = saved }
        preferences.value.inspector = true; preferences.value.previewPane = false
        preferences.value.pins = []; preferences.value.recent = []
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.home), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop()
        let probe = Probe()
        let host = NSHostingView(rootView: WorkspaceShell(workspace: workspace, tab: workspace.current)
            .environmentObject(workspace).environmentObject(preferences)
            .onPreferenceChange(ExplorerLayoutRegions.self) { probe.regions = $0 })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 700), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFrontRegardless()
        defer { workspace.tabs.forEach { $0.stop() }; window.orderOut(nil); window.contentView = nil; window.close() }
        for width in [1260.0, 800, 960, 1260] {
            window.setContentSize(NSSize(width: width, height: 700))
            try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
            let sidebar = try XCTUnwrap(probe.regions["sidebar"])
            let files = try XCTUnwrap(probe.regions["files"])
            let inspector = try XCTUnwrap(probe.regions["inspector"])
            XCTAssertEqual(sidebar.width, 211, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(files.width, 349.5)
            XCTAssertLessThanOrEqual(inspector.maxX, width + 0.5)
            XCTAssertEqual(sidebar.width + files.width + inspector.width + 2, width, accuracy: 0.5)
            if width == 1260 { XCTAssertEqual(inspector.width, 254, accuracy: 0.5); XCTAssertEqual(files.width, 793, accuracy: 0.5) }
            if width == 800 { XCTAssertEqual(inspector.width, 237, accuracy: 0.5) }
            XCTAssertTrue(preferences.value.inspector)
        }
    }
}
