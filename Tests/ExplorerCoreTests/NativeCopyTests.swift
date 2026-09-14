import XCTest
import Darwin
@testable import ExplorerCore

final class NativeCopyTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorer-copy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func testCopyPreservesDataPermissionsDateAndExtendedAttributes() throws {
        let root = try fixture(), source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("copy")
        let content = Data(repeating: 0xAC, count: 2 * 1024 * 1024)
        try content.write(to: source)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o640, .modificationDate: date], ofItemAtPath: source.path)
        let attribute = Data("retained-metadata".utf8)
        let set = attribute.withUnsafeBytes { bytes in setxattr(source.path, "com.macexplorer.test", bytes.baseAddress, bytes.count, 0, 0) }
        XCTAssertEqual(set, 0)
        let result = try NativeFileCopy.copy(from: source, to: destination, control: OperationControl(), allowClone: false)
        XCTAssertEqual(try Data(contentsOf: destination), content)
        XCTAssertEqual(result.writtenBytes, Int64(content.count))
        let values = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((values[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        XCTAssertEqual(values[.modificationDate] as? Date, date)
        var actual = Data(count: attribute.count)
        let read = actual.withUnsafeMutableBytes { bytes in getxattr(destination.path, "com.macexplorer.test", bytes.baseAddress, bytes.count, 0, 0) }
        XCTAssertEqual(read, attribute.count); XCTAssertEqual(actual, attribute)
    }
    func testDirectoryCopyDoesNotFollowSymlinks() throws {
        let root = try fixture(), source = root.appendingPathComponent("tree"), destination = root.appendingPathComponent("result")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("payload".utf8).write(to: source.appendingPathComponent("file"))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("loop").path, withDestinationPath: ".")
        XCTAssertEqual(try TransferInventory.logicalBytes(source, control: OperationControl()), 7)
        let result = try NativeFileCopy.copy(from: source, to: destination, control: OperationControl())
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("loop").path), ".")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("file")), "payload")
        XCTAssertEqual(result.logicalBytes, 7)
    }
    func testExistingDestinationIsNeverReplacedOrRemoved() throws {
        let root = try fixture(), source = root.appendingPathComponent("new"), destination = root.appendingPathComponent("existing")
        try Data("new".utf8).write(to: source); try Data("original".utf8).write(to: destination)
        XCTAssertThrowsError(try NativeFileCopy.copy(from: source, to: destination, control: OperationControl()))
        XCTAssertEqual(try String(contentsOf: destination), "original")
    }
    func testCancellationDuringDataCopyRetainsSource() throws {
        let root = try fixture(), source = root.appendingPathComponent("large"), destination = root.appendingPathComponent("stage")
        try Data(repeating: 0x5A, count: 16 * 1024 * 1024).write(to: source)
        let control = OperationControl()
        XCTAssertThrowsError(try NativeFileCopy.copy(from: source, to: destination, control: control, allowClone: false) { sample in
            if sample.writtenBytes > 0 { control.cancel() }
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: source).count, 16 * 1024 * 1024)
        // The enclosing transaction owns cleanup of the private partial destination.
    }
    func testCancellationFromFinalProgressIsObservedBeforeReturning() throws {
        let root = try fixture(), source = root.appendingPathComponent("tiny"), destination = root.appendingPathComponent("stage")
        try Data("payload".utf8).write(to: source)
        let control = OperationControl()
        XCTAssertThrowsError(try NativeFileCopy.copy(from: source, to: destination, control: control) { sample in
            if sample.logicalBytes > 0 { control.cancel() }
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try String(contentsOf: source), "payload")
    }
    func testAlreadyCancelledDoesNotCreateDestination() throws {
        let root = try fixture(), source = root.appendingPathComponent("file"), destination = root.appendingPathComponent("copy")
        try Data().write(to: source)
        let control = OperationControl(); control.cancel()
        XCTAssertThrowsError(try NativeFileCopy.copy(from: source, to: destination, control: control))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
