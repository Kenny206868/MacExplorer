import XCTest
import CoreGraphics
@testable import ExplorerCore
final class GridGeometryTests: XCTestCase {
    func testHitTestingRespectsGapsAndHeaders() throws {
        let g = ExplorerGridGeometry(counts: [5, 4], width: 500, minimumWidth: 125, cellHeight: 143, headers: true)
        XCTAssertEqual(g.columns, 3)
        let first = try XCTUnwrap(g.rect(for: 0))
        XCTAssertEqual(g.index(at: CGPoint(x: first.midX, y: first.midY)), 0)
        XCTAssertNil(g.index(at: CGPoint(x: first.maxX + 2, y: first.midY)))
        XCTAssertNil(g.index(at: CGPoint(x: first.midX, y: first.minY - 5)))
        XCTAssertEqual(g.indices(intersecting: CGRect(x: 0, y: 0, width: 500, height: g.height)), Array(0..<9))
    }
    func testVirtualizedCellsRemainSelectable() throws {
        let g = ExplorerGridGeometry(counts: [100_000], width: 700, minimumWidth: 120, cellHeight: 140, headers: false)
        let cell = try XCTUnwrap(g.rect(for: 90_000))
        XCTAssertEqual(g.indices(intersecting: cell.insetBy(dx: 2, dy: 2)), [90_000])
        XCTAssertNil(g.rect(for: 100_000))
    }
    func testNarrowAndEmptyLayouts() {
        let g = ExplorerGridGeometry(counts: [0], width: 0, minimumWidth: 125, cellHeight: 140, headers: false)
        XCTAssertEqual(g.columns, 1); XCTAssertNil(g.index(at: .zero))
        XCTAssertTrue(g.indices(intersecting: .null).isEmpty)
    }
}
