import XCTest
@testable import ExplorerCore

final class DetailsRowGeometryTests: XCTestCase {
    func testHeaderGapsAndCollapsedGroupsAreExcluded() {
        let rows = DetailsRowGeometry(counts: [2, 0, 3], headings: [true, true, true], rowHeight: 36, headerHeight: 34)
        XCTAssertNil(rows.index(at: 20)); XCTAssertNil(rows.index(at: 40))
        XCTAssertEqual(rows.index(at: 68), 0)
        XCTAssertEqual(rows.indices(from: 68, through: 140), [0, 1])
        XCTAssertEqual(rows.indices(from: 140, through: 208), [])
        XCTAssertEqual(rows.indices(from: 208, through: 316), [2, 3, 4])
        XCTAssertEqual(rows.indices(from: 999, through: -10), [0, 1, 2, 3, 4])
    }
    func testInvalidMeasurementsNeverProduceInvalidIndices() {
        let rows = DetailsRowGeometry(counts: [-1, 2], headings: [], rowHeight: .nan, headerHeight: .infinity)
        XCTAssertEqual(rows.height, 106)
        XCTAssertNil(rows.index(at: .nan)); XCTAssertNil(rows.index(at: -100))
        XCTAssertEqual(rows.indices(from: .infinity, through: 4), [])
    }
}
