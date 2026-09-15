import XCTest
@testable import ExplorerCore

final class FileReadExecutorTests: XCTestCase {
    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        func read() -> Int { lock.lock(); defer { lock.unlock() }; return value }
    }
    func testCancellationReleasesCallerWithoutWaitingForBlockedRead() async throws {
        let executor = FileReadExecutor(name: "test-blocked", concurrency: 1)
        let entered = expectation(description: "Blocking read started"), release = DispatchSemaphore(value: 0)
        let task = Task { try await executor.run { _ in entered.fulfill(); _ = release.wait(timeout: .now() + 5); return 42 } }
        await fulfillment(of: [entered], timeout: 3); task.cancel()
        let cancelled = expectation(description: "Caller was released")
        Task {
            do { _ = try await task.value; XCTFail("Cancelled result escaped") }
            catch { XCTAssertTrue(error is CancellationError); cancelled.fulfill() }
        }
        await fulfillment(of: [cancelled], timeout: 1); release.signal()
        let result = try await executor.run { _ in 7 }; XCTAssertEqual(result, 7)
    }
    func testCancelledQueuedWorkDoesNotRunItsReadClosure() async throws {
        let executor = FileReadExecutor(name: "test-queue", concurrency: 1), count = Count()
        let entered = expectation(description: "First read started"), release = DispatchSemaphore(value: 0)
        let first = Task { try await executor.run { _ in entered.fulfill(); _ = release.wait(timeout: .now() + 5); return 1 } }
        await fulfillment(of: [entered], timeout: 3)
        let second = Task { try await executor.run { _ in count.increment(); return 2 } }
        await Task.yield(); second.cancel()
        do { _ = try await second.value; XCTFail("Cancelled request returned a value") } catch { XCTAssertTrue(error is CancellationError) }
        release.signal(); _ = try await first.value; _ = try await executor.run { _ in 3 }
        XCTAssertEqual(count.read(), 0)
    }
    func testBlockedBulkLaneCannotPreventForegroundListing() async throws {
        let entered = expectation(description: "Bulk read started"), release = DispatchSemaphore(value: 0)
        let bulk = Task { try await FileReadExecutor.bulk.run { _ in entered.fulfill(); _ = release.wait(timeout: .now() + 5); return 1 } }
        await fulfillment(of: [entered], timeout: 3); defer { release.signal() }
        let foreground = expectation(description: "Foreground completed independently")
        Task { _ = try await FileReadExecutor.browsing.run { _ in foreground.fulfill(); return true } }
        await fulfillment(of: [foreground], timeout: 1); release.signal(); _ = try await bulk.value
    }
    func testCancelledPresentationStopsComparing() throws {
        let cancellation = FileReadCancellation(); cancellation.cancel()
        XCTAssertThrowsError(try FilePresentation(entries: [], options: FolderOptions(), checkingCancellation: cancellation.check)) { XCTAssertTrue($0 is CancellationError) }
    }
}
