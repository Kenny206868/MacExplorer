import XCTest
import AppKit
@testable import MacExplorer

final class InputHitGeometryTests: XCTestCase {
    @MainActor func testOverflowDrawingNeverExpandsInteractiveBounds() {
        let view = OverflowView(frame: NSRect(x: 0, y: 0, width: 200, height: 40)); view.clipsToBounds = false
        XCTAssertTrue(view.visibleRect.contains(NSPoint(x: 50, y: 80)))
        XCTAssertFalse(view.inputHitRect.contains(NSPoint(x: 50, y: 80)))
        XCTAssertTrue(view.inputHitRect.contains(NSPoint(x: 50, y: 20)))
        XCTAssertEqual(view.inputHitRect, view.bounds)
    }
    @MainActor func testAncestorClippingStillRestrictsInput() {
        let view = ClippedView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        XCTAssertEqual(view.inputHitRect, NSRect(x: 0, y: 10, width: 200, height: 20))
        XCTAssertFalse(view.inputHitRect.contains(NSPoint(x: 50, y: 5)))
        XCTAssertTrue(view.inputHitRect.contains(NSPoint(x: 50, y: 20)))
    }
}
@MainActor private final class OverflowView: NSView { override var visibleRect: NSRect { NSRect(x: -200, y: -200, width: 800, height: 800) } }
@MainActor private final class ClippedView: NSView { override var visibleRect: NSRect { NSRect(x: 0, y: 10, width: 200, height: 20) } }
