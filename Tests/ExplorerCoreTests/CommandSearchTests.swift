import XCTest
@testable import ExplorerCore

final class CommandSearchTests: XCTestCase {
    private let index = CommandSearch([
        .init(id: "new", title: "New Folder", category: "Files", aliases: "create directory mkdir"),
        .init(id: "open", title: "Open Folder", category: "Navigation", aliases: "browse directory"),
        .init(id: "dual", title: "Toggle Dual Panes", category: "Layout", aliases: "split commander side by side"),
        .init(id: "preview", title: "Preview Pane", category: "View", aliases: "quick look")
    ])
    func testExactPrefixAliasAndSubsequenceRanking() {
        XCTAssertEqual(index.results(for: "new folder").first?.id, "new")
        XCTAssertEqual(index.results(for: "directory new").map(\.id), ["new"])
        XCTAssertEqual(index.results(for: "mkdir").map(\.id), ["new"])
        XCTAssertEqual(index.results(for: "tgl dl").map(\.id), ["dual"])
        XCTAssertEqual(index.results(for: "preview").first?.id, "preview")
        XCTAssertTrue(index.results(for: "new nonexistent").isEmpty)
    }
    func testOrderingIsStableAndLimitsAreClamped() {
        XCTAssertEqual(index.results(for: "").map(\.id), ["new", "open", "dual", "preview"])
        XCTAssertEqual(index.results(for: "directory").map(\.id), ["new", "open"])
        XCTAssertEqual(index.results(for: " ", limit: 1).map(\.id), ["new"])
        XCTAssertTrue(index.results(for: "", limit: -5).isEmpty)
        XCTAssertEqual(index.results(for: "", limit: Int.max).count, 4)
    }
    func testUnicodeNormalizationAndDuplicateIDs() {
        let value = CommandSearch([
            .init(id: "a", title: "Café 日本語", category: "資料"),
            .init(id: "a", title: "Duplicate", category: ""),
            .init(id: "b", title: "Ｆｏｌｄｅｒ", category: "View")
        ])
        XCTAssertEqual(value.results(for: "CAFE").first?.id, "a")
        XCTAssertEqual(value.results(for: "日本語").first?.id, "a")
        XCTAssertEqual(value.results(for: "folder").first?.id, "b")
        XCTAssertEqual(value.results(for: "").count, 2)
    }
    func testOversizedQueryRemainsBounded() {
        XCTAssertTrue(index.results(for: String(repeating: "🗂", count: 100_000)).isEmpty)
        for _ in 0..<100 { XCTAssertEqual(index.results(for: "side by side").first?.id, "dual") }
    }
}
