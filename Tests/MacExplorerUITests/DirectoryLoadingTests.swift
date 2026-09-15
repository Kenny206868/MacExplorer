import XCTest
import ExplorerCore
@testable import MacExplorer

final class DirectoryLoadingTests: XCTestCase {
    @MainActor private func waitForIdle(_ tab: BrowserTab) async throws {
        let deadline = Date().addingTimeInterval(12)
        while tab.work != nil || tab.searchDebounce != nil || tab.refreshDebounce != nil || tab.projectionTask != nil {
            guard Date() < deadline else { XCTFail("Directory pipeline did not settle"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DirectoryLoading-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<120 { try Data().write(to: root.appendingPathComponent("file\(index).txt")) }; return root
    }
    @MainActor func testNotificationStormCoalescesWithoutCancellingCurrentLoad() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let tab = BrowserTab(.folder(root)); defer { tab.stop() }
        tab.refresh(); for _ in 0..<400 { tab.requestFilesystemRefresh() }
        try await waitForIdle(tab)
        XCTAssertEqual(tab.entries.count, 120)
        XCTAssertLessThanOrEqual(tab.refreshStarts, 2, "A storm gets one in-flight load and one trailing refresh")
        XCTAssertGreaterThanOrEqual(tab.snapshotInstalls, 1)
        let builds = tab.presentationBuilds
        for _ in 0..<100 { _ = tab.navigation; _ = tab.displayEntries }
        XCTAssertEqual(tab.presentationBuilds, builds, "Prepared listings must not sort in view getters")
    }
    @MainActor func testNavigationAndTypingRejectOldDirectoryResults() async throws {
        let root = try fixture(), other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
        try Data().write(to: other.appendingPathComponent("Only-current.txt"))
        defer { try? FileManager.default.removeItem(at: root) }
        let tab = BrowserTab(.folder(root)); defer { tab.stop() }
        tab.refresh(); tab.navigate(.folder(other)); tab.query = "Only"; tab.requestFilesystemRefresh()
        try await waitForIdle(tab)
        XCTAssertEqual(tab.location, .folder(other)); XCTAssertEqual(tab.entries.map(\.name), ["Only-current.txt"]); XCTAssertNil(tab.error)
        tab.options.descending = true; try await waitForIdle(tab)
        XCTAssertEqual(tab.visibleEntries.map(\.name), ["Only-current.txt"])
    }
}
