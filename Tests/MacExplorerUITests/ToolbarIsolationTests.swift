import XCTest
import AppKit
@testable import MacExplorer

final class ToolbarIsolationTests: XCTestCase {
    @MainActor func testNonpersistentWindowsCannotShareCustomizedItems() throws {
        _ = NSApplication.shared
        let fixture = try CommanderFixture()
        let windows = (0..<2).map { _ in NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false) }
        let chromes = windows.map { window -> NativeWindowChrome in
            window.isReleasedWhenClosed = false
            let chrome = NativeWindowChrome(); chrome.persistsConfiguration = false
            chrome.attach(to: window, owner: fixture.owner); return chrome
        }
        defer { fixture.close(); windows.forEach { $0.close() } }
        let first = try XCTUnwrap(windows[0].toolbar), second = try XCTUnwrap(windows[1].toolbar)
        XCTAssertNotEqual(first.identifier, second.identifier)
        XCTAssertNotEqual(first.identifier, NativeWindowChrome.identifier)
        XCTAssertFalse(first.autosavesConfiguration); XCTAssertFalse(second.autosavesConfiguration)
        first.insertItem(withItemIdentifier: .init("operations"), at: 0)
        XCTAssertEqual(first.items.first?.itemIdentifier.rawValue, "operations")
        XCTAssertFalse(second.items.contains { $0.itemIdentifier.rawValue == "operations" })
        withExtendedLifetime(chromes) { XCTAssertEqual(windows.count, 2) }
    }
}
