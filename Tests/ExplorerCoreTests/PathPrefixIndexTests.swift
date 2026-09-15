import XCTest
@testable import ExplorerCore

final class PathPrefixIndexTests: XCTestCase {
    func testComponentsNotStringPrefixesAndIncludingEquality() {
        var index = PathPrefixIndex(); index.insert(["/", "Projects", "App"])
        XCTAssertTrue(index.containsAncestor(of: ["/", "Projects", "App"]))
        XCTAssertTrue(index.containsAncestor(of: ["/", "Projects", "App", "main.swift"]))
        XCTAssertFalse(index.containsAncestor(of: ["/", "Projects", "App2"]))
        XCTAssertFalse(index.containsAncestor(of: ["/", "Projects"]))
        index.insert(["/", "Projects"])
        XCTAssertTrue(index.containsAncestor(of: ["/", "Projects", "App2"]))
    }
    func testFiftyThousandSiblingsUseLinearNodeStorage() {
        var index = PathPrefixIndex()
        for number in 0..<50_000 { index.insert(["/", "Projects", "Assets", String(number)]) }
        XCTAssertEqual(index.nodeCount, 50_004)
        for number in 0..<50_000 { XCTAssertTrue(index.containsAncestor(of: ["/", "Projects", "Assets", String(number), "child"])) }
        XCTAssertFalse(index.containsAncestor(of: ["/", "Projects", "Assets", "absent"]))
    }
    func testIndependentRootsPreserveSymlinkRootBoundary() throws {
        let manager = FileManager.default, root = manager.temporaryDirectory.appendingPathComponent("Roots-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let directory = root.appendingPathComponent("folder"), child = directory.appendingPathComponent("file.txt"), link = root.appendingPathComponent("link")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true); try Data().write(to: child)
        try manager.createSymbolicLink(at: link, withDestinationURL: directory)
        XCTAssertEqual(FileNames.independentRoots([directory, child, child]).map(\.path), [directory.path])
        let independent = FileNames.independentRoots([link, link.appendingPathComponent("file.txt")])
        XCTAssertEqual(independent.count, 2, "Selecting a symlink does not recursively copy its target")
    }
}
