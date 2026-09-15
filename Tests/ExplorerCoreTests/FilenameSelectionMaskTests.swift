import XCTest
@testable import ExplorerCore

final class FilenameSelectionMaskTests: XCTestCase {
    func testIncludesExcludesAndCommanderAllFilesConvention() throws {
        let mask = try FilenameSelectionMask("*.swift; *.cs | *.g.cs;Generated*")
        XCTAssertTrue(mask.matches("Program.cs")); XCTAssertTrue(mask.matches("View.SWIFT"))
        XCTAssertFalse(mask.matches("Bindings.g.cs")); XCTAssertFalse(mask.matches("GeneratedView.swift"))
        XCTAssertFalse(mask.matches("README.md"))
        XCTAssertTrue(try FilenameSelectionMask("*.*").matches("LICENSE"))
        XCTAssertFalse(try FilenameSelectionMask("|*.tmp").matches("cache.tmp"))
        XCTAssertTrue(try FilenameSelectionMask("|*.tmp").matches("README"))
    }
    func testUnicodeGraphemesCanonicalEquivalenceAndLiteralMetacharacters() throws {
        XCTAssertTrue(try FilenameSelectionMask("?.txt").matches("e\u{301}.txt"))
        XCTAssertTrue(try FilenameSelectionMask("?.txt").matches("👨‍👩‍👧‍👦.txt"))
        XCTAssertTrue(try FilenameSelectionMask("É*.txt").matches("e\u{301}cole.txt"))
        XCTAssertFalse(try FilenameSelectionMask("A*", caseSensitive: true).matches("abc"))
        XCTAssertTrue(try FilenameSelectionMask("[draft](1).txt").matches("[draft](1).txt"))
        XCTAssertFalse(try FilenameSelectionMask("a?c").matches("ac"))
        XCTAssertTrue(try FilenameSelectionMask("a**?*c").matches("abc"))
    }
    func testLimitsAndInvalidInput() {
        for source in ["", "  ", "a|b|c", "folder/*.txt", "a\0b", String(repeating: "?", count: 257), Array(repeating: "*.cs", count: 33).joined(separator: ";")] {
            XCTAssertThrowsError(try FilenameSelectionMask(source), source)
        }
    }
    func testAdversarialWildcardAndLongNamesRemainDeterministic() throws {
        let mask = try FilenameSelectionMask(String(repeating: "*a", count: 100) + "b")
        for _ in 0..<20 { XCTAssertFalse(mask.matches(String(repeating: "a", count: 255))) }
        XCTAssertTrue(try FilenameSelectionMask("*").matches(""))
    }
    func testStatisticsExcludeFolderContentsClampNegativesAndSaturate() {
        var value = SelectionStatistics()
        value.include(isDirectory: true, byteCount: 9_000)
        value.include(isDirectory: false, byteCount: -1)
        value.include(isDirectory: false, byteCount: .max)
        value.include(isDirectory: false, byteCount: 1)
        XCTAssertEqual(value.count, 4); XCTAssertEqual(value.folders, 1); XCTAssertEqual(value.files, 3)
        XCTAssertEqual(value.bytes, .max); XCTAssertTrue(value.overflowed)
    }
}
