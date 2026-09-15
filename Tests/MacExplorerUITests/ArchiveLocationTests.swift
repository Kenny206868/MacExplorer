import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class ArchiveLocationTests: XCTestCase {
    @MainActor func testVirtualNavigationAndSessionNeverBecomeFilesystemDestinations() throws {
        let source = URL(fileURLWithPath: "/tmp/Documentation.zip")
        let tab = BrowserTab(.archive(source, folder: "Package/Docs"))
        XCTAssertNil(tab.location.directory)
        tab.up(); XCTAssertEqual(tab.location, .archive(source, folder: "Package"))
        tab.up(); XCTAssertEqual(tab.location, .archive(source, folder: ""))
        tab.up(); XCTAssertEqual(tab.location, .folder(source.deletingLastPathComponent()))
        tab.back(); XCTAssertEqual(tab.location.archiveSource, source)
        let session = tab.session()
        let restored = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.history.current, tab.location)
        tab.stop()
    }
    @MainActor func testActualArchiveViewsAndJournaledRename() async throws {
        guard let output = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job") }
        let manager = FileManager.default, root = manager.temporaryDirectory.appendingPathComponent("ArchiveUI-" + UUID().uuidString)
        let input = root.appendingPathComponent("Package"), docs = input.appendingPathComponent("Documentation")
        try manager.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        try Data("Release documentation".utf8).write(to: docs.appendingPathComponent("Overview.txt"))
        try Data("Version 1.0".utf8).write(to: input.appendingPathComponent("Release Notes.txt"))
        let archive = try ArchiveService.compress([input], to: root, control: OperationControl())
        let before = try Data(contentsOf: archive)
        let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")), model = ArchiveLocationModel(source: archive, engine: engine)
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.archive(archive, folder: "")), options: FolderOptions(), query: "", allLocations: false, selection: []))
        let tab = workspace.current
        defer { tab.stop(); model.stop() }
        await model.scan(); XCTAssertTrue(model.editable); XCTAssertNotNil(model.catalog)
        XCTAssertNil(workspace.destination); XCTAssertTrue(workspace.selectedURLs.isEmpty)
        var captures: [NativeViewSnapshotTests.Capture] = []
        for folder in ["", "Package"] {
            tab.navigate(.archive(archive, folder: folder))
            model.selection = folder.isEmpty ? ["Package"] : ["Package/Release Notes.txt"]
            for dark in [false, true] {
                captures.append(try await NativeSnapshotCapture.render(AnyView(ArchiveLocationView(workspace: workspace, tab: tab, source: archive, folder: folder, model: model)), named: (dark ? "dark-" : "light-") + "archive-location-" + (folder.isEmpty ? "root" : "folder"), size: NSSize(width: 820, height: 560), dark: dark, output: URL(fileURLWithPath: output)))
            }
        }
        XCTAssertEqual(try Data(contentsOf: archive), before, "Rendering a virtual location must not mutate the archive")
        await model.scan()
        let center = OperationCenter()
        await model.apply(.rename(path: "Package/Release Notes.txt", to: "Package/Changelog.txt"), center: center)
        XCTAssertNotNil(model.catalog?.members.first { $0.path == "Package/Changelog.txt" })
        XCTAssertEqual(center.undoStack.count, 1)
        let undo = await engine.undo(try XCTUnwrap(center.undoStack.first), control: OperationControl())
        XCTAssertTrue(undo.errors.isEmpty, undo.errors.description); XCTAssertEqual(try Data(contentsOf: archive), before)
        try JSONEncoder().encode(captures).write(to: URL(fileURLWithPath: output).appendingPathComponent("archive-location-captures.json"))
    }
}
