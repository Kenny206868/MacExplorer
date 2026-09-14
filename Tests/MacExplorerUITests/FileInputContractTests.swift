import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class FileInputContractTests: XCTestCase {
    @MainActor private func browser(_ location: Location = .home) -> ExplorerWorkspace {
        _ = NSApplication.shared
        let result = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(location), options: FolderOptions(), query: "", allLocations: false, selection: []))
        result.current.stop(); return result
    }
    private func files() throws -> (URL, [FileEntry]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileInput-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let entries = try (0..<15).map { index -> FileEntry in
            let url = root.appendingPathComponent(String(format: "Document %02d.txt", index))
            try Data("Fixture".utf8).write(to: url); return try FileEntry(url: url)
        }
        return (root, entries)
    }
    @MainActor func testTouchSelectionWorksInEveryPresentationWithoutModifiers() async throws {
        let (folder, entries) = try files(), workspace = browser()
        let previous = PreferenceStore.shared.value
        defer { workspace.current.stop(); PreferenceStore.shared.value = previous; AppRouter.shared.active = nil; try? FileManager.default.removeItem(at: folder) }
        workspace.current.entries = entries; workspace.touchSelecting = true
        for mode in ViewMode.allCases {
            workspace.current.options.view = mode; workspace.current.selection = []
            workspace.tapFile(entries[0].url, modifiers: []); workspace.tapFile(entries[2].url, modifiers: [])
            XCTAssertEqual(workspace.current.selection, [entries[0].url, entries[2].url], mode.rawValue)
            workspace.tapFile(entries[0].url, modifiers: [])
            XCTAssertEqual(workspace.current.selection, [entries[2].url], mode.rawValue)
            workspace.touchSelecting = false; workspace.tapFile(entries[4].url, modifiers: [])
            XCTAssertEqual(workspace.current.selection, [entries[4].url], mode.rawValue); workspace.touchSelecting = true
        }
    }
    @MainActor func testTouchDensityOverridesCompactPreferenceAndPreservesDesktopSizes() async {
        let suite = "FileInput-" + UUID().uuidString, defaults = UserDefaults(suiteName: "FileInput-" + UUID().uuidString)!
        let input = InputPreferences(defaults: defaults)
        defer { defaults.removeObject(forKey: "MacExplorer.input.touchFriendly"); _ = suite }
        XCTAssertEqual(input.rowHeight(compact: true), 28); XCTAssertEqual(input.rowHeight(compact: false), 36)
        input.touchFriendly = true
        XCTAssertEqual(input.target, 44); XCTAssertEqual(input.headerHeight, 44); XCTAssertEqual(input.rowHeight(compact: true), 44)
        for mode in ViewMode.allCases { XCTAssertGreaterThanOrEqual(input.gridCellHeight(mode), 44) }
        XCTAssertTrue(InputPreferences(defaults: defaults).touchFriendly)
    }
    @MainActor func testDragFromInactivePaneUsesOnlyItsOwnSelectedFiles() async throws {
        let (folder, entries) = try files(), root = browser()
        root.dualPane = DualPaneController(primary: root)
        let dual = try XCTUnwrap(root.dualPane), other = dual.secondary
        other.current.stop(); root.current.entries = entries; other.current.entries = Array(entries.suffix(8))
        root.current.selection = [entries[0].url, entries[1].url]; other.current.selection = [entries[8].url, entries[10].url]
        defer { root.current.stop(); other.current.stop(); AppRouter.shared.active = nil; try? FileManager.default.removeItem(at: folder) }
        dual.focus(.primary)
        let anchor = FileDragAnchorView(); anchor.workspace = other; anchor.tab = other.current; anchor.url = entries[8].url
        XCTAssertEqual(anchor.prepareEntries().map(\.url), [entries[8].url, entries[10].url])
        XCTAssertTrue(AppRouter.shared.active === other)
        XCTAssertEqual(root.current.selection, [entries[0].url, entries[1].url])
        anchor.url = entries[13].url; XCTAssertEqual(anchor.prepareEntries().map(\.url), [entries[13].url])
    }
    @MainActor func testLongPressPreservesMultiSelectionAndTargetsOwningPane() async throws {
        let (folder, entries) = try files(), root = browser()
        root.dualPane = DualPaneController(primary: root)
        let other = try XCTUnwrap(root.dualPane).secondary
        other.current.stop(); other.current.entries = entries; other.current.selection = [entries[0].url, entries[2].url]
        defer { root.current.stop(); other.current.stop(); AppRouter.shared.active = nil; try? FileManager.default.removeItem(at: folder) }
        other.showFileActions(for: entries[0]); XCTAssertEqual(other.sheet, .fileActions)
        XCTAssertEqual(other.current.selection.count, 2); XCTAssertNil(root.sheet)
        other.sheet = nil; other.showFileActions(for: entries[3]); XCTAssertEqual(other.current.selection, [entries[3].url])
    }
    @MainActor func testSelectModeNeverOpensFolderWithSingleClickOpenEnabled() async throws {
        let (folder, _) = try files(), workspace = browser()
        let entry = try FileEntry(url: folder), previous = PreferenceStore.shared.value
        defer { workspace.current.stop(); PreferenceStore.shared.value = previous; AppRouter.shared.active = nil; try? FileManager.default.removeItem(at: folder) }
        workspace.current.entries = [entry]; PreferenceStore.shared.value.singleClickOpen = true; workspace.touchSelecting = true
        workspace.activateFile(entry, modifiers: []); workspace.activateFile(entry, doubleClick: true, modifiers: [])
        XCTAssertEqual(workspace.current.location, .home); XCTAssertEqual(workspace.current.selection, [entry.url])
    }
}
