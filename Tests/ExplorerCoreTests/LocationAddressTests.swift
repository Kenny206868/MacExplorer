import XCTest
@testable import ExplorerCore

final class LocationAddressTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/Example")
    private let base = URL(fileURLWithPath: "/Users/Example/Projects")
    func testLexicalPathsAndFileURLsDoNotEvaluateCommands() throws {
        for (text, path) in [("..", "/Users/Example"), ("~/Documents", "/Users/Example/Documents"),
                             ("\"/Volumes/Work Space\"", "/Volumes/Work Space"),
                             ("file:///tmp/Za%C5%BC%C3%B3%C5%82%C4%87%20g%C4%99%C5%9Bl%C4%85", "/tmp/Zażółć gęślą"),
                             ("literal%20name", base.path + "/literal%20name"),
                             ("$(touch hacked)", base.path + "/$(touch hacked)")] {
            guard case .file(let actual) = try LocationAddress.parse(text, relativeTo: base, home: home) else { return XCTFail(text) }
            XCTAssertEqual(actual.path, path, text)
        }
        XCTAssertEqual(try LocationAddress.parse("~", relativeTo: base, home: home), .file(home))
    }
    func testUnsafeAndAmbiguousURLInputsAreRejected() {
        for text in ["", "\"\"", "~anotherUser", "a\0b", "a\nb", "file://remote/tmp", "file:///tmp/a?x=1",
                     "file:///tmp/a#fragment", "file:///tmp/%00bad", "https://user:secret@example.org", "javascript://host/code"] {
            XCTAssertThrowsError(try LocationAddress.parse(text, relativeTo: base, home: home), text)
        }
        XCTAssertNoThrow(try LocationAddress.parse("smb://server/share", relativeTo: base, home: home))
    }
    func testCompletionIsShallowAndOnlyProposesBrowsableFolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Paths-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["Documents", "Downloads", "Other/Deep", ".private"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("Document.txt"))
        let service = PathAddressService()
        let result = try await service.suggestions("Do", base: root, home: root, showHidden: false)
        XCTAssertTrue(result.items.allSatisfy { ["Documents", "Downloads"].contains($0.title) })
        if !result.truncated { XCTAssertEqual(result.items.map(\.title), ["Documents", "Downloads"]) }
        let all = try await service.suggestions(root.path + "/", base: root, home: root, showHidden: false)
        XCTAssertTrue(all.items.allSatisfy { ["Documents", "Downloads", "Other"].contains($0.title) })
        if !all.truncated { XCTAssertEqual(Set(all.items.map(\.title)), ["Documents", "Downloads", "Other"]) }
        let hidden = try await service.suggestions(".", base: root, home: root, showHidden: true)
        XCTAssertTrue(hidden.items.allSatisfy { $0.title == ".private" })
        if !hidden.truncated { XCTAssertEqual(hidden.items.map(\.title), [".private"]) }
        guard case .folder(let directory) = try await service.resolve("Documents", base: root, home: root) else { return XCTFail("Not a folder") }
        XCTAssertEqual(directory.path, root.appendingPathComponent("Documents").path)
        guard case .file(let file) = try await service.resolve("Document.txt", base: root, home: root) else { return XCTFail("Not a file") }
        XCTAssertEqual(file.path, root.appendingPathComponent("Document.txt").path)
    }
    func testCompletingDoesNotWalkIntoGrandchildrenAndHasBoundedOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Paths-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<25 { try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder\(i)/Nested"), withIntermediateDirectories: true) }
        let result = try await PathAddressService().suggestions("Folder", base: root, home: root, showHidden: false)
        // Twelve is an upper bound, not a minimum. A cold/busy filesystem may
        // reach the scan time budget first and must report truncation honestly.
        XCTAssertLessThanOrEqual(result.items.count, 12); XCTAssertTrue(result.truncated)
        XCTAssertEqual(Set(result.items.map(\.id)).count, result.items.count)
        XCTAssertTrue(result.items.allSatisfy { $0.url.deletingLastPathComponent().path == root.path && $0.title.hasPrefix("Folder") })
    }
}
