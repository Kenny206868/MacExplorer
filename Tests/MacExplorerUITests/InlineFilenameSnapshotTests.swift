import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class InlineFilenameSnapshotTests: XCTestCase {
    @MainActor func testRealInlineEditorRendersWithoutCancellingItself() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job only") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory), fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("InlineSnapshot-" + UUID().uuidString)
        let documents = root.appendingPathComponent("Documents")
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        let names = ["Brand guidelines.md", "Meeting notes.txt", "Project proposal.txt"]
        let entries = try names.map { name -> FileEntry in
            let url = documents.appendingPathComponent(name); try Data("Design review fixture.\n".utf8).write(to: url); return try FileEntry(url: url)
        }
        let preferences = PreferenceStore.shared, original = PreferenceStore.shared.value
        let touch = InputPreferences.shared.touchFriendly, columns = DetailsColumnStore.shared.value
        defer {
            preferences.value = original; InputPreferences.shared.touchFriendly = touch; DetailsColumnStore.shared.value = columns
            AppRouter.shared.active = nil; try? fm.removeItem(at: root)
        }
        var settings = Preferences(); settings.pins = [Bookmark(documents)]; settings.restoreTabs = false; settings.inspector = true
        preferences.value = settings; InputPreferences.shared.touchFriendly = false; DetailsColumnStore.shared.value = DetailsColumns()
        var captures: [NativeViewSnapshotTests.Capture] = []
        for dark in [false, true] {
            preferences.value.theme = dark ? "dark" : "light"
            let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(documents)), options: FolderOptions(), query: "", allLocations: false, selection: []))
            workspace.current.stop(); workspace.current.entries = entries; workspace.current.selection = [entries[1].url]; workspace.current.loading = false
            let coordinator = FilenameEditorRegistry.shared.editor(for: workspace.current)
            try coordinator.begin(entries[1], in: workspace)
            let content = AnyView(WorkspaceShell(workspace: workspace, tab: workspace.current).environmentObject(workspace).environmentObject(preferences).environmentObject(AppUpdater()))
            captures.append(try await NativeSnapshotCapture.render(content, named: (dark ? "dark-" : "light-") + "inline-rename", size: NSSize(width: 1260, height: 800), dark: dark, output: output, verify: { window in
                XCTAssertNotNil(coordinator.session, "Swapping a label into an editor must not cancel its session")
                let fieldEditor = try XCTUnwrap(window.firstResponder as? NSTextView, "The actual filename field must own focus")
                XCTAssertEqual(fieldEditor.string, "Meeting notes.txt")
                XCTAssertEqual((fieldEditor.string as NSString).substring(with: fieldEditor.selectedRange()), "Meeting notes")
            }))
            coordinator.cancel(); workspace.current.stop()
            XCTAssertEqual(try String(contentsOf: entries[1].url), "Design review fixture.\n")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("inline-captures.json"), options: .atomic)
        XCTAssertEqual(captures.count, 2)
    }
}
