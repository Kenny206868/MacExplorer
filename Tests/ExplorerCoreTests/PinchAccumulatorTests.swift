import XCTest
@testable import ExplorerCore

final class PinchAccumulatorTests: XCTestCase {
    func testNoiseAccumulatesOnlyWithinOnePaneAndGesture() {
        var pinch = PinchAccumulator(); let first = UUID(), second = UUID()
        XCTAssertEqual(pinch.consume(0.10, owner: first), 0)
        XCTAssertEqual(pinch.consume(0.10, owner: second), 0)
        XCTAssertEqual(pinch.consume(0.09, owner: second), 1)
        XCTAssertEqual(pinch.consume(-0.10, owner: first), 0)
        XCTAssertEqual(pinch.consume(-0.10, owner: first), -1)
        XCTAssertEqual(pinch.consume(0.15, owner: first), 0)
        XCTAssertEqual(pinch.consume(0.1, owner: first, began: true), 0)
        XCTAssertEqual(pinch.consume(0, owner: first, ended: true), 0)
        XCTAssertEqual(pinch.consume(0.1, owner: first), 0)
    }
    func testCancellationAndNonfiniteInputNeverZoom() {
        var pinch = PinchAccumulator(); let owner = UUID()
        XCTAssertEqual(pinch.consume(0.17, owner: owner), 0)
        XCTAssertEqual(pinch.consume(1, owner: owner, cancelled: true), 0)
        XCTAssertEqual(pinch.consume(0.02, owner: owner), 0)
        XCTAssertEqual(pinch.consume(.nan, owner: owner), 0)
        XCTAssertEqual(pinch.consume(.infinity, owner: owner), 0)
        XCTAssertEqual(pinch.consume(1000, owner: owner), 1)
        XCTAssertEqual(pinch.consume(-1000, owner: owner), -1)
    }
}
