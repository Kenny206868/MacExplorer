import XCTest
@testable import ExplorerCore

final class DualPaneLayoutTests: XCTestCase {
    func testPaneBudgetsAndFallbackAcrossWidthsAndRatios() {
        for width in stride(from: 350.0, through: 2400, by: 7) {
            for ratio in [-4.0, 0.2, 0.5, 0.8, 99, .nan] {
                for preferred in PaneOrientation.allCases {
                    let layout = DualPaneLayout(width: width, height: 600, preferred: preferred, ratio: ratio)
                    let stacked = preferred == .stacked || width < 760
                    XCTAssertEqual(layout.orientation, stacked ? .stacked : .sideBySide)
                    XCTAssertEqual(layout.first + layout.second + layout.divider, stacked ? 600 : width, accuracy: 0.001)
                    XCTAssertGreaterThanOrEqual(layout.first, stacked ? 160 : 320)
                    XCTAssertGreaterThanOrEqual(layout.second, stacked ? 160 : 320)
                }
            }
        }
    }
    func testInvalidAndTinyViewportsStayFinite() {
        for value in [Double.nan, .infinity, -1, 0, 2] {
            let layout = DualPaneLayout(width: value, height: value, preferred: .sideBySide, ratio: value)
            XCTAssertTrue(layout.first.isFinite && layout.second.isFinite)
            XCTAssertGreaterThanOrEqual(layout.first, 0); XCTAssertGreaterThanOrEqual(layout.second, 0)
        }
    }
    func testNarrowFallbackDoesNotMutateIntent() {
        let geometry = PaneGeometry(ratio: 0.65)
        XCTAssertEqual(DualPaneLayout(width: 500, height: 600, preferred: geometry.orientation, ratio: geometry.ratio).orientation, .stacked)
        XCTAssertEqual(DualPaneLayout(width: 1200, height: 600, preferred: geometry.orientation, ratio: geometry.ratio).orientation, .sideBySide)
        XCTAssertEqual(geometry.ratio, 0.65)
    }
}
