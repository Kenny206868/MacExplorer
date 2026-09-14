import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class TabTransferTests: XCTestCase {
    @MainActor private func workspace(_ location: Location = .home) -> ExplorerWorkspace {
        let result = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(location), options: FolderOptions(), query: "", allLocations: false, selection: []))
        result.current.stop(); return result
    }
    @MainActor func testTicketsAreOneShotAndKeepLiveSelectionHistoryAcrossPanes() async throws {
        let first = workspace(), second = workspace(.computer), broker = TabTransferCoordinator()
        defer { first.tabs.forEach { $0.stop() }; second.tabs.forEach { $0.stop() }; AppRouter.shared.active = nil }
        let tab = first.current; tab.selection = [URL(fileURLWithPath: "/kept.txt")]
        tab.history.navigate(.network)
        let ticket = try XCTUnwrap(broker.begin(tab: tab, source: first))
        XCTAssertFalse(broker.accept(Data("invalid".utf8), into: second, before: nil))
        XCTAssertTrue(broker.accept(ticket, into: second, before: second.activeID))
        XCTAssertTrue(second.current === tab)
        XCTAssertEqual(second.current.selection.count, 1)
        XCTAssertTrue(second.current.history.canGoBack)
        XCTAssertFalse(broker.accept(ticket, into: first, before: nil))
        XCTAssertEqual(first.tabs.count, 1); XCTAssertEqual(first.current.location, .home)
    }
    @MainActor func testCancelledOrFailedDropKeepsOriginalTab() async throws {
        let first = workspace(), second = workspace(.computer), broker = TabTransferCoordinator()
        defer { first.tabs.forEach { $0.stop() }; second.tabs.forEach { $0.stop() } }
        let tab = first.current
        let data = try XCTUnwrap(broker.begin(tab: tab, source: first))
        broker.end(operation: [], released: false, outside: true, point: .zero)
        XCTAssertTrue(first.current === tab)
        XCTAssertFalse(broker.accept(data, into: second, before: nil))
        let fresh = try XCTUnwrap(broker.begin(tab: tab, source: first))
        broker.cancel(); XCTAssertFalse(broker.accept(fresh, into: second, before: nil))
    }
    @MainActor func testDetachmentWaitsForTargetAndTransfersTheActualTab() async throws {
        let first = workspace(.network), broker = TabTransferCoordinator.shared
        let original = first.current
        let session = try XCTUnwrap(broker.detach(original, from: first))
        XCTAssertTrue(first.current === original, "Requesting a new window must not close the source")
        let second = ExplorerWorkspace(session: session); second.current.stop()
        defer { first.tabs.forEach { $0.stop() }; second.tabs.forEach { $0.stop() }; AppRouter.shared.active = nil }
        broker.completeArrival(in: second)
        XCTAssertTrue(second.current === original)
        XCTAssertEqual(second.tabs.count, 1)
        XCTAssertFalse(first.tabs.contains { $0 === original })
        broker.completeArrival(in: second)
        XCTAssertEqual(second.tabs.count, 1)
    }
}
