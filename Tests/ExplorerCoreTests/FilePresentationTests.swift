import XCTest
@testable import ExplorerCore

final class FilePresentationTests: XCTestCase {
    func testSparseAndDenseSelectionsFollowPresentedOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = try (0..<32).reversed().map { index -> FileEntry in
            let url = root.appendingPathComponent("file\(index).txt")
            try Data().write(to: url); return try FileEntry(url: url)
        }
        let projection = FilePresentation(entries: entries, options: FolderOptions())
        XCTAssertEqual(projection.sorted.first?.name, "file0.txt")
        for count in [0, 1, 3, 8, 31, 32] {
            let selection = Set(entries.prefix(count).map(\.url))
            XCTAssertEqual(projection.selected(selection), projection.ordered.filter { selection.contains($0.url) })
        }
        XCTAssertTrue(projection.selected([root.appendingPathComponent("missing")]).isEmpty)
    }
    func testModifiedGroupsAreChronologicalRatherThanAlphabetical() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.locale = Locale(identifier: "en_US_POSIX")
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12))!
        let dates = [now.addingTimeInterval(-86400), now, calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!, calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!]
        let entries = try dates.enumerated().map { index, date -> FileEntry in
            let url = root.appendingPathComponent("file\(index).txt")
            try Data().write(to: url); try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            return try FileEntry(url: url)
        }
        var options = FolderOptions(); options.group = .modified
        let result = FilePresentation(entries: entries, options: options, calendar: calendar, now: now)
        XCTAssertEqual(result.groups.map(\.title), ["Today", "Yesterday", "August 2026", "January 2026"])
        XCTAssertEqual(result.ordered.map(\.name), ["file1.txt", "file0.txt", "file3.txt", "file2.txt"])
    }
}
