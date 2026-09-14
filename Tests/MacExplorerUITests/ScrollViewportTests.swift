import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class ScrollViewportTests: XCTestCase {
    @MainActor func testNativeScrollerGutterIsBudgetedInsteadOfClippingLastColumn() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 320), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 320))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = false
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 1200))
        scroll.documentView = document; window.contentView = scroll
        let probe = ScrollViewportMetricView(frame: document.bounds)
        document.addSubview(probe)
        var received: CGFloat?
        probe.changed = { received = $0 }; window.orderFrontRegardless()
        defer { probe.invalidate(); window.orderOut(nil); window.contentView = nil; window.close() }
        for style in [NSScroller.Style.legacy, .overlay, .legacy] {
            scroll.scrollerStyle = style; scroll.tile(); scroll.layoutSubtreeIfNeeded(); probe.observeViewport()
            try await Task.sleep(for: .milliseconds(100))
            let measured = try XCTUnwrap(received)
            XCTAssertEqual(measured, scroll.bounds.width - scroll.contentSize.width, accuracy: 0.5)
            let widths = DetailsColumns().widths(available: scroll.bounds.width - measured)
            XCTAssertLessThanOrEqual(widths.reduce(0, +), scroll.contentSize.width + 0.5)
            if style == .legacy { XCTAssertGreaterThan(measured, 5) }
        }
    }
}
