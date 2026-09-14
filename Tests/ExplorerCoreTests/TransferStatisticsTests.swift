import XCTest
@testable import ExplorerCore

final class TransferStatisticsTests: XCTestCase {
    func testRateAndETAUseActualSamples() throws {
        var value = TransferStatistics()
        value.record(bytes: 0, at: 0); value.record(bytes: 1000, at: 1)
        XCTAssertEqual(try XCTUnwrap(value.bytesPerSecond), 1000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(value.secondsRemaining(totalBytes: 3000, completedBytes: 1000)), 2, accuracy: 0.001)
        XCTAssertNil(value.secondsRemaining(totalBytes: nil, completedBytes: 1000))
    }
    func testPauseDoesNotBecomeTransferTime() throws {
        var value = TransferStatistics()
        value.record(bytes: 0, at: 0); value.record(bytes: 1000, at: 1)
        value.suspend(); value.record(bytes: 1000, at: 50)
        XCTAssertNil(value.bytesPerSecond)
        value.record(bytes: 2000, at: 51)
        XCTAssertEqual(try XCTUnwrap(value.bytesPerSecond), 1000, accuracy: 0.001)
    }
    func testOutOfOrderAndNonFiniteSamplesDoNotRegressCounters() {
        var value = TransferStatistics()
        value.record(bytes: 1000, at: 10); value.record(bytes: 2000, at: 11)
        value.record(bytes: 100, at: 2); value.record(bytes: 9999, at: .nan)
        XCTAssertEqual(value.bytes, 2000)
    }
    func testHistoryIsBoundedAndZeroRateHasNoETA() {
        var value = TransferStatistics()
        for second in 0...500 { value.record(bytes: 0, at: Double(second)) }
        XCTAssertEqual(value.samples.count, 120)
        XCTAssertNil(value.secondsRemaining(totalBytes: 500, completedBytes: 0))
    }
}
