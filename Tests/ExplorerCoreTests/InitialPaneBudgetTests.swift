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
                let actual = plan.allocate(hasInspector: inspector, hasPreview: preview)
                XCTAssertGreaterThanOrEqual(actual.content, 350)
                XCTAssertEqual(actual.sidebar + actual.content + actual.auxiliary + actual.preview + Double(plan.auxiliaryCount + 1), width, accuracy: 0.01)
            } }
        }
    }
    func testDefaultInspectorLeavesRoomForFourFileColumns() {
        let plan = WorkspaceLayout(width: 1260, preview: false, inspector: true)
        XCTAssertEqual(plan.initialPaneWidths(totalWidth: 1260, dividerThickness: 1), [211, 793, 254])
        let actual = plan.allocate(hasInspector: true, hasPreview: false)
        XCTAssertEqual(actual.sidebar, 211); XCTAssertEqual(actual.auxiliary, 254); XCTAssertEqual(actual.content, 793)
    }
}
