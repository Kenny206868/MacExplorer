import XCTest
import ExplorerCore
@testable import MacExplorer

final class TransferPreparationTests: XCTestCase {
    @MainActor func testBlockedMetadataLaneDoesNotBlockInputAndRejectsStaleSelection() async throws {
        let fixture = try CommanderFixture(), lane = FileReadExecutor(name: "test-transfer", concurrency: 1)
        let gate = DispatchSemaphore(value: 0), entered = expectation(description: "metadata lane blocked")
        let blocker = Task { try await lane.run { _ in entered.fulfill(); gate.wait() } }
        await fulfillment(of: [entered], timeout: 3)
        let dual = DualPaneController(primary: fixture.owner, transferReads: lane); fixture.owner.dualPane = dual
        dual.secondary.current.stop(); dual.secondary.current.history = NavigationHistory(.folder(fixture.root))
        defer { gate.signal(); blocker.cancel(); fixture.close() }
        fixture.owner.current.selection = [fixture.files[0].url]
        dual.requestTransfer(from: fixture.owner, move: true)
        XCTAssertTrue(dual.preparingTransfer)
        fixture.owner.current.selection = [fixture.files[1].url] // immediate main-actor input remains possible
        gate.signal(); _ = try await blocker.value
        try await until { !dual.preparingTransfer }
        XCTAssertNil(fixture.owner.pendingPaneTransfer); XCTAssertNotNil(dual.transferNotice)
        XCTAssertEqual(fixture.owner.current.selection, [fixture.files[1].url])
        XCTAssertTrue(FileNames.exists(fixture.files[0].url))
    }
    @MainActor func testCancelPreparationCannotPublishLateConfirmation() async throws {
        let fixture = try CommanderFixture(), lane = FileReadExecutor(name: "cancel-transfer", concurrency: 1)
        let gate = DispatchSemaphore(value: 0), entered = expectation(description: "metadata lane blocked")
        let blocker = Task { try await lane.run { _ in entered.fulfill(); gate.wait() } }
        await fulfillment(of: [entered], timeout: 3)
        let dual = DualPaneController(primary: fixture.owner, transferReads: lane); fixture.owner.dualPane = dual
        dual.secondary.current.stop(); dual.secondary.current.history = NavigationHistory(.folder(fixture.root))
        defer { gate.signal(); blocker.cancel(); fixture.close() }
        fixture.owner.current.selection = [fixture.files[0].url]
        dual.requestTransfer(from: fixture.owner, move: true); XCTAssertTrue(dual.preparingTransfer)
        dual.cancelTransferPreparation(); XCTAssertFalse(dual.preparingTransfer)
        gate.signal(); _ = try await blocker.value
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(fixture.owner.pendingPaneTransfer)
        XCTAssertTrue(dual.transferNotice?.contains("cancelled") == true)
    }
    @MainActor func testPreparedMoveStillRequiresConfirmationAndCapturesItsSource() async throws {
        let fixture = try CommanderFixture(); defer { fixture.close() }
        let dual = DualPaneController(primary: fixture.owner); fixture.owner.dualPane = dual
        dual.secondary.current.stop(); dual.secondary.current.history = NavigationHistory(.folder(fixture.root))
        fixture.owner.current.selection = [fixture.files[0].url]
        dual.requestTransfer(from: fixture.owner, move: true)
        try await until { !dual.preparingTransfer }
        let request = try XCTUnwrap(fixture.owner.pendingPaneTransfer)
        XCTAssertEqual(request.job.sources.first?.path, fixture.files[0].url.path)
        XCTAssertTrue(FileNames.exists(fixture.files[0].url))
        let snapshot = request.snapshot
        try await FileReadExecutor.metadata.run { try snapshot.validate($0) }
        fixture.owner.pendingPaneTransfer = nil
    }
    @MainActor private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Transfer preparation did not settle")
    }
}
