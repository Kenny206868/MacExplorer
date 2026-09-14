import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class CommandPaletteTests: XCTestCase {
    @MainActor private func owner(_ location: Location = .home) -> ExplorerWorkspace {
        _ = NSApplication.shared
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(location), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop(); return workspace
    }
    @MainActor func testSearchAndKeyboardSelectionAreDeterministic() async {
        let model = CommandPaletteModel()
        XCTAssertEqual(model.matches.count, ExplorerCommand.allCases.count)
        XCTAssertEqual(model.selection, .goToFolder)
        model.move(1); XCTAssertEqual(model.selection, .newTab)
        model.move(-100); XCTAssertEqual(model.selection, .goToFolder)
        model.query = "side by side"
        XCTAssertEqual(model.matches, [.dualPanes])
        model.move(1); XCTAssertEqual(model.selection, .dualPanes)
        model.query = "does not exist 93745"
        XCTAssertTrue(model.matches.isEmpty); XCTAssertNil(model.selection)
        model.move(1); XCTAssertNil(model.selection)
        XCTAssertEqual(Set(ExplorerCommand.allCases.map(\.spec.title)).count, ExplorerCommand.allCases.count)
    }
    @MainActor func testDisabledCommandsRemainDiscoverableWithoutExecuting() async throws {
        let w = owner(); defer { w.current.stop() }
        XCTAssertNotNil(ExplorerCommand.rename.unavailable(in: w))
        XCTAssertNotNil(ExplorerCommand.newFolder.unavailable(in: w))
        XCTAssertNotNil(ExplorerCommand.switchPane.unavailable(in: w))
        XCTAssertNil(ExplorerCommand.dualPanes.unavailable(in: w))
        XCTAssertThrowsError(try CommandInvocation(.permanentDelete, workspace: w))
        XCTAssertTrue(w.pendingDeletion.isEmpty)
        let model = CommandPaletteModel(query: "rename")
        XCTAssertTrue(model.matches.contains(.rename))
    }
    @MainActor func testOnlyActualDismissalRunsQueuedCommandAndItRunsOnce() async throws {
        let w = owner(.folder(FileManager.default.temporaryDirectory))
        defer { w.current.stop(); DeferredSheetAction.shared.cancel(for: w) }
        w.sheet = .commandPalette
        let request = try CommandInvocation(.newFolder, workspace: w)
        request.enqueue()
        XCTAssertNil(w.sheet)
        XCTAssertTrue(DeferredSheetAction.shared.didDismiss(w))
        XCTAssertEqual(w.sheet, .newFolder)
        w.sheet = nil
        XCTAssertFalse(DeferredSheetAction.shared.didDismiss(w))
    }
    @MainActor func testChangingTabsOrCancellingOwnerDropsDeferredCommand() async throws {
        let w = owner(); defer { w.tabs.forEach { $0.stop() }; DeferredSheetAction.shared.cancel(for: w) }
        w.sheet = .commandPalette
        try CommandInvocation(.details, workspace: w).enqueue()
        let tab = BrowserTab(.computer); tab.stop(); tab.options.view = .gallery
        w.tabs.append(tab); w.activeID = tab.id
        XCTAssertFalse(DeferredSheetAction.shared.didDismiss(w))
        XCTAssertEqual(w.current.options.view, .gallery)
        w.message = nil; w.sheet = .commandPalette
        try CommandInvocation(.details, workspace: w).enqueue()
        DeferredSheetAction.shared.cancel(for: w)
        XCTAssertFalse(DeferredSheetAction.shared.didDismiss(w))
        XCTAssertEqual(w.current.options.view, .gallery)
    }
    @MainActor func testChangedFileNeverReachesDeletionConfirmation() async throws {
        let manager = FileManager.default, root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let url = root.appendingPathComponent("document.txt"); try Data("original".utf8).write(to: url)
        let w = owner(.folder(root)); w.current.entries = [try FileEntry(url: url)]; w.current.selection = [w.current.entries[0].url]
        defer { w.current.stop(); DeferredSheetAction.shared.cancel(for: w) }
        w.sheet = .commandPalette; try CommandInvocation(.permanentDelete, workspace: w).enqueue()
        try Data("a newer version".utf8).write(to: url)
        XCTAssertFalse(DeferredSheetAction.shared.didDismiss(w))
        XCTAssertTrue(w.pendingDeletion.isEmpty)
        XCTAssertEqual(try String(contentsOf: url), "a newer version")
    }
    @MainActor func testPaletteShortcutDoesNotReplaceTextOrEnterAnotherModal() async throws {
        let w = owner(), window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; w.window = window; AppRouter.shared.active = w
        defer { AppRouter.shared.active = nil; w.current.stop(); window.close() }
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 40)); editor.string = "original text"
        window.contentView = editor; window.makeFirstResponder(editor)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: "P", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35))
        XCTAssertNil(KeyboardRouter.handle(event)); XCTAssertEqual(w.sheet, .commandPalette)
        XCTAssertEqual(editor.string, "original text")
        w.sheet = .newFolder
        XCTAssertNotNil(KeyboardRouter.handle(event)); XCTAssertEqual(w.sheet, .newFolder)
    }
}
