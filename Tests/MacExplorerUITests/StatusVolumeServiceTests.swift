import XCTest
import ExplorerCore
@testable import MacExplorer

final class StatusVolumeServiceTests: XCTestCase {
    func testTwoObserversShareAReadAndCancellingOneDoesNotCancelTheOther() async throws {
        let gate = DispatchSemaphore(value: 0), entered = expectation(description: "storage reader started")
        let count = VolumeReadCounter()
        let service = StatusVolumeService(lifetime: 60) { _, cancellation in
            count.increment(); entered.fulfill(); gate.wait(); try cancellation.check()
            return StatusVolume(name: "Test", available: 200, total: 500, format: "APFS", readOnly: false)
        }
        let url = URL(fileURLWithPath: "/tmp")
        let first = Task { try await service.read(url) }, second = Task { try await service.read(url) }
        defer { gate.signal(); first.cancel(); second.cancel() }
        await fulfillment(of: [entered], timeout: 3)
        let deadline = ContinuousClock.now + .seconds(3)
        while await service.inFlightObservers != 2, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let observers = await service.inFlightObservers; XCTAssertEqual(observers, 2)
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled observer must be resumed with cancellation") } catch is CancellationError { }
        gate.signal(); let result = try await second.value
        XCTAssertEqual(result?.available, 200); XCTAssertEqual(count.value, 1)
        let cached = try await service.read(url); XCTAssertEqual(cached?.name, "Test"); XCTAssertEqual(count.value, 1)
    }
    func testRevisionInvalidatesAndCacheIsBoundedIncludingUnavailableVolumes() async throws {
        let count = VolumeReadCounter()
        let service = StatusVolumeService(lifetime: 60) { _, _ in count.increment(); return nil }
        let url = URL(fileURLWithPath: "/tmp")
        _ = try await service.read(url); _ = try await service.read(url)
        XCTAssertEqual(count.value, 1, "Unavailable storage is also cached briefly")
        _ = try await service.read(url, revision: 1); XCTAssertEqual(count.value, 2)
        for index in 0..<40 { _ = try await service.read(url.appendingPathComponent(String(index))) }
        let cached = await service.cachedLocations; XCTAssertEqual(cached, 32)
    }
}
private final class VolumeReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
    func increment() { lock.lock(); storage += 1; lock.unlock() }
}
