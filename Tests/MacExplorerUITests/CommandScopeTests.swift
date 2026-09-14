import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class CommandScopeTests: XCTestCase {
    @MainActor private func workspace() -> ExplorerWorkspace {
        let value = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.home), options: FolderOptions(), query: "", allLocations: false, selection: []))
        value.current.stop(); return value
    }
    @MainActor func testAllModalStatesBlockMenuAndKeyboardFileCommandsInBothPanes() async throws {
        _ = NSApplication.shared
        let root = workspace(); root.dualPane = DualPaneController(primary: root)
        let secondary = try XCTUnwrap(root.dualPane?.secondary); secondary.current.stop()
        defer { root.tabs.forEach { $0.stop() }; secondary.tabs.forEach { $0.stop() }; AppRouter.shared.active = nil }
        XCTAssertTrue(WorkspaceCommandScope.target(root) === root)
        root.dualPane?.focus(.secondary)
        XCTAssertTrue(WorkspaceCommandScope.target(root) === secondary)
        for source in [root, secondary] {
            source.sheet = .properties
            XCTAssertNil(WorkspaceCommandScope.target(root)); XCTAssertNil(WorkspaceCommandScope.target(secondary))
            var invoked = false
            XCTAssertFalse(WorkspaceCommandScope.perform(on: root) { _ in invoked = true })
            XCTAssertFalse(invoked)
            source.sheet = nil; source.message = MessageBox(title: "Blocked", message: "Dialog")
            XCTAssertNil(WorkspaceCommandScope.target(root)); source.message = nil
            source.pendingDeletion = [URL(fileURLWithPath: "/unmodified")]
            XCTAssertNil(WorkspaceCommandScope.target(secondary)); source.pendingDeletion = []
        }
        XCTAssertNotNil(WorkspaceCommandScope.target(root))
    }
    @MainActor func testVoiceOverModifierAndFocusedControlKeysPassThrough() async throws {
        _ = NSApplication.shared
        let root = workspace()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; root.window = window; window.makeKeyAndOrderFront(nil); AppRouter.shared.active = root
        defer { root.current.stop(); window.orderOut(nil); window.close(); AppRouter.shared.active = nil }
        func key(_ code: UInt16, _ text: String, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
        }
        for text in ["c", "m", "a", "d"] {
            let event = try key(0, text, [.control, .option])
            XCTAssertTrue(KeyboardRouter.handle(event) === event)
        }
        root.fileSurfaceFocused = false
        XCTAssertNotNil(KeyboardRouter.handle(try key(125, "", [.control])))
        XCTAssertNotNil(KeyboardRouter.handle(try key(49, " ", [.control])))
        XCTAssertTrue(root.current.selection.isEmpty)
    }
}
