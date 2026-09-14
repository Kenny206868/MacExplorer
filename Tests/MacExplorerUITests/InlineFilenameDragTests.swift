import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class InlineFilenameDragTests: XCTestCase {
    @MainActor func testEditingTextCannotStartAFileTransferOrChangeSelection() async throws {
        _ = NSApplication.shared
        let fm = FileManager.default, original = PreferenceStore.shared.value
        let root = fm.temporaryDirectory.appendingPathComponent("RenameDrag-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("Original.txt"); try Data("payload".utf8).write(to: file)
        let entry = try FileEntry(url: file)
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop(); workspace.current.entries = [entry]; workspace.current.selection = [file]
        let editor = FilenameEditorRegistry.shared.editor(for: workspace.current)
        let anchor = FileDragAnchorView(); anchor.url = file; anchor.workspace = workspace; anchor.tab = workspace.current
        defer { editor.cancel(); workspace.current.stop(); PreferenceStore.shared.value = original; AppRouter.shared.active = nil; try? fm.removeItem(at: root) }
        try editor.begin(entry, in: workspace)
        XCTAssertTrue(anchor.isEditingFilename)
        XCTAssertTrue(anchor.prepareEntries().isEmpty)
        XCTAssertEqual(workspace.current.selection, [file]); XCTAssertNotNil(editor.session)
        editor.cancel()
        XCTAssertEqual(anchor.prepareEntries().map(\.url), [file])
        XCTAssertEqual(try String(contentsOf: file), "payload")
    }
}
