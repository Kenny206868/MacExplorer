import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class DualPaneStateTests: XCTestCase {
    @MainActor private func workspace() -> ExplorerWorkspace {
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.home), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop(); return workspace
    }
    @MainActor func testIndependentTabsFocusAndSessionRoundTrip() async throws {
        let root = workspace(), controller = DualPaneController(primary: workspace())
        _ = controller
        root.dualPane = DualPaneController(primary: root)
        let dual = try XCTUnwrap(root.dualPane)
        defer { root.current.stop(); dual.secondary.tabs.forEach { $0.stop() }; AppRouter.shared.active = nil }
        root.current.selection = [URL(fileURLWithPath: "/primary.txt")]
        dual.secondary.current.selection = [URL(fileURLWithPath: "/secondary.txt")]
        dual.secondary.newTab(.computer); dual.secondary.current.stop()
        dual.focus(.secondary)
        XCTAssertTrue(AppRouter.shared.active === dual.secondary)
        XCTAssertEqual(root.tabs.count, 1); XCTAssertEqual(dual.secondary.tabs.count, 2)
        XCTAssertEqual(root.current.selection.count, 1)
        dual.geometry.ratio = 0.63; dual.geometry.orientation = .stacked
        let snapshot = WorkspaceSessionCoordinator.shared.snapshot(root)
        let decoded = try JSONDecoder().decode(WindowSession.self, from: JSONEncoder().encode(snapshot))
        let restored = ExplorerWorkspace(windowSession: decoded)
        defer { restored.tabs.forEach { $0.stop() }; restored.dualPane?.secondary.tabs.forEach { $0.stop() } }
        XCTAssertEqual(restored.dualPane?.secondary.tabs.count, 2)
        XCTAssertEqual(restored.dualPane?.secondary.current.location, .computer)
        XCTAssertEqual(restored.dualPane?.geometry.ratio, 0.63)
        XCTAssertEqual(restored.dualPane?.geometry.focused, .secondary)
        XCTAssertEqual(restored.current.selection, root.current.selection)
    }
    @MainActor func testTransferSnapshotDoesNotFollowLaterSelectionOrDestinationNavigation() async throws {
        let manager = FileManager.default
        let fixture = manager.temporaryDirectory.appendingPathComponent("PaneTransfer-" + UUID().uuidString)
        defer { try? manager.removeItem(at: fixture) }
        let source = fixture.appendingPathComponent("from"), destination = fixture.appendingPathComponent("to")
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("file.txt"); try Data("source".utf8).write(to: file)
        let root = workspace(); root.current.entries = [try FileEntry(url: file)]; root.current.selection = [file]
        let request = try await PaneTransferRequest.prepare(source: root, destination: destination, move: false)
        root.current.selection = []
        try request.snapshot.validate()
        XCTAssertEqual(request.job.sources.first?.path, file.path)
        XCTAssertEqual(request.job.destination?.path, destination.path)
        let engine = FileOperationEngine(recoveryDirectory: fixture.appendingPathComponent("receipts"))
        let result = await engine.run(request.job, control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertTrue(result.errors.isEmpty, result.errors.description)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("file.txt")), "source")
        try Data("changed source".utf8).write(to: file)
        XCTAssertThrowsError(try request.snapshot.validate())
        root.current.stop()
    }
    @MainActor func testChangedDestinationCannotBeConfirmed() async throws {
        let manager = FileManager.default, root = workspace()
        let fixture = manager.temporaryDirectory.appendingPathComponent("PaneConfirm-" + UUID().uuidString)
        defer { try? manager.removeItem(at: fixture); root.current.stop() }
        let destination = fixture.appendingPathComponent("to")
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = fixture.appendingPathComponent("file.txt"); try Data("source".utf8).write(to: file)
        root.current.entries = [try FileEntry(url: file)]; root.current.selection = [file]
        let request = try await PaneTransferRequest.prepare(source: root, destination: destination, move: true)
        try manager.moveItem(at: destination, to: fixture.appendingPathComponent("old"))
        try manager.createDirectory(at: destination, withIntermediateDirectories: false)
        XCTAssertThrowsError(try request.snapshot.validate()); XCTAssertTrue(FileNames.exists(file))
    }
}
