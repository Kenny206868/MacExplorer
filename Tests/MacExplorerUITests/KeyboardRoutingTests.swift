import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

/// Real NSEvents and native first responders; no global keyboard injection.
final class KeyboardRoutingTests: XCTestCase {
    @MainActor private func event(_ key: UInt16, _ window: NSWindow, flags: NSEvent.ModifierFlags = [], text: String = "") throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1, windowNumber: window.windowNumber,
            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: key))
    }
    @MainActor func testNativeKeysRouteToActivePaneAndRespectTextAndControls() async throws {
        _ = NSApplication.shared
        let fm = FileManager.default, previous = PreferenceStore.shared.value
        let fixture = fm.temporaryDirectory.appendingPathComponent("KeyboardRouting-" + UUID().uuidString)
        try fm.createDirectory(at: fixture, withIntermediateDirectories: false)
        let entries = try (0..<30).map { index -> FileEntry in
            let url = fixture.appendingPathComponent(String(format: "Item %02d.txt", index)); try Data().write(to: url); return try FileEntry(url: url)
        }
        let root = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(fixture)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        root.dualPane = DualPaneController(primary: root)
        let dual = try XCTUnwrap(root.dualPane), other = dual.secondary
        root.current.stop(); other.current.stop(); root.current.entries = entries; other.current.entries = entries
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; root.window = window; other.window = window
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700)); window.contentView = content; window.orderFrontRegardless()
        defer {
            root.current.stop(); other.current.stop(); window.orderOut(nil); window.contentView = nil; window.close()
            PreferenceStore.shared.value = previous; AppRouter.shared.active = nil; try? fm.removeItem(at: fixture)
        }
        root.select(entries[0].url, extend: false, range: false); other.select(entries[10].url, extend: false, range: false)
        dual.focus(.primary, files: true)
        XCTAssertNil(KeyboardRouter.handle(try event(125, window)))
        XCTAssertEqual(root.current.selection, [entries[1].url])
        XCTAssertNil(KeyboardRouter.handle(try event(125, window, flags: [.shift])))
        XCTAssertEqual(root.current.selection, [entries[1].url, entries[2].url])
        XCTAssertNil(KeyboardRouter.handle(try event(125, window, flags: [.control])))
        XCTAssertEqual(root.current.focusedURL, entries[3].url)
        XCTAssertEqual(root.current.selection.count, 2)
        XCTAssertNil(KeyboardRouter.handle(try event(48, window)))
        XCTAssertTrue(AppRouter.shared.active === other)
        XCTAssertEqual(root.current.selection.count, 2)
        XCTAssertNil(KeyboardRouter.handle(try event(119, window)))
        XCTAssertEqual(other.current.selection, [entries[29].url])
        XCTAssertNil(KeyboardRouter.handle(try event(115, window, flags: [.shift])))
        XCTAssertEqual(other.current.selection.count, entries.count)
        other.fileSurfaceFocused = false
        XCTAssertNotNil(KeyboardRouter.handle(try event(125, window)), "Arrow keys on a focused control must not move files")
        XCTAssertEqual(other.current.selection.count, entries.count)
        XCTAssertNil(KeyboardRouter.handle(try event(97, window)))
        XCTAssertTrue(other.addressFocused)
        XCTAssertNil(KeyboardRouter.handle(try event(97, window))); XCTAssertTrue(other.searchFocused)
        XCTAssertNil(KeyboardRouter.handle(try event(97, window))); XCTAssertTrue(other.fileSurfaceFocused)
        let editor = NSTextView(frame: NSRect(x: 10, y: 10, width: 500, height: 80)); editor.string = "Editable address"
        content.addSubview(editor); XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertNotNil(KeyboardRouter.handle(try event(125, window)), "Text cursor keys must stay in the editor")
        XCTAssertNotNil(KeyboardRouter.handle(try event(117, window)), "Delete in an editor must not delete files")
        XCTAssertNotNil(KeyboardRouter.handle(try event(48, window)), "Tab in a text editor must not switch panes")
        XCTAssertTrue(AppRouter.shared.active === other)
        XCTAssertNil(KeyboardRouter.handle(try event(0, window, flags: [.control], text: "a")))
        XCTAssertEqual(editor.selectedRange().length, editor.string.utf16.count)
        XCTAssertTrue(OperationCenter.shared.jobs.allSatisfy(\.finished))
        other.focusFileSurface(); other.sheet = .keyboardHelp
        XCTAssertNotNil(KeyboardRouter.handle(try event(48, window)), "A sheet owns its navigation keys")
        other.sheet = nil; other.current.selection = []; other.current.focusedURL = nil; other.current.selectionAnchor = nil
        XCTAssertNil(KeyboardRouter.handle(try event(34, window, text: "I")))
        XCTAssertEqual(other.current.selection, [entries[0].url])
        other.current.typeAhead.reset(); other.fileViewportHeight = 360
        XCTAssertNil(KeyboardRouter.handle(try event(121, window)))
        XCTAssertEqual(other.current.selection, [entries[9].url])
    }
}
