import XCTest
@testable import ExplorerCore

final class WorkspaceChromeLayoutTests: XCTestCase {
    func testOneShelfReplacesTwoRowsAndTouchDoesNotShrinkTargets() {
        for width in [800.0, 1024, 1260, 1440, 1760] {
            let desktop = WorkspaceChromeLayout(width: width), touch = WorkspaceChromeLayout(width: width, touch: true)
            XCTAssertEqual(desktop.footerHeight, 38); XCTAssertEqual(desktop.paneStatusHeight, 26)
            XCTAssertEqual(touch.footerHeight, 52); XCTAssertEqual(touch.paneStatusHeight, 44)
            XCTAssertGreaterThanOrEqual(touch.titlebarHeight, 44)
            XCTAssertLessThanOrEqual(desktop.titlebarWidth, max(180, width - 760))
        }
    }
    func testResponsivePolicyBoundsAndDeterministicFallbacks() {
        XCTAssertTrue(WorkspaceChromeLayout(width: 800).compactActions)
        XCTAssertFalse(WorkspaceChromeLayout(width: 1440).compactActions)
        XCTAssertTrue(WorkspaceChromeLayout(width: 800, touch: true).iconOnlyActions)
        XCTAssertFalse(WorkspaceChromeLayout(width: 1440, touch: true).iconOnlyActions)
        XCTAssertFalse(WorkspaceChromeLayout(width: 800).titlebarShowsLocations)
        XCTAssertTrue(WorkspaceChromeLayout(width: 1440).titlebarShowsCompare)
        for width in [Double.nan, .infinity, -.infinity, -1, 0] {
            let layout = WorkspaceChromeLayout(width: width)
            XCTAssertEqual(layout.width, 0); XCTAssertEqual(layout.titlebarWidth, 180)
        }
        XCTAssertEqual(WorkspaceChromeLayout(width: .greatestFiniteMagnitude).titlebarWidth, 900)
    }
}
