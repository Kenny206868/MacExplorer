import XCTest
@testable import ExplorerCore

final class FileDisplayTextTests: XCTestCase {
    func testSmallFileSizeAndKindRemainReadableWithoutChangingMetadata() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try Data("test".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let entry = try FileEntry(url: file)
        XCTAssertEqual(entry.compactSizeText, "4 B")
        XCTAssertEqual(entry.conciseKind, "Markdown")
        XCTAssertEqual(entry.size, 4)
        XCTAssertFalse(entry.kind.isEmpty)
    }
}
