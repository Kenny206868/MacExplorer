import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class PathShortcutTests: XCTestCase {
    @MainActor func testRepeatedPathCommandsReselectTheNativeFieldWithoutLosingDraft() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PathKeys-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop()
        let model = PathEditorModel(complete: { _, _, _, _ in PathSuggestions() })
        let host = NSHostingView(rootView: LocationPathControl(workspace: owner, tab: owner.current, editor: model).frame(width: 620).padding(10))
        let window = PathShortcutWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; owner.window = window; window.contentView = host
        window.makeKeyAndOrderFront(nil); AppRouter.shared.active = owner
        defer { model.cancel(); owner.current.stop(); window.orderOut(nil); window.contentView = nil; window.close(); AppRouter.shared.active = nil; try? FileManager.default.removeItem(at: root) }
        host.layoutSubtreeIfNeeded()
        XCTAssertNil(KeyboardRouter.handle(try key(37, "l", flags: .command, window: window)))
        try await settle { self.pathField(host)?.currentEditor() is NSTextView }
        let field = try XCTUnwrap(pathField(host)), editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        model.change(root.path + "/Draft 日本語")
        try await settle { field.stringValue == model.text && !model.completing }
        let draft = model.text
        for flags: NSEvent.ModifierFlags in [.command, .control] {
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            XCTAssertNil(KeyboardRouter.handle(try key(37, "l", flags: flags, window: window)))
            try await settle { editor.selectedRange() == NSRange(location: 0, length: (draft as NSString).length) }
            XCTAssertEqual(model.text, draft, "Reselecting must preserve the user's uncommitted draft")
        }
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        ExplorerCommand.goToFolder.perform(in: owner)
        try await settle { editor.selectedRange().length == (draft as NSString).length }
        let version = model.focusVersion
        XCTAssertNil(KeyboardRouter.handle(try key(37, "l", flags: .command, window: window, repeated: true)))
        XCTAssertEqual(model.focusVersion, version, "Key-repeat must not continuously reset the editor")
        owner.sheet = .properties
        XCTAssertNotNil(KeyboardRouter.handle(try key(37, "l", flags: .command, window: window)))
        XCTAssertEqual(model.focusVersion, version)
        owner.sheet = nil
    }

    @MainActor func testMarkedTextRetainsEscapePathAndPaneCommands() throws {
        _ = NSApplication.shared
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.home), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop(); owner.addressFocused = true
        let window = PathShortcutWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; owner.window = window
        let editor = MarkedPathTestEditor(frame: NSRect(x: 0, y: 0, width: 400, height: 200)); window.contentView = editor
        window.makeKeyAndOrderFront(nil); XCTAssertTrue(window.makeFirstResponder(editor)); AppRouter.shared.active = owner
        defer { owner.current.stop(); window.orderOut(nil); window.contentView = nil; window.close(); AppRouter.shared.active = nil }
        for (code, text, flags): (UInt16, String, NSEvent.ModifierFlags) in [(53, "", []), (37, "l", .command), (48, "\t", .control), (36, "\r", [.command, .option])] {
            XCTAssertNotNil(KeyboardRouter.handle(try key(code, text, flags: flags, window: window)), "Marked text must own this input")
        }
        XCTAssertTrue(owner.addressFocused)
        XCTAssertNil(owner.sheet)
    }

    @MainActor func testDeferredBothPaneTerminalCommandRejectsChangedOtherLocation() throws {
        _ = NSApplication.shared
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.home), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop(); owner.dualPane = DualPaneController(primary: owner)
        let panes = try XCTUnwrap(owner.dualPane)
        panes.secondary.current.stop(); panes.focus(.primary)
        defer { owner.current.stop(); panes.secondary.current.stop(); AppRouter.shared.active = nil }
        XCTAssertNil(ExplorerCommand.terminalBoth.unavailable(in: owner))
        let invocation = try CommandInvocation(.terminalBoth, workspace: owner)
        panes.secondary.current.history.navigate(.folder(FileManager.default.temporaryDirectory))
        XCTAssertNil(ExplorerCommand.terminalBoth.unavailable(in: owner), "Both locations are still valid terminal targets")
        XCTAssertThrowsError(try invocation.validate(), "A deferred command must not silently adopt the other pane's new folder")
    }

    @MainActor private func key(_ code: UInt16, _ text: String, flags: NSEvent.ModifierFlags, window: NSWindow, repeated: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1, windowNumber: window.windowNumber,
            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: repeated, keyCode: code))
    }
    @MainActor private func pathField(_ view: NSView) -> PathTextField? {
        if let field = view as? PathTextField { return field }
        return view.subviews.lazy.compactMap { self.pathField($0) }.first
    }
    @MainActor private func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Native path focus did not settle")
    }
}
@MainActor private final class PathShortcutWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor private final class MarkedPathTestEditor: NSTextView { override func hasMarkedText() -> Bool { true } }
