import XCTest
@testable import ExplorerJournal

final class ActiveRecoveryTests: XCTestCase {
    func testCanonicalParentAliasDoesNotWeakenLeafSymlinkRejection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JournalAlias-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let store = try FileJournal(directory: alias.appendingPathComponent("journal"))
        XCTAssertTrue(try store.summaries().isEmpty)
        XCTAssertThrowsError(try FileJournal(directory: real.appendingPathComponent("journal")))
        let leaf = root.appendingPathComponent("linked-journal")
        try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: real.appendingPathComponent("journal"))
        XCTAssertThrowsError(try FileJournal(directory: leaf))
    }
    func testReceiptsUseCommitOrderRatherThanWallClock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JournalOrder-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try FileJournal(directory: root)
        let first = try journal.begin(title: "First")
        try first.checkpoint(receipt: Data("first".utf8)); try first.finish(receipt: nil)
        let second = try journal.begin(title: "Second")
        try second.checkpoint(receipt: Data("second".utf8)); try second.finish(receipt: nil)
        try journal.database.execute("UPDATE operations SET started=0 WHERE id=?", [.text(second.id.uuidString)])
        XCTAssertEqual(try journal.receipts(), [Data("first".utf8), Data("second".utf8)])
        XCTAssertEqual(try journal.receipts(limit: 1), [Data("second".utf8)])
    }
    func testActiveRollbackRetainsCheckpointAndCanContinue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try FileJournal(directory: root.appendingPathComponent("journal"))
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b"), c = root.appendingPathComponent("c")
        try Data("original".utf8).write(to: a)
        let transaction = try journal.begin(title: "Partial transaction")
        try transaction.move(a, to: b); try transaction.checkpoint(receipt: Data("a-to-b".utf8))
        try transaction.move(b, to: c)
        let rollback = try transaction.rollbackToCheckpoint()
        XCTAssertTrue(rollback.resolved); XCTAssertEqual(rollback.receipt, Data("a-to-b".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: c.path))
        XCTAssertThrowsError(try journal.recover(transaction.id))
        try transaction.move(b, to: c); try transaction.checkpoint(receipt: Data("a-to-c".utf8)); try transaction.finish(receipt: nil)
        XCTAssertTrue(try journal.summaries().isEmpty)
        XCTAssertEqual(try journal.receipts(), [Data("a-to-c".utf8)])
    }
    func testAcknowledgementIsExplicitAndDoesNotModifyFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try FileJournal(directory: root.appendingPathComponent("journal"))
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("original".utf8).write(to: a)
        var transaction: JournalTransaction? = try journal.begin(title: "Conflict")
        let id = transaction!.id
        XCTAssertThrowsError(try journal.acknowledge(id))
        try transaction!.move(a, to: b); transaction = nil
        try Data("new occupant".utf8).write(to: a)
        XCTAssertFalse(try journal.recover(id).resolved)
        try journal.acknowledge(id)
        XCTAssertTrue(try journal.summaries().isEmpty)
        XCTAssertEqual(try String(contentsOf: a), "new occupant"); XCTAssertEqual(try String(contentsOf: b), "original")
        XCTAssertTrue(try journal.recover(id).resolved)
    }
}
