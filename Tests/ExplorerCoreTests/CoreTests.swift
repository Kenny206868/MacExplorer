import XCTest
@testable import ExplorerCore

final class CoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorerTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    private func file(_ name: String, text: String = "sample") throws -> URL {
        let url = root.appendingPathComponent(name); try Data(text.utf8).write(to: url, options: .withoutOverwriting); return url
    }
    func testNamesRejectTraversalAndSeparators() {
        for name in ["", ".", "..", "a/b", "a:b", "a\0b", String(repeating: "x", count: 256)] { XCTAssertThrowsError(try FileNames.validate(name)) }
        XCTAssertNoThrow(try FileNames.validate("工程 notes 2.swift"))
    }
    func testContainmentUsesPathComponents() {
        XCTAssertTrue(FileNames.isDescendant(root.appendingPathComponent("a/b"), of: root))
        XCTAssertFalse(FileNames.isDescendant(URL(fileURLWithPath: root.path + "-neighbor/file"), of: root))
    }
    func testHistoryTruncatesForwardBranch() {
        var h = NavigationHistory(.home); h.navigate(.computer); h.navigate(.network); h.back(); h.navigate(.trash)
        XCTAssertEqual(h.current, .trash); XCTAssertFalse(h.canGoForward); XCTAssertTrue(h.canGoBack)
        XCTAssertEqual(h.locations, [.home, .computer, .trash])
    }
    func testUniqueNamesPreserveExtension() throws { XCTAssertEqual(FileNames.unique(try file("Report.pdf")).lastPathComponent, "Report (2).pdf") }
    func testMetadataSearch() throws {
        let entry = try FileEntry(url: file("Quarterly report.pdf", text: String(repeating: "a", count: 2048)))
        XCTAssertTrue(SearchExpression("\"Quarterly report\" ext:pdf size:>1KB").matches(entry))
        XCTAssertFalse(SearchExpression("ext:png").matches(entry)); XCTAssertFalse(SearchExpression("size:<1KB").matches(entry))
    }
    func testNaturalSortAndFolderFirst() throws {
        let a = try FileEntry(url: file("file10.txt")), b = try FileEntry(url: file("file2.txt")), directory = root.appendingPathComponent("z-directory")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let c = try FileEntry(url: directory)
        XCTAssertEqual(FolderOptions().sorted([a, b, c]).map(\.name), ["z-directory", "file2.txt", "file10.txt"])
    }
    func testCancellationAndPauseRelease() {
        let control = OperationControl(); control.setPaused(true); control.cancel()
        XCTAssertTrue(control.isCancelled); XCTAssertThrowsError(try control.checkpoint())
    }
    func testSHA256Streaming() async throws {
        let hash = try await FileService().checksum(file("checksum.txt", text: "abc"))
        XCTAssertEqual(hash, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testCopyKeepBothAndReceipt() async throws {
        let source = try file("source.txt")
        let result = await FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")).run(FileJob(.copy, sources: [source], destination: root), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.keepBoth) })
        XCTAssertTrue(result.errors.isEmpty, result.errors.description); XCTAssertEqual(result.outputs.first?.lastPathComponent, "source (2).txt")
        XCTAssertEqual(result.receipt.steps.count, 1); XCTAssertTrue(FileNames.exists(source))
    }
    func testMoveAndUndo() async throws {
        let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")), source = try file("move.txt"), destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let result = await engine.run(FileJob(.move, sources: [source], destination: destination), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        XCTAssertTrue(result.errors.isEmpty, result.errors.description); XCTAssertFalse(FileNames.exists(source))
        let undone = await engine.undo(result.receipt, control: OperationControl())
        XCTAssertTrue(undone.errors.isEmpty, undone.errors.description); XCTAssertTrue(FileNames.exists(source))
    }
    func testChangedFileCannotBeUndone() async throws {
        let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")), source = try file("change.txt"), destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let result = await engine.run(FileJob(.move, sources: [source], destination: destination), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
        let output = try XCTUnwrap(result.outputs.first); try Data("newer contents are protected".utf8).write(to: output)
        let undone = await engine.undo(result.receipt, control: OperationControl())
        XCTAssertFalse(undone.errors.isEmpty); XCTAssertTrue(FileNames.exists(output))
    }
    func testRenameSwapsWithoutOverwriting() async throws {
        let a = try file("a.txt", text: "A"), b = try file("b.txt", text: "B")
        let result = await FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")).rename([(a, "b.txt"), (b, "a.txt")], control: OperationControl())
        XCTAssertTrue(result.errors.isEmpty, result.errors.description)
        XCTAssertEqual(try String(contentsOf: a), "B"); XCTAssertEqual(try String(contentsOf: b), "A")
    }
}
