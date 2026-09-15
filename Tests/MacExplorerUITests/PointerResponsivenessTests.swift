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
        let original = owner.preferences.value
        owner.preferences.value.singleClickOpen = false
        defer { owner.preferences.value = original }
        let window = PointerTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; owner.window = window
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        content.autoresizesSubviews = false; window.contentView = content
        var anchors: [FileDragAnchorView] = []
        for (index, url) in urls.enumerated() {
            let anchor = FileDragAnchorView(frame: NSRect(x: 0, y: index * 60, width: 300, height: 50))
            anchor.workspace = owner; anchor.tab = owner.current; anchor.url = url
            content.addSubview(anchor); FileDragRouter.shared.register(anchor); anchors.append(anchor)
        }
        window.makeKeyAndOrderFront(nil); content.layoutSubtreeIfNeeded(); AppRouter.shared.active = owner
        defer { anchors.forEach { FileDragRouter.shared.unregister($0) }; owner.current.stop(); window.orderOut(nil); window.contentView = nil; window.close(); AppRouter.shared.active = nil }
        var sequence = 0
        func event(_ kind: NSEvent.EventType, _ index: Int, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            sequence += 1
            let point = anchors[index].convert(NSPoint(x: 100, y: 20), to: nil)
            let value = try XCTUnwrap(NSEvent.mouseEvent(with: kind, location: point, modifierFlags: flags,
                timestamp: 10 + Double(sequence) * 0.1, windowNumber: window.windowNumber, context: nil, eventNumber: sequence, clickCount: 1, pressure: 1))
            XCTAssertEqual(value.locationInWindow.x, point.x, accuracy: 0.1)
            XCTAssertEqual(value.locationInWindow.y, point.y, accuracy: 0.1)
            XCTAssertEqual(value.modifierFlags.intersection([.command, .control, .shift]), flags)
            let hits = anchors.filter { $0.visibleRect.contains($0.convert(value.locationInWindow, from: nil)) }.compactMap(\.url)
            XCTAssertEqual(hits, [urls[index]], "Each native point must target exactly its own row")
            return value
        }
        owner.tapFile(urls[0], modifiers: []); owner.tapFile(urls[1], modifiers: .command)
        XCTAssertEqual(owner.current.selection, Set(urls), "Indexed selection must toggle the requested identity")
        owner.current.selection = []; owner.current.focusedURL = nil
        _ = FileDragRouter.shared.handle(try event(.leftMouseDown, 0))
        XCTAssertEqual(owner.current.selection, [urls[0]], "Selection must not wait for mouse-up/double-click timeout")
        _ = FileDragRouter.shared.handle(try event(.leftMouseUp, 0))
        _ = FileDragRouter.shared.handle(try event(.leftMouseDown, 1, flags: .command)); XCTAssertEqual(owner.current.selection, Set(urls))
        _ = FileDragRouter.shared.handle(try event(.leftMouseUp, 1, flags: .command))
        _ = FileDragRouter.shared.handle(try event(.leftMouseDown, 0)); XCTAssertEqual(owner.current.selection, Set(urls), "A multi-file drag retains every source until mouse-up")
        _ = FileDragRouter.shared.handle(try event(.leftMouseUp, 0)); XCTAssertEqual(owner.current.selection, [urls[0]])
        let exclusion = FilePointerExclusionView(frame: anchors[1].frame)
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
