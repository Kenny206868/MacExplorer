import XCTest
@testable import ExplorerCore

final class GridNavigationTests: XCTestCase {
    func testPartialRowsAndEmptyGroups() {
        XCTAssertEqual(GridNavigation.verticalNeighbor(of: 2, counts: [4, 0, 5], columns: 3, direction: 1), 3)
        XCTAssertEqual(GridNavigation.verticalNeighbor(of: 3, counts: [4, 0, 5], columns: 3, direction: 1), 4)
        XCTAssertEqual(GridNavigation.verticalNeighbor(of: 5, counts: [4, 0, 5], columns: 3, direction: -1), 3)
        XCTAssertEqual(GridNavigation.verticalNeighbor(of: 6, counts: [4, 0, 5], columns: 3, direction: 1), 8)
        XCTAssertEqual(GridNavigation.verticalNeighbor(of: 0, counts: [4], columns: 3, direction: -1), 0)
        XCTAssertEqual(GridNavigation.verticalNeighbor(of: 3, counts: [4], columns: 3, direction: 1), 3)
    }
    func testFullRowsRetainColumn() {
        XCTAssertEqual(GridNavigation.verticalNeighbor(of: 2, counts: [6, 6], columns: 3, direction: 1), 5)
        XCTAssertEqual(GridNavigation.verticalNeighbor(of: 5, counts: [6, 6], columns: 3, direction: 1), 8)
        XCTAssertEqual(GridNavigation.verticalNeighbor(of: 8, counts: [6, 6], columns: 3, direction: -1), 5)
    }
    func testInvalidAndOverflowingCounts() {
        XCTAssertNil(GridNavigation.verticalNeighbor(of: 1, counts: [], columns: 3, direction: 1))
        XCTAssertNil(GridNavigation.verticalNeighbor(of: 1, counts: [-2], columns: 3, direction: 1))
        XCTAssertNil(GridNavigation.verticalNeighbor(of: 1, counts: [3], columns: 0, direction: 1))
        XCTAssertNil(GridNavigation.verticalNeighbor(of: 1, counts: [.max, 1], columns: 3, direction: 1))
    }
}
