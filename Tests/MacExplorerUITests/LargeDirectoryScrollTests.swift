import XCTest
import SwiftUI
import AppKit
import QuartzCore
import ExplorerCore
@testable import MacExplorer

final class LargeDirectoryScrollTests: XCTestCase {
    struct Timing: Codable {
        let samples: Int
        let medianMilliseconds: Double
        let p95Milliseconds: Double
        let maximumMilliseconds: Double
        init(_ values: [Double]) {
            let sorted = values.sorted(); samples = sorted.count
            medianMilliseconds = sorted[sorted.count / 2]
            p95Milliseconds = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
            maximumMilliseconds = sorted.last ?? 0
        }
    }
    struct Evidence: Codable {
        let schemaVersion = 2
        let buildConfiguration: String
        let entries: Int
        let maximumLiveRowAnchors: Int
        let selectionBodyEvaluations: UInt64
        let selectionLayout: Timing
        let scrollLayout: Timing
        let continuousScrollLayout: Timing
        let keyDispatch: Timing
        let notes: String
    }
    @MainActor func testLargeDetailsViewKeepsRowsLazyAndSelectionLocalized() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native CI performance evidence") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LargeDirectory-" + UUID().uuidString)
        try await FileReadExecutor.browsing.run { cancellation in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for index in 0..<2000 {
                try cancellation.check()
                try Data().write(to: root.appendingPathComponent("Document \(index).txt"))
            }
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = PreferenceStore.shared, saved = PreferenceStore.shared.value
        let oldColumns = DetailsColumnStore.shared.value
        let touch = InputPreferences.shared.touchFriendly
        preferences.value.compact = false; preferences.value.checkboxes = false
        DetailsColumnStore.shared.value = DetailsColumns(); InputPreferences.shared.touchFriendly = false
        defer { preferences.value = saved; DetailsColumnStore.shared.value = oldColumns; InputPreferences.shared.touchFriendly = touch }
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        let tab = workspace.current
        tab.refresh()
        let deadline = ContinuousClock.now + .seconds(15)
        while tab.loading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(tab.loading); XCTAssertEqual(tab.entries.count, 2000); XCTAssertNil(tab.error)
        tab.watcher.stop()
        let initialAnchors = FileDragRouter.shared.liveAnchorCount
        let host = NSHostingView(rootView: FileDetailsTable(workspace: workspace, tab: tab)
            .environmentObject(preferences).frame(width: 1100, height: 600))
        let window = ScrollTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; workspace.window = window
        window.contentView = host; window.makeKeyAndOrderFront(nil); AppRouter.shared.active = workspace
        defer { tab.stop(); window.orderOut(nil); window.contentView = nil; window.close(); AppRouter.shared.active = nil }
        try await Task.sleep(for: .milliseconds(350)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let scroll = try XCTUnwrap(findScroll(host)), clip = scroll.contentView
        var maximumAnchors = max(0, FileDragRouter.shared.liveAnchorCount - initialAnchors)
        XCTAssertGreaterThan(maximumAnchors, 0, "Real file rows must be mounted")
        let builds = tab.presentationBuilds, reads = tab.refreshStarts
        let rows = tab.displayEntries
        var selectTimes: [Double] = [], scrollTimes: [Double] = [], continuousTimes: [Double] = [], keyTimes: [Double] = []
        let beforeBodies = FileRenderDiagnostics.detailsRowBodies
        for index in 0..<12 {
            let start = CACurrentMediaTime()
            workspace.select(rows[index % 2].url, extend: false, range: false)
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
            selectTimes.append((CACurrentMediaTime() - start) * 1000)
            try await Task.sleep(for: .milliseconds(16))
        }
        let selectionBodies = FileRenderDiagnostics.detailsRowBodies - beforeBodies
        #if DEBUG || MACEXPLORER_PERFORMANCE_DIAGNOSTICS
        XCTAssertGreaterThan(selectionBodies, 0, "The rendering counter must actually be enabled")
        #endif
        XCTAssertLessThan(selectionBodies, 240, "Selection must not reevaluate every retained file row")
        for index in 1...16 {
            let start = CACurrentMediaTime()
            clip.scroll(to: NSPoint(x: 0, y: index * 180)); scroll.reflectScrolledClipView(clip)
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
            scrollTimes.append((CACurrentMediaTime() - start) * 1000)
            try await Task.sleep(for: .milliseconds(16))
            maximumAnchors = max(maximumAnchors, FileDragRouter.shared.liveAnchorCount - initialAnchors)
        }
        XCTAssertGreaterThan(clip.bounds.origin.y, 1000, "The production scroll view must actually move")
        // Separately record small continuous deltas over an already visited
        // region. Large cold jumps and steady scrolling are different workloads.
        clip.scroll(to: NSPoint(x: 0, y: 720)); scroll.reflectScrolledClipView(clip)
        try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
        let selectionBeforeScroll = tab.selection
        for index in 1...120 {
            let start = CACurrentMediaTime()
            clip.scroll(to: NSPoint(x: 0, y: 720 + index * 6)); scroll.reflectScrolledClipView(clip)
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
            continuousTimes.append((CACurrentMediaTime() - start) * 1000)
            try await Task.sleep(for: .milliseconds(8))
            maximumAnchors = max(maximumAnchors, FileDragRouter.shared.liveAnchorCount - initialAnchors)
        }
        XCTAssertEqual(tab.selection, selectionBeforeScroll, "Scrolling must not mutate selected files")
        XCTAssertLessThan(maximumAnchors, 500, "A short scroll cannot eagerly mount an entire directory")
        workspace.focusFileSurface()
        for index in 0..<200 {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: Double(index),
                windowNumber: window.windowNumber, context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: index > 0, keyCode: 125))
            let start = CACurrentMediaTime()
            XCTAssertNil(KeyboardRouter.handle(event))
            keyTimes.append((CACurrentMediaTime() - start) * 1000)
        }
        XCTAssertEqual(tab.presentationBuilds, builds, "Scrolling and input do not sort the listing")
        XCTAssertEqual(tab.refreshStarts, reads, "Scrolling and input do not enumerate the filesystem")
        #if DEBUG
        let configuration = "debug"
        #elseif MACEXPLORER_PERFORMANCE_DIAGNOSTICS
        let configuration = "release-instrumented"
        #else
        let configuration = "release-no-render-counters"
        #endif
        let report = Evidence(buildConfiguration: configuration, entries: rows.count, maximumLiveRowAnchors: maximumAnchors,
            selectionBodyEvaluations: selectionBodies, selectionLayout: Timing(selectTimes), scrollLayout: Timing(scrollTimes),
            continuousScrollLayout: Timing(continuousTimes), keyDispatch: Timing(keyTimes),
            notes: "Shared-runner CPU diagnostics: actual NSScrollView layout/display and NSEvent key dispatch. Large jumps are 180 points; continuous deltas are 6 points. Explicit CATransaction flushing is included. Not input-to-photon latency, GPU completion, display cadence or hardware refresh-rate certification.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try encoder.encode(report).write(to: output.appendingPathComponent("large-directory-performance.json"), options: .atomic)
    }
    @MainActor private func findScroll(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView != nil { return scroll }
        return view.subviews.lazy.compactMap { self.findScroll($0) }.first
    }
}
@MainActor private final class ScrollTestWindow: NSWindow { override var canBecomeKey: Bool { true } }
