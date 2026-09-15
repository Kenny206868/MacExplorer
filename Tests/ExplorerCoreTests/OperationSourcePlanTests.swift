import XCTest
@testable import ExplorerCore

final class OperationSourcePlanTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SourcePlan-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    func testParentsSuppressChildrenWithoutConfusingPrefixNeighbors() throws {
        let root = try fixture(), parent = root.appendingPathComponent("Documents"), child = parent.appendingPathComponent("Nested/file")
        try FileManager.default.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: child)
        let neighbor = root.appendingPathComponent("Documents-other"); try Data().write(to: neighbor)
        let result = try OperationSourcePlan.roots([child, neighbor, parent, child], checkingCancellation: {})
        XCTAssertEqual(result.map(\.path), [neighbor.path, parent.path])
    }
    func testSelectedSymlinksAreObjectsAndDoNotHideOutsideContent() throws {
        let root = try fixture(), parent = root.appendingPathComponent("Parent"), outside = root.appendingPathComponent("Outside")
        for url in [parent, outside] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        let file = outside.appendingPathComponent("file"); try Data().write(to: file)
        let link = parent.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let explicit = link.appendingPathComponent("file")
        let roots = try OperationSourcePlan.roots([parent, link, explicit], checkingCancellation: {})
        XCTAssertEqual(roots.map(\.path), [parent.path, explicit.path])
        let reverse = root.appendingPathComponent("ReverseLink")
        try FileManager.default.createSymbolicLink(at: reverse, withDestinationURL: parent)
        let preserved = try OperationSourcePlan.roots([parent, reverse], checkingCancellation: {})
        XCTAssertEqual(preserved.map(\.path), [parent.path, reverse.path], "A separate link into a selected folder remains selected")
        let unique = try OperationSourcePlan.roots([explicit, outside.appendingPathComponent("file")], checkingCancellation: {})
        XCTAssertEqual(unique.map(\.path), [explicit.path], "Parent aliases identify one leaf without following leaf links")
    }
    func testLargeDisjointSelectionDoesNotPerformPairwiseContainment() throws {
        let root = try fixture(), urls = (0..<4000).map { root.appendingPathComponent("missing-\($0)") }
        var checkpoints = 0
        let result = try OperationSourcePlan.roots(urls, checkingCancellation: { checkpoints += 1 })
        XCTAssertEqual(result, urls); XCTAssertLessThan(checkpoints, 12_000)
        XCTAssertThrowsError(try OperationSourcePlan.roots(urls, checkingCancellation: { throw CancellationError() }))
        XCTAssertThrowsError(try OperationSourcePlan.roots([URL(string: "https://example.invalid/a")!], checkingCancellation: {}))
    }
    func testCutCoverageHandlesManyRootsWithoutDiskAccess() {
        let roots = (0..<20_000).map { URL(fileURLWithPath: "/fixtures/Folder\($0)") }
        let coverage = FilePathCoverage(roots: roots)
        for index in 0..<20_000 {
            XCTAssertTrue(coverage.contains(roots[index]))
            XCTAssertTrue(coverage.contains(roots[index].appendingPathComponent("child/file")))
            XCTAssertFalse(coverage.contains(URL(fileURLWithPath: roots[index].path + "-neighbor")))
        }
        XCTAssertFalse(FilePathCoverage(roots: []).contains(URL(fileURLWithPath: "/")))
        XCTAssertTrue(FilePathCoverage(roots: [URL(fileURLWithPath: "/")]).contains(URL(fileURLWithPath: "/anything")))
    }
    @MainActor func testJobConstructionCapturesIntentWithoutFilesystemPlanning() {
        let source = URL(fileURLWithPath: "/unmounted-volume/missing/file")
        let sources = Array(repeating: source, count: 10_000)
        let job = FileJob(.copy, sources: sources, destination: URL(fileURLWithPath: "/destination"))
        XCTAssertEqual(job.sources, sources, "Input capture must not synchronously resolve or deduplicate filesystem roots")
    }
    func testEngineNormalizesParentAndDuplicateSelectionsBeforeMutation() async throws {
        let root = try fixture(), parent = root.appendingPathComponent("Input"), destination = root.appendingPathComponent("Output")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let child = parent.appendingPathComponent("file.txt"); try Data("one copy".utf8).write(to: child)
        let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("Recovery"))
        let result = await engine.run(FileJob(.copy, sources: [child, parent, child], destination: destination), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertTrue(result.errors.isEmpty, result.errors.description)
        XCTAssertEqual(result.completedSources.map(\.path), [parent.path])
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Input/file.txt")), "one copy")
        XCTAssertFalse(FileNames.exists(destination.appendingPathComponent("file.txt")))
    }
}
