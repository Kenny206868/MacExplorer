import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class WorkspaceLayoutIntegrationTests: XCTestCase {
    @MainActor private final class Regions { var values: [String: CGRect] = [:] }

    @MainActor func testActualSwiftUILayoutDoesNotOverlapOrOverflow() async throws {
        _ = NSApplication.shared
        let preferences = PreferenceStore.shared, original = PreferenceStore.shared.value
        let key = "MacExplorer.preferences.v1", saved = UserDefaults.standard.data(forKey: "MacExplorer.preferences.v1")
        defer {
            preferences.value = original
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        preferences.value.pins = []; preferences.value.recent = []
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.home), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop()
        for width in [800.0, 860, 960, 1024, 1200, 1240, 1440, 1600, 1920] {
            for flags in 0..<4 {
                preferences.value.inspector = flags & 1 != 0
                preferences.value.previewPane = flags & 2 != 0
                let regions = Regions(), size = NSSize(width: width, height: 700)
                let host = NSHostingView(rootView: WorkspaceShell(workspace: workspace, tab: workspace.current)
                    .environmentObject(workspace).environmentObject(preferences)
                    .onPreferenceChange(ExplorerLayoutRegions.self) { regions.values = $0 })
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host
                host.frame = NSRect(origin: .zero, size: size); window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                let label = "width=\(width), panes=\(flags)"
                let required: Set<String> = ["tabs", "commands", "address", "sidebar", "files", "status"]
                XCTAssertTrue(required.isSubset(of: Set(regions.values.keys)), "Missing geometry: \(label): \(regions.values.keys)")
                for (name, rect) in regions.values {
                    XCTAssertGreaterThan(rect.width, 0, "\(name): \(label)")
                    XCTAssertGreaterThan(rect.height, 0, "\(name): \(label)")
                    XCTAssertGreaterThanOrEqual(rect.minX, -1, "\(name): \(label)")
                    XCTAssertGreaterThanOrEqual(rect.minY, -1, "\(name): \(label)")
                    XCTAssertLessThanOrEqual(rect.maxX, width + 1, "\(name): \(label)")
                    XCTAssertLessThanOrEqual(rect.maxY, 701, "\(name): \(label)")
                }
                if let files = regions.values["files"] { XCTAssertGreaterThanOrEqual(files.width, 349, label) }
                let panes = ["sidebar", "files", "auxiliary", "preview", "inspector"].compactMap { regions.values[$0] }
                for index in panes.indices {
                    for other in panes.indices where other > index {
                        let overlap = panes[index].intersection(panes[other])
                        XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1, "Overlapping panes: \(label)")
                    }
                }
                if flags == 3 {
                    XCTAssertEqual(regions.values["auxiliary"] != nil, width < 1240, label)
                }
                window.orderOut(nil); window.contentView = nil; window.close()
            }
        }
        workspace.tabs.forEach { $0.stop() }
    }
}
