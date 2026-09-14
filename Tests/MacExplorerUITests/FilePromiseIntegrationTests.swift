import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class FilePromiseIntegrationTests: XCTestCase {
    @MainActor func testPasteboardPromiseRoundTrip() async throws {
        _ = NSApplication.shared
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("PromiseRoundTrip-" + UUID().uuidString)
        let incoming = root.appendingPathComponent("incoming")
        try manager.createDirectory(at: incoming, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let source = root.appendingPathComponent("promised.txt")
        try Data("native promise handshake".utf8).write(to: source)
        let provider = try ExplorerFilePromiseProvider.make(for: FileEntry(url: source))
        let board = NSPasteboard(name: NSPasteboard.Name("MacExplorer-test-" + UUID().uuidString))
        defer { board.releaseGlobally(); _ = provider }
        XCTAssertTrue(board.writeObjects([provider]))
        XCTAssertTrue(provider.writableTypes(for: board).contains(.fileURL))
        XCTAssertEqual(provider.pasteboardPropertyList(forType: .fileURL) as? String, source.absoluteString)
        let receivers = try XCTUnwrap(board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver])
        XCTAssertEqual(receivers.count, 1)
        let finished = expectation(description: "AppKit fulfilled the promise")
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: incoming, options: [:], operationQueue: queue) { url, error in
                XCTAssertNil(error)
                XCTAssertEqual(url.lastPathComponent, "promised.txt")
                XCTAssertEqual(try? String(contentsOf: url), "native promise handshake")
                finished.fulfill()
            }
        }
        await fulfillment(of: [finished], timeout: 15)
        XCTAssertEqual(try String(contentsOf: source), "native promise handshake")
    }
}
