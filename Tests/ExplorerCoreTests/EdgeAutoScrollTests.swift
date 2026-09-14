import XCTest
import CoreGraphics
@testable import ExplorerCore

final class EdgeAutoScrollTests: XCTestCase {
    func testCenterIsStationaryAndEdgesHaveCorrectDirection() {
        let size = CGSize(width: 600, height: 400)
        XCTAssertEqual(EdgeAutoScroll.delta(pointer: CGPoint(x: 300, y: 200), viewport: size, elapsed: 1.0 / 60), .zero)
        XCTAssertEqual(EdgeAutoScroll.delta(pointer: .zero, viewport: size, elapsed: 1.0 / 60), CGPoint(x: -15, y: -15))
        XCTAssertEqual(EdgeAutoScroll.delta(pointer: CGPoint(x: 600, y: 400), viewport: size, elapsed: 1.0 / 60), CGPoint(x: 15, y: 15))
    }
    func testFrameStallsAndInvalidGeometryCannotCauseUnboundedJumps() {
        XCTAssertEqual(EdgeAutoScroll.delta(pointer: .zero, viewport: CGSize(width: 600, height: 400), elapsed: 30), CGPoint(x: -60, y: -60))
        XCTAssertEqual(EdgeAutoScroll.delta(pointer: CGPoint(x: CGFloat.nan, y: 0), viewport: CGSize(width: 600, height: 400), elapsed: 1), .zero)
        XCTAssertEqual(EdgeAutoScroll.delta(pointer: .zero, viewport: .zero, elapsed: 1), .zero)
    }
    func testScrollOriginIsClampedForEmptyAndLargeDocuments() {
        XCTAssertEqual(EdgeAutoScroll.clampedOrigin(CGPoint(x: -5, y: 9999), content: CGSize(width: 500, height: 2000), viewport: CGSize(width: 600, height: 400)), CGPoint(x: 0, y: 1600))
        XCTAssertEqual(EdgeAutoScroll.clampedOrigin(CGPoint(x: 20, y: 20), content: .zero, viewport: CGSize(width: 600, height: 400)), .zero)
    }
}
