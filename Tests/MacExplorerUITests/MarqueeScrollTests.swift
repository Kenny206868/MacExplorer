import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class MarqueeScrollTests: XCTestCase {
    @MainActor func testNativeScrollStepUpdatesDocumentPointWithoutGlobalInput() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let document = MarqueeScrollAnchor(frame: NSRect(x: 0, y: 0, width: 600, height: 2000))
        scroll.documentView = document; window.contentView = scroll
        let controller = MarqueeAutoScroller(); controller.attach(document)
        defer { controller.stop(); window.contentView = nil; window.close() }
        scroll.layoutSubtreeIfNeeded()
        let start = scroll.contentView.bounds.origin
        let point = document.convert(CGPoint(x: 300, y: 399), to: nil)
        let moved = controller.step(pointerInWindow: point, elapsed: 1.0 / 60)
        XCTAssertNotNil(moved)
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, start.y)
        XCTAssertGreaterThan(moved?.y ?? 0, 399)
        for _ in 0..<500 { _ = controller.step(pointerInWindow: point, elapsed: 1.0 / 60) }
        XCTAssertLessThanOrEqual(scroll.contentView.bounds.maxY, document.bounds.maxY + 0.1)
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 0)
    }
}
