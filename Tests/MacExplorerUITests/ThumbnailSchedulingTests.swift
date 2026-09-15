import XCTest
import AppKit
import QuickLookThumbnailing
import ExplorerCore
@testable import MacExplorer

final class ThumbnailSchedulingTests: XCTestCase {
    @MainActor func testCoalescedRequestsCancelOnlyAfterLastSubscriber() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThumbnailSchedule-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("file.txt"); try Data().write(to: url)
        let entry = try FileEntry(url: url)
        var completions: [ThumbnailCache.Completion] = [], cancellations = 0
        let cache = ThumbnailCache(limit: 1, start: { _, completion in completions.append(completion) }, cancel: { _ in cancellations += 1 })
        let first = Task { try await cache.image(for: entry, size: 20) }
        let second = Task { try await cache.image(for: entry, size: 20) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(cache.requestStarts, 1); XCTAssertEqual(cache.pendingCount, 1)
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled client completed") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(cancellations, 0)
        second.cancel()
        do { _ = try await second.value; XCTFail("Cancelled client completed") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(cancellations, 1); XCTAssertEqual(cache.activeCount, 0)
        completions.first?(nil); await Task.yield()
        XCTAssertEqual(cache.activeCount, 0, "A late callback must not release a slot twice")
    }
    @MainActor func testConcurrencyAndQueueCancellationAreBounded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThumbnailQueue-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = try (0..<20).map { index in
            let url = root.appendingPathComponent("file\(index).txt"); try Data().write(to: url); return try FileEntry(url: url)
        }
        let cache = ThumbnailCache(limit: 2, start: { _, _ in }, cancel: { _ in })
        let tasks = entries.map { entry in Task { try await cache.image(for: entry, size: 20) } }
        for _ in 0..<40 { await Task.yield() }
        XCTAssertEqual(cache.requestStarts, 2); XCTAssertEqual(cache.activeCount, 2)
        for task in tasks.reversed() { task.cancel() }
        for task in tasks { _ = try? await task.value }
        XCTAssertEqual(cache.activeCount, 0); XCTAssertEqual(cache.pendingCount, 0)
    }
    @MainActor func testDrawingCutStateDoesNotReadThePasteboard() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacExplorer-test-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let clipboard = FileClipboard(pasteboard: pasteboard)
        let urls = (0..<1000).map { URL(fileURLWithPath: "/fixture/file\($0)") }
        clipboard.write(urls, cut: true); let reads = clipboard.generationReads
        for _ in 0..<30 { for url in urls { XCTAssertTrue(clipboard.isCut(url)) } }
        XCTAssertEqual(clipboard.generationReads, reads)
        pasteboard.clearContents(); clipboard.refresh()
        XCTAssertFalse(clipboard.isCut(urls[0])); XCTAssertNil(clipboard.reserveCut())
    }
}
