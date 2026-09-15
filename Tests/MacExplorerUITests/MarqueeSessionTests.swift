import XCTest
import Combine
import ExplorerCore
@testable import MacExplorer

final class MarqueeSessionTests: XCTestCase {
    @MainActor func testStableHitsPublishSelectionOnlyOnce() throws {
        let (tab, root) = try fixture()
        defer { tab.stop(); try? FileManager.default.removeItem(at: root) }
        let ordered = tab.navigation.entries.map(\.url)
        let session = FileMarqueeSession(tab: tab, mode: .replace)
        var publications = 0
        let subscription = tab.$selection.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        guard case .changed(let last) = session.update(hits: [0, 1]) else { return XCTFail("First hits must publish") }
        XCTAssertEqual(last, ordered[1]); XCTAssertEqual(tab.selection, Set(ordered.prefix(2)))
        for _ in 0..<1000 {
            guard case .unchanged = session.update(hits: [0, 1]) else { return XCTFail("Stable hits reprojected") }
        }
        XCTAssertEqual(publications, 1, "Pointer movement inside the same rows must not invalidate the file UI")
    }

    @MainActor func testRefreshRejectsOldDragBeforeAViewCanObserveIt() throws {
        let (tab, root) = try fixture()
        defer { tab.stop(); try? FileManager.default.removeItem(at: root) }
        let session = FileMarqueeSession(tab: tab, mode: .replace)
        _ = session.update(hits: [0])
        let kept = try XCTUnwrap(tab.entries.last?.url)
        tab.entries.reverse(); tab.selection = [kept]
        guard case .invalidated = session.update(hits: [0, 1]) else { return XCTFail("Refreshed data reused an obsolete identity order") }
        XCTAssertEqual(tab.selection, [kept])
    }

    @MainActor func testReorderRejectsOldDragEvenWithoutADataRevisionChange() throws {
        let (tab, root) = try fixture()
        let original = tab.options
        defer { tab.options = original; tab.stop(); try? FileManager.default.removeItem(at: root) }
        let session = FileMarqueeSession(tab: tab, mode: .toggle)
        let revision = tab.dataRevision
        tab.options.descending.toggle()
        XCTAssertEqual(tab.dataRevision, revision)
        guard case .invalidated = session.update(hits: [0]) else { return XCTFail("Reordered presentation reused old drag indices") }
        XCTAssertTrue(tab.selection.isEmpty)
    }

    @MainActor private func fixture() throws -> (BrowserTab, URL) {
        let manager = FileManager.default, root = manager.temporaryDirectory.appendingPathComponent("Marquee-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let tab = BrowserTab(.folder(root))
        do {
            tab.entries = try ["a.txt", "b.txt", "c.txt"].map { name in
                let url = root.appendingPathComponent(name); try Data().write(to: url); return try FileEntry(url: url)
            }
            return (tab, root)
        } catch { tab.stop(); try? manager.removeItem(at: root); throw error }
    }
}
