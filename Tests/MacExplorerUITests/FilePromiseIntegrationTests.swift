import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class FilePromiseIntegrationTests: XCTestCase {
    /// AppKit metadata decoding and the exact background fulfillment method are
    /// tested independently from WindowServer's live cross-process drag transport.
    @MainActor func testNativePasteboardContractAndQueuedFulfillment() async throws {
        _ = NSApplication.shared
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("PromiseContract-" + UUID().uuidString)
        let incoming = root.appendingPathComponent("incoming")
        try manager.createDirectory(at: incoming, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let source = root.appendingPathComponent("promised.txt")
        let target = incoming.appendingPathComponent("promised.txt")
        try Data("native promise handshake".utf8).write(to: source)
        let provider = try ExplorerFilePromiseProvider.make(for: FileEntry(url: source))
        let board = NSPasteboard(name: NSPasteboard.Name("MacExplorer-test-" + UUID().uuidString))
        defer { board.releaseGlobally(); _ = provider }
        XCTAssertTrue(board.writeObjects([provider]))
        XCTAssertTrue(provider.writableTypes(for: board).contains(.fileURL))
        XCTAssertEqual(provider.pasteboardPropertyList(forType: .fileURL) as? String, source.absoluteString)
        let receivers = try XCTUnwrap(board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver])
        XCTAssertEqual(receivers.count, 1)
        XCTAssertFalse(try XCTUnwrap(receivers.first).fileTypes.isEmpty)
        let delegate = try XCTUnwrap(provider.userInfo as? ExplorerPromiseDelegate)
        XCTAssertEqual(delegate.filePromiseProvider(provider, fileNameForType: "public.plain-text"), "promised.txt")
        let finished = expectation(description: "Promise worker wrote the file")
        delegate.operationQueue(for: provider).addOperation {
            delegate.fulfill(to: target) { error in
                XCTAssertNil(error)
                XCTAssertEqual(try? String(contentsOf: target), "native promise handshake")
                finished.fulfill()
            }
        }
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertEqual(try String(contentsOf: source), "native promise handshake")
    }

    @MainActor func testIncomingCompletionKeepsOriginalFolderAndUndoAfterTabSwitch() async throws {
        let fixture = try ImportFixture(); defer { fixture.cleanup() }
        let source = ControlledPromiseSource()
        let origin = fixture.workspace.current
        let row = try XCTUnwrap(fixture.inbox.enqueue([source], into: fixture.destination, owner: fixture.workspace))
        fixture.workspace.newTab(.folder(fixture.otherFolder))
        _ = try source.complete()
        try await waitUntil { row.finished && fixture.inbox.activeCount == 0 }
        XCTAssertTrue(row.errors.isEmpty, row.errors.description)
        XCTAssertEqual(try String(contentsOf: fixture.destination.appendingPathComponent("delivered.txt")), "received content")
        XCTAssertFalse(FileNames.exists(fixture.otherFolder.appendingPathComponent("delivered.txt")))
        XCTAssertTrue(origin !== fixture.workspace.current)
        let receipt = try XCTUnwrap(fixture.center.undoStack.last)
        XCTAssertEqual(receipt.steps.count, 1)
        XCTAssertEqual(receipt.steps.first?.kind, .trash)
        XCTAssertEqual(receipt.steps.first?.source.path, fixture.destination.appendingPathComponent("delivered.txt").path)
    }

    @MainActor func testCancelledIncomingPromiseCannotInstallItsLateFile() async throws {
        let fixture = try ImportFixture(); defer { fixture.cleanup() }
        let source = ControlledPromiseSource()
        let row = try XCTUnwrap(fixture.inbox.enqueue([source], into: fixture.destination, owner: fixture.workspace))
        row.cancel()
        _ = try source.complete()
        try await waitUntil { fixture.inbox.activeCount == 0 }
        XCTAssertTrue(row.cancelled)
        XCTAssertTrue(fixture.center.undoStack.isEmpty)
        XCTAssertFalse(FileNames.exists(fixture.destination.appendingPathComponent("delivered.txt")))
    }

    @MainActor func testReplacedDestinationRetainsReceivedOriginalWithoutWritingReplacement() async throws {
        let fixture = try ImportFixture(); defer { fixture.cleanup() }
        let source = ControlledPromiseSource()
        let row = try XCTUnwrap(fixture.inbox.enqueue([source], into: fixture.destination, owner: fixture.workspace))
        try FileManager.default.moveItem(at: fixture.destination, to: fixture.root.appendingPathComponent("old-folder"))
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: false)
        let received = try source.complete()
        defer { if let directory = source.directory { try? FileManager.default.removeItem(at: directory) } }
        try await waitUntil { row.finished && fixture.inbox.activeCount == 0 }
        XCTAssertFalse(row.errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: received), "received content")
        XCTAssertFalse(FileNames.exists(fixture.destination.appendingPathComponent("delivered.txt")))
        XCTAssertTrue(fixture.center.undoStack.isEmpty)
    }

    @MainActor func testUnfinishedProviderTimeoutRetainsInboxAndReleasesBatch() async throws {
        let fixture = try ImportFixture(); defer { fixture.cleanup() }
        let source = ControlledPromiseSource()
        let row = try XCTUnwrap(fixture.inbox.enqueue([source], into: fixture.destination, owner: fixture.workspace, timeout: .milliseconds(75)))
        let directory = try XCTUnwrap(source.directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await waitUntil { row.finished && fixture.inbox.activeCount == 0 }
        XCTAssertTrue(row.cancelled)
        XCTAssertTrue(FileNames.exists(directory), "Never remove an inbox while an external application might still write it")
        XCTAssertTrue(row.errors.contains { $0.contains(directory.path) })
        XCTAssertTrue(fixture.center.undoStack.isEmpty)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Asynchronous import did not reach its terminal state")
    }
}

@MainActor private final class ControlledPromiseSource: PromisedFileSource {
    var expectedCount: Int { 1 }
    private(set) var directory: URL?
    private var completion: (@Sendable (URL, String?) -> Void)?
    func receive(into directory: URL, queue: OperationQueue, completion: @escaping @Sendable (URL, String?) -> Void) {
        self.directory = directory; self.completion = completion
    }
    func complete() throws -> URL {
        let file = try XCTUnwrap(directory).appendingPathComponent("delivered.txt")
        try Data("received content".utf8).write(to: file)
        let callback = completion; completion = nil; callback?(file, nil)
        return file
    }
}

@MainActor private final class ImportFixture {
    let root: URL
    let destination: URL
    let otherFolder: URL
    let center = OperationCenter()
    let inbox: FilePromiseInbox
    let workspace: ExplorerWorkspace
    private let oldPreferences = PreferenceStore.shared.value
    private let oldData = UserDefaults.standard.data(forKey: "MacExplorer.preferences.v1")
    init() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent("InboxTests-" + UUID().uuidString)
        destination = root.appendingPathComponent("destination")
        otherFolder = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: false)
        inbox = FilePromiseInbox(engine: FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")), center: center)
        workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(destination)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop()
    }
    func cleanup() {
        workspace.tabs.forEach { $0.stop() }
        PreferenceStore.shared.value = oldPreferences
        if let oldData { UserDefaults.standard.set(oldData, forKey: "MacExplorer.preferences.v1") }
        else { UserDefaults.standard.removeObject(forKey: "MacExplorer.preferences.v1") }
        try? FileManager.default.removeItem(at: root)
    }
}
