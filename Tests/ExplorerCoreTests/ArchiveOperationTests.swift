import XCTest
@testable import ExplorerCore

final class ArchiveOperationTests: XCTestCase {
    func testEncryptedExtractionUsesQueueAndPasswordFreeRecoveryReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveOperation-" + UUID().uuidString)
        let output = root.appendingPathComponent("output")
        let receipts = root.appendingPathComponent("receipts")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("encrypted.zip")
        try XCTUnwrap(Data(base64Encoded: ArchiveCatalogTests.encrypted)).write(to: archive)
        let engine = FileOperationEngine(recoveryDirectory: receipts)
        let job = FileJob(.extract, sources: [archive], destination: output, archiveOptions: ArchiveReadOptions(passphrase: "fixture-password"))
        let result = await engine.run(job, control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertTrue(result.errors.isEmpty, result.errors.description)
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertEqual(result.receipt.steps.count, 1)
        XCTAssertEqual(result.receipt.steps.first?.kind, .trash)
        let json = try JSONEncoder().encode(result.receipt)
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("fixture-password"))
        let history = await engine.history()
        XCTAssertEqual(history.count, 1)
        for file in try FileManager.default.contentsOfDirectory(at: receipts, includingPropertiesForKeys: nil) {
            XCTAssertFalse(try String(contentsOf: file).contains("fixture-password"))
        }
    }
}
