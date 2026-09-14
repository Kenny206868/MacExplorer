import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class InlineFilenameTests: XCTestCase {
    @MainActor func testNativeEditorSelectsBaseNameAndCancellationDoesNotTouchFiles() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InlineRename-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("Zażółć 🧪.txt"); try Data("original".utf8).write(to: file)
        let entry = try FileEntry(url: file), preferences = PreferenceStore.shared.value
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop(); workspace.current.entries = [entry]; workspace.current.selection = [file]
        let coordinator = FilenameEditorRegistry.shared.editor(for: workspace.current)
        try coordinator.begin(entry, in: workspace)
        let session = try XCTUnwrap(coordinator.session)
        let host = NSHostingView(rootView: InlineFilenameField(session: session).frame(width: 260, height: 30))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { coordinator.cancel(); workspace.current.stop(); window.contentView = nil; window.close(); PreferenceStore.shared.value = preferences; try? FileManager.default.removeItem(at: root) }
        try await Task.sleep(for: .milliseconds(150))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertEqual((editor.string as NSString).substring(with: editor.selectedRange()), "Zażółć 🧪")
        session.draft = "Renamed.txt"
        XCTAssertEqual(try session.validatedName(), "Renamed.txt")
        session.cancel(); XCTAssertNil(coordinator.session)
        XCTAssertEqual(try String(contentsOf: file), "original")
        XCTAssertFalse(FileNames.exists(root.appendingPathComponent("Renamed.txt")))
    }
    @MainActor func testInvalidNameConflictsAndChangedSourcesKeepTheOriginal() async throws {
        let fm = FileManager.default, saved = PreferenceStore.shared.value
        let root = fm.temporaryDirectory.appendingPathComponent("RenameValidation-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("Source.txt"), other = root.appendingPathComponent("Existing.txt")
        try Data("source".utf8).write(to: file); try Data("existing".utf8).write(to: other)
        let entry = try FileEntry(url: file)
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop(); workspace.current.entries = [entry]; workspace.current.selection = [file]
        let editor = FilenameEditorRegistry.shared.editor(for: workspace.current)
        defer { editor.cancel(); workspace.current.stop(); PreferenceStore.shared.value = saved; try? fm.removeItem(at: root) }
        try editor.begin(entry, in: workspace)
        let session = try XCTUnwrap(editor.session)
        for invalid in ["", "..", "../outside", "Existing.txt"] { session.draft = invalid; XCTAssertThrowsError(try session.validatedName()) }
        session.draft = "Valid.txt"; XCTAssertEqual(try session.validatedName(), "Valid.txt")
        try Data("changed-source".utf8).write(to: file)
        XCTAssertFalse(session.commit()); XCTAssertNotNil(session.error)
        XCTAssertTrue(FileNames.exists(file)); XCTAssertFalse(FileNames.exists(root.appendingPathComponent("Valid.txt")))
        XCTAssertEqual(try String(contentsOf: other), "existing")
    }
}
