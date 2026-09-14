import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class SessionPersistenceTests: XCTestCase {
    private func store() throws -> SessionDiskStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorer-Sessions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return SessionDiskStore(url: root.appendingPathComponent("windows.json"))
    }
    private func tab(_ location: Location = .home) -> BrowserSession {
        var history = NavigationHistory(location); history.navigate(.computer); history.back()
        var options = FolderOptions(); options.view = .gallery; options.descending = true
        return BrowserSession(id: UUID(), history: history, options: options, query: "ext:png", allLocations: true, selection: [])
    }
    func testCompleteSessionRoundTripAndPrivatePermissions() throws {
        let disk = try store()
        var value = SessionDocument()
        value.openWindows = [WindowSession(tabs: [tab(), tab(.gallery)], activeIndex: 1, closedTabs: [tab(.trash)], frame: CGRect(x: 5, y: 10, width: 1260, height: 800))]
        disk.write(value) { error in XCTAssertNil(error) }; disk.flush()
        let result = try disk.read()
        XCTAssertEqual(result.openWindows.count, 1)
        XCTAssertEqual(result.openWindows[0].activeIndex, 1)
        XCTAssertEqual(result.openWindows[0].tabs[0].history.current, .home)
        XCTAssertTrue(result.openWindows[0].tabs[0].history.canGoForward)
        XCTAssertEqual(result.openWindows[0].tabs[0].options.view, .gallery)
        XCTAssertEqual(result.openWindows[0].tabs[0].query, "ext:png")
        XCTAssertEqual(result.openWindows[0].closedTabs.count, 1)
        XCTAssertEqual(result.openWindows[0].frame?.width, 1260)
        let attributes = try FileManager.default.attributesOfItem(atPath: disk.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testInvalidNavigationAndEmptyWindowAreRejectedBeforeIndexing() throws {
        var value = SessionDocument(); value.openWindows = [WindowSession(tabs: [tab()], activeIndex: 0)]
        let data = try JSONEncoder().encode(value)
        for invalid in ["empty", "index"] {
            let disk = try store()
            var document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var windows = try XCTUnwrap(document["openWindows"] as? [[String: Any]])
            if invalid == "empty" { windows[0]["tabs"] = [] }
            else { windows[0]["activeIndex"] = 1234 }
            document["openWindows"] = windows
            try JSONSerialization.data(withJSONObject: document).write(to: disk.url)
            XCTAssertThrowsError(try disk.read())
        }
    }
    @MainActor func testOnlyInitialWindowClaimsRestoreAndAdditionalWindowsAreRequestedOnce() async throws {
        let disk = try store()
        var value = SessionDocument()
        value.openWindows = [WindowSession(tabs: [tab()], activeIndex: 0), WindowSession(tabs: [tab(.gallery)], activeIndex: 0)]
        disk.write(value) { _ in }; disk.flush()
        let coordinator = WorkspaceSessionCoordinator(storage: disk)
        guard case .restored(let first) = coordinator.claimInitialWindow(restore: true) else { return XCTFail("Missing initial restoration") }
        XCTAssertEqual(first.tabs[0].history.current, .home)
        guard case .fresh = coordinator.claimInitialWindow(restore: true) else { return XCTFail("New windows must not duplicate launch restoration") }
        var requested: [WindowSession] = []
        coordinator.restoreAdditionalWindows { requested.append($0) }
        coordinator.restoreAdditionalWindows { requested.append($0) }
        XCTAssertEqual(requested.count, 1)
        XCTAssertEqual(requested[0].tabs[0].history.current, .gallery)
    }
    @MainActor func testClosingWindowPersistsAndReopeningConsumesOneHistoryEntry() async throws {
        let disk = try store(), coordinator = WorkspaceSessionCoordinator(storage: disk)
        let workspace = ExplorerWorkspace(session: tab()); workspace.current.stop()
        coordinator.register(workspace); coordinator.close(workspace); coordinator.flushForTesting()
        XCTAssertEqual(try disk.read().closedWindows.count, 1)
        XCTAssertTrue(try disk.read().openWindows.isEmpty)
        XCTAssertNil(coordinator.reopen(UUID()))
        XCTAssertEqual(coordinator.closedWindows.count, 1)
        XCTAssertNotNil(coordinator.reopen())
        XCTAssertTrue(coordinator.closedWindows.isEmpty)
        XCTAssertNil(coordinator.reopen())
    }
    @MainActor func testQuitRetainsOpenWindowsRatherThanMovingThemToClosedHistory() async throws {
        let disk = try store(), coordinator = WorkspaceSessionCoordinator(storage: disk)
        let first = ExplorerWorkspace(session: tab()), second = ExplorerWorkspace(session: tab(.gallery))
        first.current.stop(); second.current.stop()
        coordinator.register(first); coordinator.register(second)
        coordinator.prepareToQuit(); coordinator.close(first); coordinator.close(second)
        let result = try disk.read()
        XCTAssertEqual(result.openWindows.count, 2)
        XCTAssertTrue(result.closedWindows.isEmpty)
    }
}
