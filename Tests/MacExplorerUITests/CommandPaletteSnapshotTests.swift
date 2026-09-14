import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class CommandPaletteSnapshotTests: XCTestCase {
    @MainActor func testNativeCommandPaletteStates() async throws {
        guard let path = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native visual CI only") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CommandPalette-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("Project proposal.txt"); try Data("fixture".utf8).write(to: file)
        let input = InputPreferences.shared, savedTouch = input.touchFriendly
        let store = PreferenceStore.shared, saved = store.value
        defer { input.touchFriendly = savedTouch; store.value = saved; try? FileManager.default.removeItem(at: root) }
        input.touchFriendly = false
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop(); workspace.current.entries = [try FileEntry(url: file)]
        workspace.current.selection = [workspace.current.entries[0].url]
        defer { workspace.current.stop() }
        let output = URL(fileURLWithPath: path)
        var captures: [NativeViewSnapshotTests.Capture] = []
        for dark in [false, true] {
            store.value.theme = dark ? "dark" : "light"
            for (name, query) in [("commands", ""), ("commands-search", "pane"), ("commands-disabled", "delete permanently"), ("commands-empty", "no such command 94812")] {
                workspace.current.selection = name == "commands-disabled" ? [] : [workspace.current.entries[0].url]
                let model = CommandPaletteModel(query: query)
                let view = AnyView(CommandPaletteView(workspace: workspace, model: model))
                captures.append(try await NativeSnapshotCapture.render(view, named: (dark ? "dark-" : "light-") + name,
                    size: NSSize(width: 680, height: 540), dark: dark, output: output) { window in
                    let editor = try XCTUnwrap(window.firstResponder as? NSTextView, "Command search did not acquire native text focus")
                    XCTAssertEqual(editor.string, query)
                    if name == "commands-disabled" { XCTAssertNotNil(model.selection?.unavailable(in: workspace)) }
                    if name == "commands-empty" { XCTAssertTrue(model.matches.isEmpty) }
                })
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("command-captures.json"), options: .atomic)
        XCTAssertEqual(captures.count, 8)
    }
}
