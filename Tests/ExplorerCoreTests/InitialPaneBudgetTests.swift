import XCTest
@testable import ExplorerCore

final class InitialPaneBudgetTests: XCTestCase {
    func testInitialWidthsFitEverySupportedWindowAndPaneConfiguration() {
        for width in stride(from: 800.0, through: 3000, by: 7) {
            for preview in [false, true] { for inspector in [false, true] {
                let plan = WorkspaceLayout(width: width, preview: preview, inspector: inspector)
                let widths = plan.initialPaneWidths(totalWidth: width, dividerThickness: 1)
                XCTAssertEqual(widths.count, plan.auxiliaryCount + 2)
                XCTAssertEqual(widths.reduce(0, +) + Double(widths.count - 1), width, accuracy: 0.01)
                XCTAssertGreaterThanOrEqual(widths[0], plan.sidebarMinimum)
                XCTAssertGreaterThanOrEqual(widths[1], plan.contentMinimum)
                for auxiliary in widths.dropFirst(2) { XCTAssertGreaterThanOrEqual(auxiliary, plan.auxiliaryMinimum) }
            } }
        }
    }
    func testDefaultInspectorLeavesRoomForFourFileColumns() {
        let widths = WorkspaceLayout(width: 1260, preview: false, inspector: true).initialPaneWidths(totalWidth: 1260, dividerThickness: 1)
        XCTAssertEqual(widths, [208, 780, 270])
    }
}
