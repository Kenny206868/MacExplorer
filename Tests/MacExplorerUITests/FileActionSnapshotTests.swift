import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class FileActionSnapshotTests: XCTestCase {
    @MainActor func testDismissedActionCannotTargetNewSelectionTabOrModifiedFile() async throws {
        _ = NSApplication.shared
        let fm = FileManager.default, previous = PreferenceStore.shared.value
        let root = fm.temporaryDirectory.appendingPathComponent("FileAction-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        let first = root.appendingPathComponent("First.txt"), second = root.appendingPathComponent("Second.txt")
        try Data("original".utf8).write(to: first); try Data("second".utf8).write(to: second)
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop(); workspace.current.entries = try [first, second].map { try FileEntry(url: $0) }
        workspace.current.selection = [first]
        defer { workspace.tabs.forEach { $0.stop() }; PreferenceStore.shared.value = previous; try? fm.removeItem(at: root) }
        let snapshot = try FileActionSnapshot(workspace)
        XCTAssertNoThrow(try snapshot.validate())
        workspace.current.selection = [second]; XCTAssertThrowsError(try snapshot.validate())
        workspace.current.selection = [first]; workspace.sheet = .properties; XCTAssertThrowsError(try snapshot.validate())
        workspace.sheet = nil; XCTAssertNoThrow(try snapshot.validate())
        let id = workspace.activeID; workspace.newTab(.home); workspace.current.stop()
        XCTAssertThrowsError(try snapshot.validate()); workspace.activeID = id
        XCTAssertNoThrow(try snapshot.validate())
        try Data("externally changed".utf8).write(to: first); XCTAssertThrowsError(try snapshot.validate())
        XCTAssertEqual(try String(contentsOf: second), "second")
    }
}
