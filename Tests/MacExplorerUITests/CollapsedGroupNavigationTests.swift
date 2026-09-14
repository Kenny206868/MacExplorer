import XCTest
import ExplorerCore
@testable import MacExplorer

final class CollapsedGroupNavigationTests: XCTestCase {
    @MainActor func testCollapsedRowsCannotBeSelectedOrActivatedByKeyboard() async throws {
        let fm = FileManager.default, saved = PreferenceStore.shared.value
        let root = fm.temporaryDirectory.appendingPathComponent("GroupNavigation-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { PreferenceStore.shared.value = saved; try? fm.removeItem(at: root) }
        let directory = root.appendingPathComponent("Hidden folder")
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        let files = try ["A.txt", "B.txt", "C.txt"].map { name -> FileEntry in
            let url = root.appendingPathComponent(name); try Data().write(to: url); return try FileEntry(url: url)
        }
        let folder = try FileEntry(url: directory)
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        let tab = workspace.current; tab.stop(); defer { tab.stop() }
        tab.entries = [folder] + files; tab.options.group = .kind; tab.options.view = .details
        workspace.select(folder.url, extend: false, range: false)
        tab.toggleGroup(folder.kind)
        XCTAssertFalse(tab.selection.contains(folder.url)); XCTAssertNil(tab.focusedURL)
        workspace.selectAll(); XCTAssertEqual(tab.selection, Set(files.map(\.url)))
        workspace.select(folder.url, extend: false, range: false)
        XCTAssertEqual(tab.selection, Set(files.map(\.url)))
        workspace.selectBoundary(last: false, extend: false)
        workspace.selectBoundary(last: true, extend: true)
        XCTAssertEqual(tab.selection, Set(files.map(\.url)))
        tab.selection = []; tab.focusedURL = nil; tab.typeAhead.reset()
        XCTAssertFalse(workspace.typeToSelect("Hidden", time: 1))
        tab.options.view = .large
        XCTAssertTrue(tab.navigableEntries.contains(folder))
        tab.options.view = .details; tab.toggleGroup(folder.kind)
        XCTAssertTrue(tab.navigableEntries.contains(folder))
        tab.toggleGroup(folder.kind); tab.options.group = .none
        XCTAssertTrue(tab.collapsedGroups.isEmpty)
    }
}
