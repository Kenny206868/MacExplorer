import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import ExplorerCore

final class DirectoryComparisonTests: XCTestCase {
    private struct Fixture {
        let root: URL, left: URL, right: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Compare-" + UUID().uuidString)
            left = root.appendingPathComponent("First"); right = root.appendingPathComponent("Second")
            try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        }
        func write(_ name: String, _ text: String, into folder: URL, date: TimeInterval = 1_700_000_000) throws {
            let file = folder.appendingPathComponent(name)
            try Data(text.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: date)], ofItemAtPath: file.path)
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
        func request(_ mode: ComparisonMode = .metadata) -> ComparisonRequest { var r = ComparisonRequest(left: left, right: right); r.mode = mode; return r }
    }
    func testMetadataNeverPretendsToVerifyContent() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("same-size.txt", "aaaa", into: f.left); try f.write("same-size.txt", "bbbb", into: f.right)
        try f.write("left.txt", "left", into: f.left); try f.write("right.txt", "right", into: f.right)
        let report = try DirectoryComparison.compare(f.request())
        XCTAssertEqual(report.rows.first { $0.name == "same-size.txt" }?.status, .metadataMatch)
        XCTAssertEqual(report.rows.first { $0.name == "left.txt" }?.status, .leftOnly)
        XCTAssertEqual(report.rows.first { $0.name == "right.txt" }?.status, .rightOnly)
        XCTAssertEqual(report.bytesRead, 0)
        let data = try DirectoryComparison.compare(f.request(.contents))
        XCTAssertEqual(data.rows.first { $0.name == "same-size.txt" }?.status, .different)
        XCTAssertEqual(data.bytesRead, 8)
    }
    func testByteComparisonIgnoresDatesButPreservesBothFiles() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let payload = String(repeating: "0123456789", count: 90_000)
        try f.write("data.bin", payload, into: f.left, date: 1_700_000_000)
        try f.write("data.bin", payload, into: f.right, date: 1_700_000_050)
        let first = try ComparisonStamp.read(f.left.appendingPathComponent("data.bin")), second = try ComparisonStamp.read(f.right.appendingPathComponent("data.bin"))
        XCTAssertEqual(try DirectoryComparison.compare(f.request()).rows.first?.status, .different)
        let report = try DirectoryComparison.compare(f.request(.contents))
        XCTAssertEqual(report.rows.first?.status, .matchingData)
        XCTAssertEqual(report.bytesRead, Int64(payload.utf8.count * 2))
        XCTAssertEqual(try ComparisonStamp.read(f.left.appendingPathComponent("data.bin")), first)
        XCTAssertEqual(try ComparisonStamp.read(f.right.appendingPathComponent("data.bin")), second)
        try report.validate(report.rows)
    }
    func testFoldersLinksAndSpecialFilesAreNotTraversed() throws {
        let f = try Fixture(); defer { f.cleanup() }
        for folder in [f.left, f.right] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("link").path, withDestinationPath: ".")
            XCTAssertEqual(mkfifo(folder.appendingPathComponent("pipe").path, 0o600), 0)
        }
        try f.write("inside.txt", "different inside", into: f.left.appendingPathComponent("nested"))
        let result = try DirectoryComparison.compare(f.request(.contents))
        XCTAssertEqual(result.rows.count, 3); XCTAssertTrue(result.rows.allSatisfy { $0.status == .notCompared })
        XCTAssertEqual(result.bytesRead, 0)
    }
    func testTypeConflictHiddenPolicyAndCaseMatching() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("conflict", "file", into: f.left)
        try FileManager.default.createDirectory(at: f.right.appendingPathComponent("conflict"), withIntermediateDirectories: false)
        try f.write(".secret", "hidden", into: f.left)
        try f.write("Report.txt", "same", into: f.left); try f.write("report.txt", "same", into: f.right)
        let exact = try DirectoryComparison.compare(f.request())
        XCTAssertEqual(exact.rows.count, 3); XCTAssertEqual(exact.rows.first { $0.name == "conflict" }?.status, .typeConflict)
        var options = f.request(.contents); options.namePolicy = .ignoreCase; options.includeHidden = true
        let result = try DirectoryComparison.compare(options)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.rows.first { $0.name == "Report.txt" }?.status, .matchingData)
        XCTAssertEqual(result.rows.first { $0.name == ".secret" }?.status, .leftOnly)
    }
    func testAmbiguousNamesAreNeverSilentlyPaired() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("A.txt", "one", into: f.left)
        if FileManager.default.fileExists(atPath: f.left.appendingPathComponent("a.txt").path) { throw XCTSkip("Requires a case-sensitive filesystem") }
        try f.write("a.txt", "two", into: f.left); try f.write("a.txt", "two", into: f.right)
        var request = f.request(.contents); request.namePolicy = .ignoreCase
        let report = try DirectoryComparison.compare(request)
        XCTAssertEqual(report.rows.count, 1); XCTAssertEqual(report.rows[0].status, .ambiguous)
        XCTAssertEqual(report.rows[0].left.count, 2); XCTAssertEqual(report.bytesRead, 0)
    }
    func testReadBudgetAndListingLimitCannotYieldFalseMatches() throws {
        let f = try Fixture(); defer { f.cleanup() }
        for name in ["a", "b"] { try f.write(name, "hello", into: f.left); try f.write(name, "hello", into: f.right) }
        var request = f.request(.contents); request.maximumReadBytes = 10
        let result = try DirectoryComparison.compare(request)
        XCTAssertEqual(result.rows.map(\.status), [.matchingData, .notCompared]); XCTAssertEqual(result.bytesRead, 10)
        request.maximumEntriesPerFolder = 1
        XCTAssertThrowsError(try DirectoryComparison.compare(request))
        request.maximumEntriesPerFolder = 0
        XCTAssertThrowsError(try DirectoryComparison.compare(request))
    }
    func testChangedFilesAndRootReplacementInvalidateTheReport() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("a.txt", "original", into: f.left); try f.write("a.txt", "original", into: f.right)
        let report = try DirectoryComparison.compare(f.request(.contents))
        try f.write("a.txt", "newer", into: f.left)
        XCTAssertThrowsError(try report.validate(report.rows))
        try FileManager.default.moveItem(at: f.right, to: f.root.appendingPathComponent("Old"))
        try FileManager.default.createDirectory(at: f.right, withIntermediateDirectories: false)
        XCTAssertThrowsError(try report.validate([]))
    }
    func testReplacementWithSymlinkDuringCompareIsNotRead() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.write("file.txt", "original", into: f.left); try f.write("file.txt", "original", into: f.right)
        let secret = f.root.appendingPathComponent("private.txt"); try Data("private".utf8).write(to: secret)
        var changed = false
        XCTAssertThrowsError(try DirectoryComparison.compare(f.request(.contents), progress: { event in
            if !changed, event.name == "file.txt" {
                changed = true
                try? FileManager.default.removeItem(at: f.left.appendingPathComponent("file.txt"))
                try? FileManager.default.createSymbolicLink(at: f.left.appendingPathComponent("file.txt"), withDestinationURL: secret)
            }
        }))
        XCTAssertEqual(try String(contentsOf: secret), "private")
    }
    func testCancellationAtStartAndFinalProgressDoesNotReturnSuccess() throws {
        let f = try Fixture(); defer { f.cleanup() }
        XCTAssertThrowsError(try DirectoryComparison.compare(f.request(), checkpoint: { throw CancellationError() })) { XCTAssertTrue($0 is CancellationError) }
        var cancelled = false
        XCTAssertThrowsError(try DirectoryComparison.compare(f.request(), checkpoint: { if cancelled { throw CancellationError() } }, progress: { if $0.name == "Finished" { cancelled = true } })) { XCTAssertTrue($0 is CancellationError) }
    }
}
