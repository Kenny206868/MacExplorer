import XCTest
@testable import ExplorerCore

final class PromisedImportFileTests: XCTestCase {
    func testOnlyCompletedChildrenOfTheOriginalInboxAreAccepted() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inbox = root.appendingPathComponent("inbox")
        try manager.createDirectory(at: inbox, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let identity = try FileFingerprint(inbox)
        let file = inbox.appendingPathComponent("good.txt"), outside = root.appendingPathComponent("outside.txt")
        try Data("good".utf8).write(to: file); try Data("outside".utf8).write(to: outside)
        XCTAssertNoThrow(try PromisedImportFile.validate(file, in: inbox, expectedInbox: identity))
        XCTAssertThrowsError(try PromisedImportFile.validate(outside, in: inbox, expectedInbox: identity))
        let link = inbox.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try PromisedImportFile.validate(link, in: inbox, expectedInbox: identity))
        XCTAssertThrowsError(try PromisedImportFile.validate(inbox, in: inbox, expectedInbox: identity))
        XCTAssertThrowsError(try PromisedImportFile.validate(inbox.appendingPathComponent("missing"), in: inbox, expectedInbox: identity))
        try manager.moveItem(at: inbox, to: root.appendingPathComponent("original-inbox"))
        try manager.createDirectory(at: inbox, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: file)
        XCTAssertThrowsError(try PromisedImportFile.validate(file, in: inbox, expectedInbox: identity))
    }
}
