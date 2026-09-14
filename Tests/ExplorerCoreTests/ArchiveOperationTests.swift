import XCTest
@testable import ExplorerCore

final class ArchiveOperationTests: XCTestCase {
    func testEncryptedExtractionUsesQueueAndPasswordFreeRecoveryReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveOperation-" + UUID().uuidString), output = root.appendingPathComponent("output"), receipts = root.appendingPathComponent("receipts")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("encrypted.zip"); try XCTUnwrap(Data(base64Encoded: ArchiveCatalogTests.encrypted)).write(to: archive)
        let engine = FileOperationEngine(recoveryDirectory: receipts)
        let result = await engine.run(FileJob(.extract, sources: [archive], destination: output, archiveOptions: ArchiveReadOptions(passphrase: "fixture-password")), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertTrue(result.errors.isEmpty, result.errors.description); XCTAssertEqual(result.outputs.count, 1); XCTAssertEqual(result.receipt.steps.count, 1)
        XCTAssertEqual(result.receipt.steps.first?.kind, .trash)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(result.receipt), as: UTF8.self).contains("fixture-password"))
        let history = await engine.history(); XCTAssertEqual(history.count, 1)
        let paths = try XCTUnwrap(FileManager.default.enumerator(at: receipts, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let file as URL in paths where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            XCTAssertNil(try Data(contentsOf: file).range(of: Data("fixture-password".utf8)), "Passwords must not enter the durable journal")
        }
    }
}
