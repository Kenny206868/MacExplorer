import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class TerminalShortcutTests: XCTestCase {
    @MainActor func testCapturedTerminalFoldersAreNotShellCodeAndDoNotFollowNavigation() async throws {
        let manager = FileManager.default, root = manager.temporaryDirectory.appendingPathComponent("Terminal-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let left = root.appendingPathComponent("Left $(not a command)"), right = root.appendingPathComponent("Right 'quotes' 日本語")
        for folder in [left, right] { try manager.createDirectory(at: folder, withIntermediateDirectories: true) }
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(left)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop(); owner.dualPane = DualPaneController(primary: owner)
        let dual = try XCTUnwrap(owner.dualPane)
        dual.secondary.current.navigate(.folder(right)); dual.secondary.current.stop()
        defer { owner.tabs.forEach { $0.stop() }; dual.secondary.tabs.forEach { $0.stop() }; AppRouter.shared.active = nil }
        let request = try TerminalRequest.capture(dual.secondary, scope: .both)
        XCTAssertEqual(request.folders.map(\.path), [right.path, left.path])
        var actual: [URL] = []
        let launcher = TerminalLauncher(launch: { actual = $0 })
        dual.secondary.current.navigate(.home); dual.secondary.current.stop()
        try await launcher.perform(request)
        XCTAssertEqual(actual.map(\.path), [right.path, left.path], "The launch must use the captured URLs, not a later pane location")
        XCTAssertEqual(try TerminalRequest(folders: [left, left]).folders.count, 1)
        owner.current.navigate(.archive(root.appendingPathComponent("source.zip"), folder: "member")); owner.current.stop()
        XCTAssertEqual(try TerminalRequest.capture(owner, scope: .active).folders.first?.path, root.path)
        let file = root.appendingPathComponent("not a folder"); try Data().write(to: file)
        do { try await launcher.perform(TerminalRequest(folders: [file])); XCTFail("A regular file must never be launched as a working directory") }
        catch { XCTAssertEqual(actual.map(\.path), [right.path, left.path]) }
    }
    @MainActor func testNativeTerminalHotkeyHonorsModalScopeAndSuppressesKeyRepeat() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TerminalHotkey-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop()
        let window = TerminalTestWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; owner.window = window; window.makeKeyAndOrderFront(nil); AppRouter.shared.active = owner
        defer { owner.current.stop(); window.orderOut(nil); window.close(); AppRouter.shared.active = nil }
        let launched = expectation(description: "Captured working folder delivered")
        var calls = 0
        let launcher = TerminalLauncher(launch: { folders in calls += 1; XCTAssertEqual(folders.first?.path, root.path); launched.fulfill() })
        func key(_ flags: NSEvent.ModifierFlags, repeated: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: repeated, keyCode: 36))
        }
        let event = try key([.command, .option])
        owner.sheet = .properties; XCTAssertNotNil(KeyboardRouter.handle(event, terminalLauncher: launcher)); owner.sheet = nil
        XCTAssertNotNil(KeyboardRouter.handle(try key([.control, .option]), terminalLauncher: launcher))
        XCTAssertNil(KeyboardRouter.handle(event, terminalLauncher: launcher))
        XCTAssertNil(KeyboardRouter.handle(try key([.command, .option], repeated: true), terminalLauncher: launcher))
        await fulfillment(of: [launched], timeout: 3); XCTAssertEqual(calls, 1)
    }
}
@MainActor private final class TerminalTestWindow: NSWindow { override var canBecomeKey: Bool { true } }
