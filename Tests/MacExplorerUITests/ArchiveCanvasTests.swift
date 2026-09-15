import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class ArchiveCanvasTests: XCTestCase {
    @MainActor func testVirtualArchiveUsesAnUnstripedCanvasWithNativeSelection() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveCanvas-" + UUID().uuidString)
        let folder = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("visible row".utf8).write(to: folder.appendingPathComponent("Readme.txt"))
        let archive = try ArchiveService.compress([folder], to: root, control: OperationControl())
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.archive(archive, folder: "Documents")), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop()
        let model = ArchiveLocationModel(source: archive)
        model.show(folder: "Documents", query: ""); await model.scan()
        let host = NSHostingView(rootView: ArchiveLocationView(workspace: owner, tab: owner.current, source: archive, folder: "Documents", model: model).frame(width: 820, height: 560))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; owner.window = window; window.orderFrontRegardless()
        defer { model.stop(); owner.current.stop(); window.orderOut(nil); window.contentView = nil; window.close() }
        let deadline = ContinuousClock.now + .seconds(3)
        while table(in: host) == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        host.layoutSubtreeIfNeeded()
        let native = try XCTUnwrap(table(in: host), "The production archive Table must be present")
        XCTAssertFalse(native.usesAlternatingRowBackgroundColors, "The virtual archive must not draw empty zebra rows")
        XCTAssertEqual(native.numberOfRows, 1)
        model.selection = ["Documents/Readme.txt"]
        let selectedDeadline = ContinuousClock.now + .seconds(3)
        while native.selectedRowIndexes.count != 1 && ContinuousClock.now < selectedDeadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(native.selectedRowIndexes.count, 1, "Removing empty stripes must preserve native selection")
    }
    @MainActor private func table(in view: NSView) -> NSTableView? {
        if let value = view as? NSTableView { return value }
        return view.subviews.lazy.compactMap { self.table(in: $0) }.first
    }
}
