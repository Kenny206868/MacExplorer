import Foundation
import XCTest
@testable import ExplorerJournal

final class FileJournalTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorer-JournalTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    private func write(_ text: String, _ path: URL) throws { try Data(text.utf8).write(to: path) }
    private func read(_ path: URL) throws -> String { try String(contentsOf: path, encoding: .utf8) }
    private func journal(_ root: URL) throws -> FileJournal { try FileJournal(directory: root.appendingPathComponent("journal")) }
    func testDurabilityConfigurationAndSingleWriterLock() throws {
        let root = try fixture(), first = try journal(root)
        XCTAssertEqual(try first.database.query("PRAGMA journal_mode").first?.first?.string, "wal")
        XCTAssertEqual(try first.database.query("PRAGMA synchronous").first?.first?.integer, 2)
        XCTAssertEqual(try first.database.query("PRAGMA fullfsync").first?.first?.integer, 1)
        XCTAssertThrowsError(try journal(root)); XCTAssertTrue(try first.summaries().isEmpty)
    }
    func testRecoveryRestoresUncheckpointedRenameAndIsIdempotent() throws {
        let root = try fixture(), store = try journal(root), from = root.appendingPathComponent("a"), to = root.appendingPathComponent("b")
        try write("original", from)
        var transaction: JournalTransaction? = try store.begin(title: "Move")
        let id = transaction!.id; try transaction!.move(from, to: to); transaction = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: from.path))
        XCTAssertTrue(try store.recover(id).resolved)
        XCTAssertEqual(try read(from), "original"); XCTAssertFalse(FileManager.default.fileExists(atPath: to.path))
        XCTAssertTrue(try store.recover(id).resolved); XCTAssertTrue(try store.summaries().isEmpty)
    }
    func testCheckpointKeepsCompletedItemsAndDurableReceipt() throws {
        let root = try fixture(), store = try journal(root)
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b"), c = root.appendingPathComponent("c")
        try write("data", a)
        var transaction: JournalTransaction? = try store.begin(title: "Two moves")
        let id = transaction!.id
        try transaction!.move(a, to: b); try transaction!.checkpoint(receipt: Data("undo-a-to-b".utf8))
        try transaction!.move(b, to: c); transaction = nil
        let result = try store.recover(id)
        XCTAssertTrue(result.resolved); XCTAssertEqual(result.receipt, Data("undo-a-to-b".utf8))
        XCTAssertEqual(try read(b), "data"); XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertEqual(try store.receipts(), [Data("undo-a-to-b".utf8)])
    }
    func testOccupiedSourceAndChangedObjectsStopRecovery() throws {
        let root = try fixture(), store = try journal(root), a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try write("original", a)
        var transaction: JournalTransaction? = try store.begin(title: "Move")
        let id = transaction!.id; try transaction!.move(a, to: b); transaction = nil
        try write("newer", a)
        XCTAssertFalse(try store.recover(id).resolved)
        XCTAssertEqual(try read(a), "newer"); XCTAssertEqual(try read(b), "original")
        try FileManager.default.removeItem(at: a); try write("externally modified", b)
        XCTAssertFalse(try store.recover(id).resolved); XCTAssertEqual(try read(b), "externally modified")
    }
    func testNoClobberMoveAndActiveOperationRecoveryRefusal() throws {
        let root = try fixture(), store = try journal(root), a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try write("a", a); try write("b", b)
        let transaction = try store.begin(title: "No clobber")
        XCTAssertThrowsError(try transaction.move(a, to: b)); XCTAssertThrowsError(try store.recover(transaction.id))
        XCTAssertEqual(try read(a), "a"); XCTAssertEqual(try read(b), "b")
    }
    func testChangedParentCannotReceiveRecoveredObject() throws {
        let root = try fixture(), store = try journal(root), parent = root.appendingPathComponent("parent")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let a = parent.appendingPathComponent("a"), b = root.appendingPathComponent("b"); try write("original", a)
        var transaction: JournalTransaction? = try store.begin(title: "Move")
        let id = transaction!.id; try transaction!.move(a, to: b); transaction = nil
        try FileManager.default.moveItem(at: parent, to: root.appendingPathComponent("original-parent"))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        XCTAssertFalse(try store.recover(id).resolved); XCTAssertEqual(try read(b), "original")
    }
    func testSymlinkDatabaseDirectoryRejectedAndUnknownSchemaRetained() throws {
        let root = try fixture(), real = root.appendingPathComponent("real"), link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertThrowsError(try FileJournal(directory: link))
        var store: FileJournal? = try journal(root)
        try store!.database.execute("PRAGMA user_version=999"); store = nil
        XCTAssertThrowsError(try journal(root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("journal/operations.sqlite3").path))
    }
    func testArtifactRecoveryNeverDeletesContents() throws {
        let root = try fixture(), store = try journal(root), stage = root.appendingPathComponent(".MacExplorer-stage-fixture")
        var transaction: JournalTransaction? = try store.begin(title: "Partial copy")
        let id = transaction!.id; try transaction!.registerArtifact(stage)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        try write("partial but retained", stage.appendingPathComponent("payload")); transaction = nil
        let result = try store.recover(id)
        XCTAssertTrue(result.resolved); XCTAssertEqual(result.retainedArtifacts, [stage])
        XCTAssertEqual(try read(stage.appendingPathComponent("payload")), "partial but retained")
    }
    func testEmptyDirectoryRecoveryRefusesExternalInsertion() throws {
        let root = try fixture(), store = try journal(root), a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: false)
        var transaction: JournalTransaction? = try store.begin(title: "Container")
        let id = transaction!.id; try transaction!.move(a, to: b, emptyDirectory: true); transaction = nil
        try write("foreign", b.appendingPathComponent("new"))
        XCTAssertFalse(try store.recover(id).resolved); XCTAssertEqual(try read(b.appendingPathComponent("new")), "foreign")
    }
    func testHardExitAtEveryRenameBoundaryRetainsOriginalsOrCheckpoint() throws {
        for point in [JournalFaultPoint.intentCommitted, .filesystemApplied, .appliedCommitted] {
            for ordinal in 1...3 {
                let root = try crashFixture()
                XCTAssertEqual(try probe(root, "mutate", point, ordinal), 73, "\(point) \(ordinal)")
                let store = try journal(root), item = try XCTUnwrap(store.summaries().first)
                XCTAssertTrue(try store.recover(item.id).resolved, "\(point) \(ordinal)")
                XCTAssertEqual(try read(root.appendingPathComponent("source")), "NEW")
                XCTAssertEqual(try read(root.appendingPathComponent("destination")), "OLD")
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".backup").path))
            }
        }
        let root = try crashFixture()
        XCTAssertEqual(try probe(root, "mutate", .checkpointCommitted, 1), 73)
        let store = try journal(root), item = try XCTUnwrap(store.summaries().first), result = try store.recover(item.id)
        XCTAssertTrue(result.resolved); XCTAssertEqual(result.receipt, Data("retained-undo-receipt".utf8))
        XCTAssertEqual(try read(root.appendingPathComponent("destination")), "NEW")
        XCTAssertEqual(try read(root.appendingPathComponent(".backup")), "OLD")
    }
    func testHardExitDuringRecoveryCanResumeAtEveryReverseBoundary() throws {
        for point in [JournalFaultPoint.rollbackIntentCommitted, .rollbackApplied, .rollbackCommitted] {
            for ordinal in 1...3 {
                let root = try crashFixture()
                XCTAssertEqual(try probe(root, "mutate", .appliedCommitted, 3), 73)
                XCTAssertEqual(try probe(root, "recover", point, ordinal), 73)
                let store = try journal(root), item = try XCTUnwrap(store.summaries().first)
                XCTAssertTrue(try store.recover(item.id).resolved, "\(point) \(ordinal)")
                XCTAssertEqual(try read(root.appendingPathComponent("source")), "NEW")
                XCTAssertEqual(try read(root.appendingPathComponent("destination")), "OLD")
            }
        }
    }
    private func crashFixture() throws -> URL {
        let root = try fixture(); try write("NEW", root.appendingPathComponent("source")); try write("OLD", root.appendingPathComponent("destination")); return root
    }
    private func probe(_ root: URL, _ mode: String, _ point: JournalFaultPoint, _ ordinal: Int) throws -> Int32 {
        let ownExecutable = URL(fileURLWithPath: CommandLine.arguments[0])
        let candidates = [ownExecutable.deletingLastPathComponent().appendingPathComponent("RecoveryCrashProbe"),
                          ownExecutable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("RecoveryCrashProbe"),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/RecoveryCrashProbe")]
        let executable = try XCTUnwrap(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }, "Build RecoveryCrashProbe before running crash tests")
        let process = Process(); process.executableURL = executable
        process.arguments = [root.path, mode, point.rawValue, String(ordinal)]
        try process.run(); process.waitUntilExit(); return process.terminationStatus
    }
}
