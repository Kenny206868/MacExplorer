import XCTest
@testable import ExplorerCore

final class TransferProgressIntegrationTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorer-transfer-" + UUID().uuidString), destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("data"); try Data(repeating: 0x42, count: 1024 * 1024).write(to: source)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return (root, source, destination)
    }
    func testNativeCopyCompletesWithMatchingLogicalTotal() async throws {
        let (root, source, destination) = try fixture()
        let result = await FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")).run(FileJob(.copy, sources: [source], destination: destination), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertTrue(result.errors.isEmpty, result.errors.description); XCTAssertEqual(result.completedSources, [source])
        XCTAssertEqual(result.finalProgress?.completed, 1); XCTAssertEqual(result.finalProgress?.logicalBytes, 1024 * 1024); XCTAssertEqual(result.finalProgress?.totalBytes, 1024 * 1024)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("data")), try Data(contentsOf: source))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: destination.path).contains { $0.hasPrefix(".MacExplorer-stage-") })
    }
    func testCancellationNeverInstallsACompletedButUncommittedStage() async throws {
        let (root, source, destination) = try fixture(), control = OperationControl()
        let result = await FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")).run(FileJob(.copy, sources: [source], destination: destination), control: control, progress: { value in if value.logicalBytes > 0 { control.cancel() } }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertTrue(result.cancelled); XCTAssertTrue(result.completedSources.isEmpty)
        XCTAssertEqual(result.finalProgress?.completed, 0); XCTAssertEqual(result.finalProgress?.logicalBytes, 0)
        XCTAssertEqual(try Data(contentsOf: source).count, 1024 * 1024); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }
    func testChangedReplacementDestinationIsPreserved() async throws {
        let (root, source, destination) = try fixture(), target = destination.appendingPathComponent("data"); try Data("old".utf8).write(to: target)
        let result = await FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")).run(FileJob(.copy, sources: [source], destination: destination), control: OperationControl(), progress: { value in if value.logicalBytes > 0 { try? Data("newer external content".utf8).write(to: target) } }, resolve: { _ in CollisionAnswer(.replace) })
        XCTAssertFalse(result.errors.isEmpty); XCTAssertTrue(result.completedSources.isEmpty)
        XCTAssertEqual(try String(contentsOf: target), "newer external content"); XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["data"])
    }
    func testSkippedItemsAreNotReportedAsCompleted() async throws {
        let (root, source, destination) = try fixture(); try Data("existing".utf8).write(to: destination.appendingPathComponent("data"))
        let result = await FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")).run(FileJob(.copy, sources: [source], destination: destination), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.skip) })
        XCTAssertEqual(result.skippedSources, [source]); XCTAssertTrue(result.completedSources.isEmpty)
        XCTAssertEqual(result.finalProgress?.completed, 0); XCTAssertEqual(result.finalProgress?.logicalBytes, 0)
    }
}
