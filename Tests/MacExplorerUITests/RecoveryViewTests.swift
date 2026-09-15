import XCTest
import SwiftUI
import AppKit
import ExplorerCore
import ExplorerJournal
@testable import MacExplorer

final class RecoveryViewTests: XCTestCase {
    private func interrupted(in directory: URL, file: URL, moved: URL) throws -> UUID {
        let journal = try FileJournal(directory: directory.appendingPathComponent("Journal"))
        let transaction = try journal.begin(title: "Move Project Assets")
        try transaction.move(file, to: moved)
        return transaction.id
    }
    @MainActor func testRecoveryViewsUseRealJournalStateWithoutImplicitMutation() async throws {
        guard let path = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job") }
        let manager = FileManager.default, root = manager.temporaryDirectory.appendingPathComponent("RecoveryViews-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let source = root.appendingPathComponent("Project.txt"), moved = root.appendingPathComponent("Pending.txt")
        try Data("Original content".utf8).write(to: source)
        let recovery = root.appendingPathComponent("Recovery")
        let id = try interrupted(in: recovery, file: source, moved: moved)
        let engine = FileOperationEngine(recoveryDirectory: recovery)
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop(); defer { workspace.current.stop() }
        let model = RecoveryModel(engine: engine), output = URL(fileURLWithPath: path)
        await model.load(); XCTAssertEqual(model.interrupted.count, 1)
        var captures: [NativeViewSnapshotTests.Capture] = []
        for dark in [false, true] {
            captures.append(try await NativeSnapshotCapture.render(AnyView(RecoveryView(workspace: workspace, model: model)), named: (dark ? "dark-" : "light-") + "recovery-interrupted", size: NSSize(width: 780, height: 640), dark: dark, output: output))
            XCTAssertTrue(FileNames.exists(moved)); XCTAssertFalse(FileNames.exists(source))
        }
        let report = try await engine.recoverInterrupted(id); XCTAssertTrue(report.resolved, report.notices.description)
        model.notice = "Recovery completed. Checkpointed work is preserved."; await model.load()
        let created = await engine.run(FileJob(.createFile, destination: root.appendingPathComponent("Restored.txt")), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertTrue(created.errors.isEmpty, created.errors.description); await model.load()
        XCTAssertTrue(model.interrupted.isEmpty); XCTAssertEqual(model.receipts.count, 1)
        for dark in [false, true] {
            captures.append(try await NativeSnapshotCapture.render(AnyView(RecoveryView(workspace: workspace, model: model)), named: (dark ? "dark-" : "light-") + "recovery-history", size: NSSize(width: 780, height: 640), dark: dark, output: output))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("recovery-captures.json"), options: .atomic)
        XCTAssertEqual(try String(contentsOf: source), "Original content")
    }
}
