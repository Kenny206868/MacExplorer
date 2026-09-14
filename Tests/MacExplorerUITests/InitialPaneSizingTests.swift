import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class InitialPaneSizingTests: XCTestCase {
    @MainActor func testNativeInitialWidthsDoNotOverrideSubsequentUserResize() throws {
        _ = NSApplication.shared
        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: 1260, height: 600))
        split.isVertical = true; split.dividerStyle = .thin
        for _ in 0..<3 { split.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 600))) }
        let anchor = InitialPaneSizingView()
        anchor.plan = WorkspaceLayout(width: 1260, preview: false, inspector: true)
        anchor.configuration = "inspector"
        split.arrangedSubviews[0].addSubview(anchor)
        anchor.applyIfNeeded()
        XCTAssertEqual(split.arrangedSubviews[0].frame.width, 208, accuracy: 1)
        XCTAssertEqual(split.arrangedSubviews[2].frame.width, 270, accuracy: 1)
        XCTAssertGreaterThan(split.arrangedSubviews[1].frame.width, 775)
        split.setPosition(245, ofDividerAt: 0)
        let resized = split.arrangedSubviews[0].frame.width
        anchor.applyIfNeeded()
        XCTAssertEqual(split.arrangedSubviews[0].frame.width, resized, accuracy: 0.1)
        anchor.configuration = "combined"
        anchor.applyIfNeeded()
        XCTAssertEqual(split.arrangedSubviews[0].frame.width, 208, accuracy: 1)
    }
}
