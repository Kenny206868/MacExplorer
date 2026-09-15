import XCTest
import ExplorerCore
@testable import MacExplorer

final class ArchiveListingResponsivenessTests: XCTestCase {
    @MainActor func testSelectionDoesNotRebuildIndexAndStaleFiltersCannotWin() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveListing-" + UUID().uuidString)
        let input = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<240 { try Data("document".utf8).write(to: input.appendingPathComponent("file\(index).txt")) }
        let archive = try ArchiveService.compress([input], to: root, control: OperationControl())
        let model = ArchiveLocationModel(source: archive)
        defer { model.stop() }
        await model.scan(); model.show(folder: "Documents", query: "")
        XCTAssertEqual(model.listing.entries.count, 240)
        let builds = model.indexBuilds, projections = model.projectionBuilds
        for index in 0..<1000 {
            let path = "Documents/file\(index % 240).txt"
            model.selection = [path]
            XCTAssertEqual(model.selected.map(\.path), [path]); _ = model.listing; _ = model.editable
        }
        XCTAssertEqual(model.indexBuilds, builds)
        XCTAssertEqual(model.projectionBuilds, projections, "Selection must not re-enumerate, sort or filter")
        await model.scan()
        XCTAssertEqual(model.indexBuilds, builds, "An unchanged archive reuses its index across member-folder navigation")
        for index in 0..<60 { model.show(folder: "Documents", query: "file\(index)") }
        model.show(folder: "Documents", query: "file239.")
        let deadline = ContinuousClock.now + .seconds(4)
        while model.filtering && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.filtering)
        XCTAssertEqual(model.listing.entries.map(\.path), ["Documents/file239.txt"])
        model.show(folder: "", query: ""); XCTAssertEqual(model.listing.entries.map(\.path), ["Documents"])
        XCTAssertTrue(model.selection.isEmpty)
    }
}
