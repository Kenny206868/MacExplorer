import XCTest
import ExplorerJournal
@testable import ExplorerCore

final class FileOperationCrashTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorer-EngineCrash-" + UUID().uuidString)
        for path in ["from", "to"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        try Data("new source".utf8).write(to: root.appendingPathComponent("from/file.txt"))
        try Data("old destination".utf8).write(to: root.appendingPathComponent("to/file.txt"))
        try Data("alpha".utf8).write(to: root.appendingPathComponent("a.txt")); try Data("beta".utf8).write(to: root.appendingPathComponent("b.txt"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    private func probe(_ root: URL, mode: String, point: JournalFaultPoint, ordinal: Int) throws {
        let own = URL(fileURLWithPath: CommandLine.arguments[0])
        let candidates = [own.deletingLastPathComponent().appendingPathComponent("FileOperationCrashProbe"),
            own.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("FileOperationCrashProbe"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/FileOperationCrashProbe")]
        let executable = try XCTUnwrap(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }, "Build the crash probe before native tests")
        let process = Process(), pipe = Pipe(); process.executableURL = executable
        process.arguments = [root.path, mode, point.rawValue, String(ordinal)]; process.standardError = pipe; process.standardOutput = pipe
        try process.run()
        let limit = Date().addingTimeInterval(15)
        while process.isRunning && Date() < limit { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { process.terminate(); XCTFail("Crash probe timed out") }
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 73, "\(mode): \(point) #\(ordinal): \(text)")
    }
    private func read(_ root: URL, _ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
    func testReplaceAndRenameRecoverAtEveryInstallBoundary() async throws {
        for (mode, moves) in [("copy", 2), ("move", 3), ("rename", 4), ("create", 1)] {
            for point in [JournalFaultPoint.intentCommitted, .filesystemApplied, .appliedCommitted] {
                for ordinal in 1...moves {
                    let root = try fixture(); try probe(root, mode: mode, point: point, ordinal: ordinal)
                    let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts"))
                    let pending = try await engine.interruptedOperations(); XCTAssertEqual(pending.count, 1)
                    let id = try XCTUnwrap(pending.first?.id)
                    let blocked = await engine.run(FileJob(.createFile, destination: root.appendingPathComponent("must-not-create")), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
                    XCTAssertFalse(blocked.errors.isEmpty); XCTAssertFalse(FileNames.exists(root.appendingPathComponent("must-not-create")))
                    let report = try await engine.recoverInterrupted(id); XCTAssertTrue(report.resolved, report.notices.joined(separator: "\n"))
                    XCTAssertEqual(try read(root, "from/file.txt"), "new source"); XCTAssertEqual(try read(root, "to/file.txt"), "old destination")
                    XCTAssertEqual(try read(root, "a.txt"), "alpha"); XCTAssertEqual(try read(root, "b.txt"), "beta")
                    XCTAssertFalse(FileNames.exists(root.appendingPathComponent("to/New Folder")))
                    let repeated = try await engine.recoverInterrupted(id); XCTAssertTrue(repeated.resolved)
                    let history = await engine.history(); XCTAssertTrue(history.isEmpty)
                }
            }
        }
    }
    func testDurableCheckpointSurvivesExitAndCanBeUndoneExactlyOnce() async throws {
        let root = try fixture(); try probe(root, mode: "move", point: .checkpointCommitted, ordinal: 1)
        let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts"))
        let pending = try await engine.interruptedOperations()
        _ = try await engine.recoverInterrupted(try XCTUnwrap(pending.first?.id))
        XCTAssertFalse(FileNames.exists(root.appendingPathComponent("from/file.txt"))); XCTAssertEqual(try read(root, "to/file.txt"), "new source")
        let history = await engine.history(), receipt = try XCTUnwrap(history.first); XCTAssertEqual(history.count, 1)
        let undone = await engine.undo(receipt, control: OperationControl()); XCTAssertTrue(undone.errors.isEmpty, undone.errors.description)
        XCTAssertEqual(try read(root, "from/file.txt"), "new source"); XCTAssertEqual(try read(root, "to/file.txt"), "old destination")
        let remaining = await engine.history()
        XCTAssertFalse(remaining.contains { $0.id == receipt.id }); XCTAssertTrue(remaining.contains { $0.id == undone.receipt.id })
    }
    func testCrashDuringUndoPreservesOriginalReceiptUntilCheckpoint() async throws {
        let root = try fixture(); try probe(root, mode: "undo", point: .filesystemApplied, ordinal: 1)
        let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts"))
        let pending = try await engine.interruptedOperations()
        let report = try await engine.recoverInterrupted(try XCTUnwrap(pending.first?.id)); XCTAssertTrue(report.resolved, report.notices.description)
        XCTAssertFalse(FileNames.exists(root.appendingPathComponent("from/file.txt"))); XCTAssertEqual(try read(root, "to/file.txt"), "new source")
        let history = await engine.history(); XCTAssertEqual(history.count, 1)
        let result = await engine.undo(try XCTUnwrap(history.first), control: OperationControl())
        XCTAssertTrue(result.errors.isEmpty, result.errors.description); XCTAssertEqual(try read(root, "to/file.txt"), "old destination")
    }
}
