import XCTest
@testable import ExplorerCore

final class InteractionIntegrationTests: XCTestCase {
    func testCompletedSourcesDescribeOnlySuccessfulMoves() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("sample.txt")
        try Data("content".utf8).write(to: source)
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let cancelled = OperationControl(); cancelled.cancel()
        let skipped = await FileOperationEngine().run(FileJob(.move, sources: [source], destination: destination), control: cancelled, progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertTrue(skipped.completedSources.isEmpty)
        XCTAssertTrue(FileNames.exists(source))
        let moved = await FileOperationEngine().run(FileJob(.move, sources: [source], destination: destination), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertEqual(moved.completedSources, [source])
        XCTAssertTrue(moved.errors.isEmpty)
    }
    func testRenameCycleUndoAndRedo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = ["a", "b", "c"].map { root.appendingPathComponent($0) }
        for (index, url) in urls.enumerated() { try Data("\(index)".utf8).write(to: url) }
        let engine = FileOperationEngine()
        let renamed = await engine.rename([(urls[0], "b"), (urls[1], "c"), (urls[2], "a")], control: OperationControl())
        XCTAssertTrue(renamed.errors.isEmpty)
        XCTAssertEqual(renamed.receipt.renameBatch, true)
        let undo = await engine.undo(renamed.receipt, control: OperationControl())
        XCTAssertTrue(undo.errors.isEmpty, undo.errors.joined(separator: "\n"))
        for (index, url) in urls.enumerated() { XCTAssertEqual(try String(contentsOf: url), "\(index)") }
        let redo = await engine.undo(undo.receipt, control: OperationControl())
        XCTAssertTrue(redo.errors.isEmpty, redo.errors.joined(separator: "\n"))
        XCTAssertEqual(try String(contentsOf: urls[0]), "2")
        XCTAssertEqual(try String(contentsOf: urls[1]), "0")
        XCTAssertEqual(try String(contentsOf: urls[2]), "1")
    }
}
