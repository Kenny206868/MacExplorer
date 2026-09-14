import XCTest
@testable import ExplorerCore

final class DirectoryMergeTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let source: URL
        let destination: URL
        let engine: FileOperationEngine
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorer-Merge-" + UUID().uuidString)
            source = root.appendingPathComponent("from/Project")
            destination = root.appendingPathComponent("to/Project")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts"))
        }
        func write(_ name: String, _ value: String, into directory: URL) throws {
            let url = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: url)
        }
        func read(_ name: String, from directory: URL) throws -> String {
            try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
        func run(_ kind: FileJobKind, control: OperationControl = OperationControl(), leaf: CollisionChoice = .keepBoth) async -> FileJobResult {
            await engine.run(FileJob(kind, sources: [source], destination: destination.deletingLastPathComponent()), control: control, progress: { _ in }) { collision in
                CollisionAnswer(collision.canMerge ? .merge : leaf)
            }
        }
    }
    func testCopyMergePreservesBothTreesAndDistinctNestedItems() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("nested/source.txt", "source", into: f.source)
        try f.write("nested/destination.txt", "destination", into: f.destination)
        let before = try FileFingerprint(f.destination)
        let result = await f.run(.copy)
        XCTAssertTrue(result.errors.isEmpty, result.errors.description)
        XCTAssertEqual(result.completedSources.map(\.standardizedFileURL.path), [f.source.standardizedFileURL.path])
        XCTAssertTrue(before.matchesIdentity(f.destination))
        XCTAssertEqual(try f.read("nested/source.txt", from: f.source), "source")
        XCTAssertEqual(try f.read("nested/source.txt", from: f.destination), "source")
        XCTAssertEqual(try f.read("nested/destination.txt", from: f.destination), "destination")
        XCTAssertEqual(result.finalProgress?.logicalBytes, 6)
        let history = await f.engine.history()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.steps.count, result.receipt.steps.count)
    }
    func testMoveMergeUndoRedoPreservesContainersAndDestinationOnlyContent() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("nested/from.txt", "source", into: f.source)
        try f.write("nested/to.txt", "untouched", into: f.destination)
        try f.write("top.txt", "top", into: f.source)
        let sourceIdentity = try FileFingerprint(f.source)
        let nestedIdentity = try FileFingerprint(f.source.appendingPathComponent("nested"))
        let result = await f.run(.move)
        XCTAssertTrue(result.errors.isEmpty, result.errors.description)
        XCTAssertFalse(FileNames.exists(f.source))
        XCTAssertEqual(result.completedSources.map(\.standardizedFileURL.path), [f.source.standardizedFileURL.path])
        XCTAssertEqual(result.receipt.steps.filter { $0.emptyDirectory == true }.count, 2)
        let undone = await f.engine.undo(result.receipt, control: OperationControl())
        XCTAssertTrue(undone.errors.isEmpty, undone.errors.description)
        XCTAssertTrue(sourceIdentity.matchesIdentity(f.source))
        XCTAssertTrue(nestedIdentity.matchesIdentity(f.source.appendingPathComponent("nested")))
        XCTAssertEqual(try f.read("nested/from.txt", from: f.source), "source")
        XCTAssertEqual(try f.read("nested/to.txt", from: f.destination), "untouched")
        XCTAssertFalse(FileNames.exists(f.destination.appendingPathComponent("top.txt")))
        let redone = await f.engine.undo(undone.receipt, control: OperationControl())
        XCTAssertTrue(redone.errors.isEmpty, redone.errors.description)
        XCTAssertFalse(FileNames.exists(f.source))
        XCTAssertEqual(try f.read("top.txt", from: f.destination), "top")
        XCTAssertEqual(try f.read("nested/to.txt", from: f.destination), "untouched")
    }
    func testLeafReplacementBackupIsRestoredByMergeUndo() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("same.txt", "new", into: f.source)
        try f.write("same.txt", "old", into: f.destination)
        let result = await f.run(.move, leaf: .replace)
        XCTAssertTrue(result.errors.isEmpty, result.errors.description)
        XCTAssertEqual(try f.read("same.txt", from: f.destination), "new")
        let undo = await f.engine.undo(result.receipt, control: OperationControl())
        XCTAssertTrue(undo.errors.isEmpty, undo.errors.description)
        XCTAssertEqual(try f.read("same.txt", from: f.source), "new")
        XCTAssertEqual(try f.read("same.txt", from: f.destination), "old")
    }
    func testSkippedConflictRetainsSourceAndCanUndoCompletedChildren() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("a.txt", "moved", into: f.source)
        try f.write("z.txt", "keep source", into: f.source)
        try f.write("z.txt", "keep target", into: f.destination)
        let result = await f.run(.move, leaf: .skip)
        XCTAssertTrue(result.errors.isEmpty, result.errors.description)
        XCTAssertTrue(result.completedSources.isEmpty)
        XCTAssertEqual(result.skippedSources.map(\.standardizedFileURL.path), [f.source.standardizedFileURL.path])
        XCTAssertEqual(try f.read("z.txt", from: f.source), "keep source")
        XCTAssertEqual(try f.read("z.txt", from: f.destination), "keep target")
        let undo = await f.engine.undo(result.receipt, control: OperationControl())
        XCTAssertTrue(undo.errors.isEmpty, undo.errors.description)
        XCTAssertEqual(try f.read("a.txt", from: f.source), "moved")
    }
    func testCancellationRetainsDurableCompletedStepAndDoesNotConsumeRoot() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("a.txt", "moved", into: f.source)
        try f.write("z.txt", "keep source", into: f.source)
        try f.write("z.txt", "keep target", into: f.destination)
        let result = await f.run(.move, leaf: .cancel)
        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(result.completedSources.isEmpty)
        XCTAssertEqual(result.receipt.steps.count, 1)
        let history = await f.engine.history()
        XCTAssertEqual(history.first?.steps.count, 1)
        XCTAssertEqual(try f.read("a.txt", from: f.destination), "moved")
        XCTAssertEqual(try f.read("z.txt", from: f.source), "keep source")
    }
    func testSymlinkAndOverlappingFoldersCannotBeMergeRoots() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let link = f.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.destination)
        XCTAssertFalse(FileCollision(source: f.source, destination: link).canMerge)
        XCTAssertFalse(FileCollision(source: f.source, destination: f.source).canMerge)
        let nested = f.source.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        XCTAssertFalse(FileCollision(source: f.source, destination: nested).canMerge)
        XCTAssertFalse(FileCollision(source: nested, destination: f.source).canMerge)
    }
    func testUndoWillNotMoveEmptyContainerAfterExternalInsertion() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("a.txt", "source", into: f.source)
        let result = await f.run(.move)
        let container = try XCTUnwrap(result.receipt.steps.first(where: { $0.emptyDirectory == true }))
        try f.write("foreign.txt", "foreign", into: container.source)
        let undo = await f.engine.undo(result.receipt, control: OperationControl())
        XCTAssertFalse(undo.errors.isEmpty)
        XCTAssertEqual(undo.remaining.count, result.receipt.steps.count)
        XCTAssertEqual(try f.read("foreign.txt", from: container.source), "foreign")
        XCTAssertEqual(try f.read("a.txt", from: f.destination), "source")
    }
    func testParentReplacementDuringCollisionDecisionStopsFurtherWrites() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("same.txt", "source", into: f.source)
        try f.write("same.txt", "target", into: f.destination)
        let result = await f.engine.run(FileJob(.move, sources: [f.source], destination: f.destination.deletingLastPathComponent()), control: OperationControl(), progress: { _ in }) { collision in
            if collision.canMerge { return CollisionAnswer(.merge) }
            let displaced = f.root.appendingPathComponent("displaced")
            try? FileManager.default.moveItem(at: f.destination, to: displaced)
            try? FileManager.default.createDirectory(at: f.destination, withIntermediateDirectories: false)
            return CollisionAnswer(.replace)
        }
        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertTrue(result.receipt.steps.isEmpty)
        XCTAssertEqual(try f.read("same.txt", from: f.source), "source")
        XCTAssertEqual(try f.read("same.txt", from: f.root.appendingPathComponent("displaced")), "target")
        XCTAssertFalse(FileNames.exists(f.destination.appendingPathComponent("same.txt")))
    }
}
