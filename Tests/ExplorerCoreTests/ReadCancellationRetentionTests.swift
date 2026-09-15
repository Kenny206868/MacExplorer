import XCTest
@testable import ExplorerCore

final class ReadCancellationRetentionTests: XCTestCase {
    private final class ListingLease: @unchecked Sendable {
        let entries = [UInt8](repeating: 42, count: 1_048_576)
        let released: XCTestExpectation
        init(released: XCTestExpectation) { self.released = released }
        deinit { released.fulfill() }
    }

    func testQueuedCancellationReleasesCapturedListingBeforeBlockedIOFinishes() async throws {
        let executor = FileReadExecutor(name: "retention-test", concurrency: 1)
        let entered = expectation(description: "Blocking read entered")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let first = Task {
            try await executor.run { _ in
                entered.fulfill()
                _ = release.wait(timeout: .now() + 10)
                return 1
            }
        }
        await fulfillment(of: [entered], timeout: 3)
        let freed = expectation(description: "Cancelled read released its captured listing")
        let second = makeQueuedRead(executor, released: freed)
        let deadline = ContinuousClock.now + .seconds(3)
        while executor.outstandingReadCount < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(executor.outstandingReadCount, 2, "The read must actually be queued before cancellation")
        second.cancel()
        do { _ = try await second.value; XCTFail("Cancelled read returned a value") }
        catch { XCTAssertTrue(error is CancellationError) }
        // Do NOT unblock first until the queued capture is released. Checking
        // only continuation cancellation misses this potentially large leak.
        await fulfillment(of: [freed], timeout: 1)
        release.signal()
        let value = try await first.value
        XCTAssertEqual(value, 1)
        let next = try await executor.run { _ in 3 }
        XCTAssertEqual(next, 3, "Cancellation must not break subsequent reads")
    }

    private func makeQueuedRead(_ executor: FileReadExecutor, released: XCTestExpectation) -> Task<Int, Error> {
        let lease = ListingLease(released: released)
        return Task { try await executor.run { _ in lease.entries.count } }
    }

    func testRepeatedPreEnqueueCancellationResumesEveryCallerExactlyOnce() async throws {
        let executor = FileReadExecutor(name: "cancellation-races", concurrency: 2)
        for _ in 0..<250 {
            let task = Task {
                // Either cancellation predates continuation installation, or
                // it races operation enqueue. Both must release the caller.
                try await executor.run { cancellation in
                    try cancellation.check()
                    return 1
                }
            }
            task.cancel()
            do { _ = try await task.value }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        let result = try await executor.run { _ in 7 }
        XCTAssertEqual(result, 7)
    }
}
