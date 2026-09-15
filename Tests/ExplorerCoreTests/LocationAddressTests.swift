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
                             ("$(touch hacked)", base.path + "/$(touch hacked)"),
                             ("/private/var/../tmp/./literal", "/private/tmp/literal"),
                             ("/../../", "/")] {
            guard case .file(let actual) = try LocationAddress.parse(text, relativeTo: base, home: home) else { return XCTFail(text) }
            XCTAssertEqual(actual.path, path, text)
        }
        XCTAssertEqual(try LocationAddress.parse("~", relativeTo: base, home: home), .file(home))
    }

    func testUnsafeAndAmbiguousURLInputsAreRejected() {
        for text in ["", "\"\"", "~anotherUser", "a\0b", "a\nb", "\n/tmp", "/tmp\t", "file://remote/tmp", "file:///tmp/a?x=1",
                     "file:///tmp/a#fragment", "file:///tmp/%00bad", "https://user:secret@example.org", "javascript://host/code"] {
            XCTAssertThrowsError(try LocationAddress.parse(text, relativeTo: base, home: home), text)
        }
        XCTAssertNoThrow(try LocationAddress.parse("smb://server/share", relativeTo: base, home: home))
    }

    func testCompletionIsShallowAndOnlyProposesBrowsableFolders() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["Documents", "Downloads", "Other/Deep", ".private"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("Document.txt"))
        let service = deterministicService()
        let result = try await service.suggestions("Do", base: root, home: root, showHidden: false)
        XCTAssertEqual(result.items.map(\.title), ["Documents", "Downloads"]); XCTAssertFalse(result.truncated)
        let all = try await service.suggestions(root.path + "/", base: root, home: root, showHidden: false)
        XCTAssertEqual(Set(all.items.map(\.title)), ["Documents", "Downloads", "Other"])
        let quoted = try await service.suggestions("\"" + root.path + "/\"", base: root, home: root, showHidden: false)
        XCTAssertEqual(quoted.items, all.items, "Quoted trailing separators must still complete inside that folder")
        let hidden = try await service.suggestions(".", base: root, home: root, showHidden: true)
        XCTAssertEqual(hidden.items.map(\.title), [".private"])
        guard case .folder(let directory) = try await service.resolve("Documents", base: root, home: root) else { return XCTFail("Not a folder") }
        XCTAssertEqual(physicalPath(directory), physicalPath(root.appendingPathComponent("Documents")))
        guard case .file(let file) = try await service.resolve("Document.txt", base: root, home: root) else { return XCTFail("Not a file") }
        XCTAssertEqual(physicalPath(file), physicalPath(root.appendingPathComponent("Document.txt")))
    }

    func testCompletingDoesNotWalkIntoGrandchildrenAndHasBoundedOutput() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<25 { try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder\(i)/Nested"), withIntermediateDirectories: true) }
        let result = try await deterministicService().suggestions("Folder", base: root, home: root, showHidden: false)
        XCTAssertEqual(result.items.count, 12, "The output cap is independent of CPU scheduling")
        XCTAssertTrue(result.truncated, "Twenty-five matching children exceed the twelve-suggestion cap")
        XCTAssertEqual(Set(result.items.map(\.id)).count, result.items.count)
        for item in result.items {
            XCTAssertEqual(physicalPath(item.url.deletingLastPathComponent()), physicalPath(root), "Suggested grandchild or unrelated folder: \(item.url.path)")
            XCTAssertTrue(item.title.hasPrefix("Folder"), "Unexpected suggestion: \(item.title)")
        }
        for service in [deterministicService(scanLimit: 4), deterministicService(folderLimit: 4)] {
            let partial = try await service.suggestions(root.path + "/", base: root, home: root, showHidden: false)
            XCTAssertTrue(partial.truncated, "A deterministic four-entry budget must report a partial listing")
            XCTAssertEqual(partial.items.count, 4)
        }
        let empty = try await deterministicService().suggestions("", base: root, home: root, showHidden: false)
        XCTAssertTrue(empty.items.isEmpty); XCTAssertFalse(empty.truncated)
    }

    func testExpiredTimeBudgetReportsTruncationWithoutDependingOnRunnerSpeed() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: false)
        let clock = TickClock()
        let service = PathAddressService(scanLimit: 4096, folderLimit: 512, scanTimeBudget: 0.15, clock: { clock.next() })
        let result = try await service.suggestions(root.path + "/", base: root, home: root, showHidden: false)
        XCTAssertTrue(result.truncated, "Deadline expiry must not masquerade as a complete empty folder")
        XCTAssertTrue(result.items.isEmpty)
    }

    func testLogicalParentNormalizationDoesNotFollowFilesystemAliases() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("physical/deeper"), link = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        guard case .file(let path) = try LocationAddress.parse("alias/../sibling", relativeTo: root, home: root) else { return XCTFail("Not a path") }
        XCTAssertEqual(path.path, root.appendingPathComponent("sibling").path, "Parsing has logical, not realpath, parent semantics")
    }

    private func deterministicService(scanLimit: Int = 4096, folderLimit: Int = 512) -> PathAddressService {
        PathAddressService(scanLimit: scanLimit, folderLimit: folderLimit, scanTimeBudget: 0.15, clock: { 0 })
    }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Paths-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    // Filesystem assertions compare physical fixture identities. Lexical spelling
    // (including /private aliases) is covered separately by parser assertions.
    private func physicalPath(_ url: URL) -> String { url.resolvingSymlinksInPath().path }
    private final class TickClock: @unchecked Sendable {
        private let lock = NSLock()
        private var time: TimeInterval = 0
        func next() -> TimeInterval { lock.lock(); defer { lock.unlock() }; let value = time; time += 1; return value }
    }
}
