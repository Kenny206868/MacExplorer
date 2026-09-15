import XCTest
import Foundation
@testable import ExplorerCore

final class GridRangeGeometryTests: XCTestCase {
    func testCompressedRangesMatchBruteForceCellIntersections() throws {
        let counts = [0, 7, 0, 9, 2, 0, 23, 0], total = counts.reduce(0, +)
        var random: UInt64 = 0xE9A4F712
        func next(_ maximum: Int) -> CGFloat {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Int(random >> 32) % maximum)
        }
        for width: CGFloat in [200, 500, 900] {
            for headers in [false, true] {
                let layout = ExplorerGridGeometry(counts: counts, width: width, minimumWidth: 100, cellHeight: 70, headers: headers)
                let cells = try (0..<total).map { try XCTUnwrap(layout.rect(for: $0)) }
                for _ in 0..<500 {
                    let rectangle = CGRect(x: next(1100) - 100, y: next(Int(layout.height) + 300) - 100,
                                           width: next(600) - 80, height: next(600) - 80)
                    let expected = cells.indices.filter {
                        let intersection = cells[$0].intersection(rectangle.standardized)
                        return !intersection.isNull && !intersection.isEmpty
                    }
                    XCTAssertEqual(Array(layout.indexSet(intersecting: rectangle)), expected)
                }
                for (index, cell) in cells.enumerated() {
                    XCTAssertEqual(layout.index(at: CGPoint(x: cell.midX, y: cell.midY)), index)
                    XCTAssertNil(layout.index(at: CGPoint(x: cell.maxX, y: cell.midY)), "Right edges belong to the gap, not this cell")
                    XCTAssertNil(layout.index(at: CGPoint(x: cell.midX, y: cell.maxY)), "Bottom edges belong to the gap")
                }
            }
        }
    }
    func testMillionCellFullWidthMarqueeUsesOneRange() {
        let layout = ExplorerGridGeometry(counts: [1_000_000], width: 1200, minimumWidth: 100, cellHeight: 100, headers: false)
        let indices = layout.indexSet(intersecting: CGRect(x: 0, y: 0, width: 1200, height: layout.height))
        XCTAssertEqual(indices.count, 1_000_000)
        XCTAssertEqual(indices.rangeView.count, 1)
    }
    func testInvalidAndOverflowingMeasurementsRemainFinite() {
        for invalid in [CGFloat.nan, .infinity, -.infinity, -.greatestFiniteMagnitude, .greatestFiniteMagnitude] {
            let layout = ExplorerGridGeometry(counts: [Int.max, 100, -100], width: invalid, minimumWidth: invalid,
                                              cellHeight: invalid, headers: true, inset: invalid, gap: invalid, rowGap: invalid)
            XCTAssertTrue(layout.height.isFinite)
            XCTAssertTrue(layout.cellWidth.isFinite)
            XCTAssertTrue(layout.cellHeight.isFinite)
            XCTAssertGreaterThanOrEqual(layout.columns, 1)
            XCTAssertLessThanOrEqual(layout.columns, 4096)
            XCTAssertNotNil(layout.rect(for: 0))
            XCTAssertNil(layout.rect(for: Int.max))
            XCTAssertNil(layout.index(at: CGPoint(x: CGFloat.nan, y: 0)))
            XCTAssertTrue(layout.indexSet(intersecting: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)).isEmpty)
        }
    }
    func testDetailsRangesAgreeWithCompatibilityArray() {
        let layout = DetailsRowGeometry(counts: [7, 0, 9], headings: [true, true, true], rowHeight: 32, headerHeight: 34)
        for y in stride(from: -100.0, to: layout.height + 100, by: 7) {
            let set = layout.indexSet(from: y, through: y + 81)
            XCTAssertEqual(Array(set), layout.indices(from: y, through: y + 81))
            XCTAssertTrue(set.allSatisfy { (0..<16).contains($0) })
        }
    }
}
