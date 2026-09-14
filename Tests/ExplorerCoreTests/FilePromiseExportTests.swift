import XCTest
@testable import ExplorerCore

final class FilePromiseExportTests: XCTestCase {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testLazyExportPreservesSourceAndMetadata() throws {
        let root = try fixture(), source = root.appendingPathComponent("source.txt"), target = root.appendingPathComponent("result.txt")
        try Data("promised content".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        let request = try FilePromiseExport(source: source)
        XCTAssertFalse(FileNames.exists(target))
        try request.write(to: target)
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: target))
        XCTAssertTrue(request.expected.matches(source))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue, 0o640)
    }
    func testOccupiedDestinationIsNeverReplaced() throws {
        let root = try fixture(), source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try Data("source".utf8).write(to: source); try Data("existing".utf8).write(to: target)
        XCTAssertThrowsError(try FilePromiseExport(source: source).write(to: target))
        XCTAssertEqual(try String(contentsOf: target), "existing")
    }
    func testChangedSourceInvalidatesPendingPromise() throws {
        let root = try fixture(), source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try Data("original".utf8).write(to: source)
        let request = try FilePromiseExport(source: source)
        try Data("new external content".utf8).write(to: source)
        XCTAssertThrowsError(try request.write(to: target))
        XCTAssertFalse(FileNames.exists(target))
    }
    func testCancelledPromiseCreatesNoOutput() throws {
        let root = try fixture(), source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try Data("source".utf8).write(to: source)
        let request = try FilePromiseExport(source: source), control = OperationControl()
        control.cancel()
        XCTAssertThrowsError(try request.write(to: target, control: control)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(FileNames.exists(target)); XCTAssertTrue(FileNames.exists(source))
    }
    func testFolderPromiseCannotWriteInsideItsSource() throws {
        let root = try fixture(), request = try FilePromiseExport(source: root)
        XCTAssertThrowsError(try request.write(to: root.appendingPathComponent("recursive")))
        XCTAssertFalse(FileNames.exists(root.appendingPathComponent("recursive")))
    }
}
