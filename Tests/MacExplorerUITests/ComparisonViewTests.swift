import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

@MainActor final class ComparisonFixture {
    let root: URL
    let workspace: ExplorerWorkspace
    let controller: DualPaneController
    let model: ComparisonModel
    private let preferences: Preferences
    private let input: Bool
    init() throws {
        _ = NSApplication.shared
        preferences = PreferenceStore.shared.value; input = InputPreferences.shared.touchFriendly
        InputPreferences.shared.touchFriendly = false; PreferenceStore.shared.value.showHidden = false
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Comparison-" + UUID().uuidString)
        let left = root.appendingPathComponent("Documents"), right = root.appendingPathComponent("Backup")
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        func write(_ name: String, _ text: String, _ folder: URL, _ time: TimeInterval = 1_700_000_000) throws {
            let url = folder.appendingPathComponent(name)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: time)], ofItemAtPath: url.path)
        }
        try write("Brand guidelines.md", "new version", left)
        try write("Brand guidelines.md", "old version", right)
        try write("Roadmap.md", "matching content", left)
        try write("Roadmap.md", "matching content", right, 1_710_000_000)
        try write("Design notes.txt", "first only", left)
        try write("Release checklist.md", "second only", right)
        try write("Project.json", "{\"version\":1}", left)
        try write("Project.json", "{\"version\":1}", right)
        try FileManager.default.createDirectory(at: left.appendingPathComponent("Assets"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: right.appendingPathComponent("Assets"), withIntermediateDirectories: false)
        try write("Conflict", "file", left)
        try FileManager.default.createDirectory(at: right.appendingPathComponent("Conflict"), withIntermediateDirectories: false)
        workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(left)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop()
        controller = DualPaneController(primary: workspace)
        workspace.dualPane = controller
        controller.secondary.current.history = NavigationHistory(.folder(right)); controller.secondary.current.stop()
        workspace.current.entries = try FileManager.default.contentsOfDirectory(at: left, includingPropertiesForKeys: nil).map { try FileEntry(url: $0) }
        controller.secondary.current.entries = try FileManager.default.contentsOfDirectory(at: right, includingPropertiesForKeys: nil).map { try FileEntry(url: $0) }
        model = ComparisonModel(workspace: workspace)
    }
    func cleanup() {
        model.cancel(); DeferredSheetAction.shared.cancel(for: workspace)
        workspace.tabs.forEach { $0.stop() }; controller.secondary.tabs.forEach { $0.stop() }
        AppRouter.shared.active = nil
        PreferenceStore.shared.value = preferences; InputPreferences.shared.touchFriendly = input
        try? FileManager.default.removeItem(at: root)
    }
}
final class ComparisonViewTests: XCTestCase {
    @MainActor func testFilteringMarksAndOptionInvalidationUseActualResults() async throws {
        let f = try ComparisonFixture(); defer { f.cleanup() }
        await f.model.compare()
        XCTAssertNil(f.model.error)
        let report = try XCTUnwrap(f.model.report)
        XCTAssertEqual(report.rows.count, 7)
        XCTAssertEqual(f.model.counts[.differences], 4)
        f.model.filter = .leftOnly
        XCTAssertEqual(f.model.visible.map(\.name), ["Design notes.txt"])
        f.model.markDifferences()
        XCTAssertEqual(f.model.markedFiles(.primary), 1); XCTAssertEqual(f.model.markedFiles(.secondary), 0)
        f.model.mode = .contents
        XCTAssertNil(f.model.report); XCTAssertTrue(f.model.marked.isEmpty)
        await f.model.compare()
        XCTAssertEqual(f.model.report?.rows.first { $0.name == "Roadmap.md" }?.status, .matchingData)
        XCTAssertEqual(f.model.report?.rows.first { $0.name == "Brand guidelines.md" }?.status, .different)
    }
    @MainActor func testSelectionRejectsChangedTabBeforeTouchingEitherPane() async throws {
        let f = try ComparisonFixture(); defer { f.cleanup() }
        await f.model.compare()
        let report = try XCTUnwrap(f.model.report), context = try XCTUnwrap(f.model.context)
        let rows = report.rows.filter { $0.status == .leftOnly }
        f.workspace.newTab(.computer); f.workspace.current.stop()
        do { try await ComparisonModel.apply(rows, from: report, context: context, side: .primary); XCTFail("A changed tab must reject report selection") }
        catch { XCTAssertTrue(f.workspace.current.selection.isEmpty); XCTAssertTrue(f.controller.secondary.current.selection.isEmpty) }
    }
    @MainActor func testResultSelectionHighlightsOnlyRequestedSourceAndNeverMovesFiles() async throws {
        let f = try ComparisonFixture(); defer { f.cleanup() }
        let jobs = f.workspace.operations.jobs.map(\.id)
        await f.model.compare()
        let report = try XCTUnwrap(f.model.report), context = try XCTUnwrap(f.model.context)
        let rows = report.rows.filter { $0.status == .leftOnly }
        try await ComparisonModel.apply(rows, from: report, context: context, side: .primary)
        for _ in 0..<100 where f.workspace.current.loading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(f.workspace.current.selection.map(\.lastPathComponent), ["Design notes.txt"])
        XCTAssertTrue(f.controller.secondary.current.selection.isEmpty)
        XCTAssertTrue(FileNames.exists(context.leftURL.appendingPathComponent("Design notes.txt")))
        XCTAssertFalse(FileNames.exists(context.rightURL.appendingPathComponent("Design notes.txt")))
        XCTAssertEqual(f.workspace.operations.jobs.map(\.id), jobs)
    }
    @MainActor func testNativeComparisonStates() async throws {
        guard let path = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture workflow only") }
        let f = try ComparisonFixture(); defer { f.cleanup() }
        let output = URL(fileURLWithPath: path)
        var captures: [NativeViewSnapshotTests.Capture] = []
        for dark in [false, true] {
            PreferenceStore.shared.value.theme = dark ? "dark" : "light"
            for state in ["comparison-metadata", "comparison-data", "comparison-empty"] {
                f.model.query = ""; f.model.filter = .all
                f.model.mode = state == "comparison-metadata" ? .metadata : .contents
                await f.model.compare(); XCTAssertNil(f.model.error)
                if state == "comparison-empty" { f.model.query = "nothing-matches-this-filter" }
                else { f.model.markDifferences() }
                let view = AnyView(ComparisonView(workspace: f.workspace, model: f.model))
                captures.append(try await NativeSnapshotCapture.render(view, named: (dark ? "dark-" : "light-") + state,
                    size: NSSize(width: 880, height: 670), dark: dark, output: output) { _ in
                    XCTAssertEqual(f.model.report?.rows.count, 7)
                    if state == "comparison-empty" { XCTAssertTrue(f.model.visible.isEmpty) }
                    else { XCTAssertFalse(f.model.visible.isEmpty) }
                    XCTAssertEqual(f.workspace.current.selection.count, 0)
                    XCTAssertEqual(f.controller.secondary.current.selection.count, 0)
                })
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("comparison-captures.json"), options: .atomic)
        XCTAssertEqual(captures.count, 6)
    }
}
