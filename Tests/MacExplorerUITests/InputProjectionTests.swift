import XCTest
import Combine
import ExplorerCore
@testable import MacExplorer

final class InputProjectionTests: XCTestCase {
    @MainActor func testRepeatedInputReusesOrderAndSelectedProjection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InputProjection-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        let tab = workspace.current; tab.stop(); defer { tab.stop() }
        tab.entries = try (0..<128).map { index in
            let url = root.appendingPathComponent("file\(index).txt"); try Data().write(to: url); return try FileEntry(url: url)
        }
        workspace.selectBoundary(last: false, extend: false)
        let initialBuilds = tab.navigationBuilds
        for _ in 0..<1000 { workspace.moveSelection(1); _ = workspace.selected; _ = workspace.selectedURLs }
        XCTAssertEqual(tab.navigationBuilds, initialBuilds)
        XCTAssertEqual(tab.focusedURL, tab.navigation.order.ids.last)
        let projectionCount = tab.selectedProjectionBuilds
        var updates = 0
        let token = tab.objectWillChange.sink { updates += 1 }
        for _ in 0..<200 { workspace.moveSelection(1); _ = workspace.selected; _ = workspace.selectedURLs }
        XCTAssertEqual(updates, 0, "Holding Down at the last row must not republish unchanged state")
        XCTAssertEqual(tab.selectedProjectionBuilds, projectionCount)
        withExtendedLifetime(token) {}
        tab.options.group = .kind; _ = tab.navigation
        XCTAssertGreaterThan(tab.navigationBuilds, initialBuilds)
    }
}
