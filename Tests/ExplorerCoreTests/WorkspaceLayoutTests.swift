import XCTest
@testable import ExplorerCore

final class WorkspaceLayoutTests: XCTestCase {
    func testEverySupportedWidthFitsRequestedPanes() {
        for width in stride(from: 800.0, through: 3000.0, by: 1) {
            for preview in [false, true] {
                for inspector in [false, true] {
                    let layout = WorkspaceLayout(width: width, preview: preview, inspector: inspector)
                    XCTAssertLessThanOrEqual(layout.requiredMinimum, width)
                    XCTAssertGreaterThanOrEqual(layout.contentMinimum, 350)
                }
            }
        }
    }
    func testBothPanesBecomeTabsAtNarrowWidthsWithoutLosingIntent() {
        XCTAssertTrue(WorkspaceLayout(width: 800, preview: true, inspector: true).combinesAuxiliaryPanes)
        XCTAssertEqual(WorkspaceLayout(width: 800, preview: true, inspector: true).auxiliaryCount, 1)
        XCTAssertFalse(WorkspaceLayout(width: 1600, preview: true, inspector: true).combinesAuxiliaryPanes)
        XCTAssertEqual(WorkspaceLayout(width: 1600, preview: true, inspector: true).auxiliaryCount, 2)
        XCTAssertEqual(WorkspaceLayout(width: 800, preview: false, inspector: false).auxiliaryCount, 0)
    }
    func testUnusableMeasurementsAndSearchBudget() {
        XCTAssertEqual(WorkspaceLayout(width: .nan, preview: false, inspector: false).width, 800)
        XCTAssertEqual(WorkspaceLayout(width: -.infinity, preview: false, inspector: false).width, 800)
        XCTAssertEqual(WorkspaceLayout(width: -1, preview: false, inspector: false).width, 0)
        XCTAssertEqual(WorkspaceLayout(width: 800, preview: false, inspector: false).searchWidth, 184)
    }
}
