import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class PointerResponsivenessTests: XCTestCase {
    @MainActor func testMouseDownSelectsImmediatelyAndMouseUpPreservesDragSemantics() async throws {
        _ = NSApplication.shared
        let fm = FileManager.default, folder = fm.temporaryDirectory.appendingPathComponent("PointerInput-" + UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let urls = [folder.appendingPathComponent("a.txt"), folder.appendingPathComponent("b.txt")]
        for url in urls { try Data().write(to: url) }
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(folder)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop(); owner.current.entries = try urls.map { try FileEntry(url: $0) }
        let window = PointerTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; owner.window = window
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 160)); window.contentView = content
        var anchors: [FileDragAnchorView] = []
        for (index, url) in urls.enumerated() {
            let anchor = FileDragAnchorView(frame: NSRect(x: 0, y: index * 60, width: 300, height: 50))
            anchor.workspace = owner; anchor.tab = owner.current; anchor.url = url
            content.addSubview(anchor); FileDragRouter.shared.register(anchor); anchors.append(anchor)
        }
        window.makeKeyAndOrderFront(nil); AppRouter.shared.active = owner
        defer { anchors.forEach { FileDragRouter.shared.unregister($0) }; owner.current.stop(); window.orderOut(nil); window.contentView = nil; window.close(); AppRouter.shared.active = nil }
        func event(_ kind: NSEvent.EventType, _ index: Int, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: kind, location: NSPoint(x: 100, y: index * 60 + 20), modifierFlags: flags,
                timestamp: kind == .leftMouseDown ? 10 : 10.1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        _ = FileDragRouter.shared.handle(try event(.leftMouseDown, 0))
        XCTAssertEqual(owner.current.selection, [urls[0]], "Selection must not wait for mouse-up/double-click timeout")
        _ = FileDragRouter.shared.handle(try event(.leftMouseUp, 0))
        _ = FileDragRouter.shared.handle(try event(.leftMouseDown, 1, flags: .command)); XCTAssertEqual(owner.current.selection, Set(urls))
        _ = FileDragRouter.shared.handle(try event(.leftMouseUp, 1, flags: .command))
        _ = FileDragRouter.shared.handle(try event(.leftMouseDown, 0)); XCTAssertEqual(owner.current.selection, Set(urls), "A multi-file drag retains every source until mouse-up")
        _ = FileDragRouter.shared.handle(try event(.leftMouseUp, 0)); XCTAssertEqual(owner.current.selection, [urls[0]])
        let exclusion = FilePointerExclusionView(frame: NSRect(x: 80, y: 60, width: 40, height: 40))
        content.addSubview(exclusion); FileDragRouter.shared.exclude(exclusion)
        defer { FileDragRouter.shared.removeExclusion(exclusion) }
        _ = FileDragRouter.shared.handle(try event(.leftMouseDown, 1))
        XCTAssertEqual(owner.current.selection, [urls[0]], "Checkbox bounds own their input")
    }
}
@MainActor private final class PointerTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
